import AppKit
import CoreGraphics
import os.log
@preconcurrency import ScreenCaptureKit

private let discoveryLog = Logger(subsystem: "dev.vantage.preview", category: "discovery")

/// Mirror of one on-screen window parsed from CGWindowListCopyWindowInfo.
/// Value-type and Sendable so it can cross actor boundaries safely.
struct DiscoveredWindow: Sendable {
    let windowID: CGWindowID
    let processIdentifier: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let title: String
    let layer: Int
    let frame: CGRect
}

struct SendablePreview: @unchecked Sendable {
    let cgImage: CGImage
    let size: NSSize
}

/// Box for handing an SCScreenshotManager-required SCWindow into a detached child
/// task without tripping Swift 6.3 sending-closure analysis (@unchecked mirrors
/// ScreenCaptureKit's own undeclared isolation, same as our @preconcurrency import).
private struct HandleBox: @unchecked Sendable {
    let scWindow: SCWindow?
}

@MainActor
final class WindowCaptureService: ObservableObject {
    @Published private(set) var windows: [CapturedWindow] = []
    @Published var selectedWindowID: CGWindowID?
    @Published private(set) var activeWindowID: CGWindowID?
    @Published private(set) var hasCompletedRefresh = false
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var lastRefresh: Date?
    /// True when a freshly-discovered window cannot be pixel-bound yet because
    /// SCK handle binding is timing out and backing off. Honest staleness signal.
    @Published private(set) var listStale = false
    @Published var activationError: WindowActivationError?

    private let settings: SettingsStore
    private var updateTask: Task<Void, Never>?
    private var refreshSequence = 0
    private var lastActiveUpdate = Date.distantPast

    // P1: Discovery uses cheap synchronous CGWindowList every cycle (no XPC,
    // no timeout class). SCShareableContent runs ONLY to bind the SCWindow handles
    // SCScreenshotManager requires, triggered when an unknown windowID appears,
    // with adaptive timeout/backoff. This removes hot-loop enumeration that caused
    // long-run stalls and stale-list "fake update" states.
    @preconcurrency private var scWindowsByID: [CGWindowID: SCWindow] = [:]
    private var lastHandleBindAttempt = Date.distantPast
    private var handleBindBackoffUntil = Date.distantPast
    private var consecutiveBindTimeouts = 0
    private var bindTimeoutMs = 2_000

    // Diagnostics throttle.
    private var lastDiscoveryLog = Date.distantPast
    private var lastCandidateCount = -1

    init(settings: SettingsStore) {
        self.settings = settings
    }

    var hasScreenCapturePermission: Bool {
        CGPreflightScreenCaptureAccess()
    }

    func start() {
        if let task = updateTask {
            if !task.isCancelled { return }
            updateTask = nil
        }

        updateTask = Task { @MainActor [weak self] in
            guard let self else { return }
            let clock = ContinuousClock()

            while !Task.isCancelled {
                let cycleStart = clock.now

                if !settings.isPaused {
                    await refresh()
                }

                updateActiveWindowID()

                guard !Task.isCancelled else { break }

                let elapsed = cycleStart.duration(to: clock.now)
                let remaining = settings.previewRefreshRate.interval - elapsed
                // Always sleep at least 50ms: when a cycle overruns its interval,
                // sleeping zero would busy-spin the MainActor and hammer WindowServer.
                do {
                    try await Task.sleep(for: max(remaining, .milliseconds(50)))
                } catch {
                    // Task cancelled — exit promptly instead of swallowing
                    break
                }
            }
        }
    }

    func stop() {
        updateTask?.cancel()
        updateTask = nil
    }

    func setRefreshRate(_ rate: PreviewRefreshRate) {
        guard settings.previewRefreshRate != rate else { return }
        settings.previewRefreshRate = rate

        guard updateTask != nil else { return }
        stop()
        start()
    }

    func requestScreenCapturePermission() {
        if CGRequestScreenCaptureAccess() {
            Task { await refresh() }
        } else {
            captureState = .permissionRequired
            openScreenCaptureSettings()
        }
    }

    func openScreenCaptureSettings() {
        let candidates = [
            "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture",
            "x-apple.systempreferences:com.apple.settings.PrivacySecurity.extension?Privacy_ScreenCapture"
        ]

        for rawURL in candidates {
            guard let url = URL(string: rawURL) else { continue }
            if NSWorkspace.shared.open(url) { break }
        }
    }

    // MARK: - Discovery (P1)

    nonisolated private static func doubleValue(_ any: Any?) -> Double? {
        switch any {
        case let n as NSNumber: return n.doubleValue
        case let d as Double: return d
        case let i as Int: return Double(i)
        default: return nil
        }
    }

    /// Parses one raw CGWindowList entry. Static pure function so tests can feed fixtures.
    nonisolated static func parseDiscovered(
        _ info: [String: Any],
        bundleResolver: (pid_t) -> String?
    ) -> DiscoveredWindow? {
        guard let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else { return nil }
        guard let pid = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value else { return nil }

        guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
              let x = doubleValue(bounds["X"]),
              let y = doubleValue(bounds["Y"]),
              let width = doubleValue(bounds["Width"]),
              let height = doubleValue(bounds["Height"]) else {
            return nil
        }

        return DiscoveredWindow(
            windowID: CGWindowID(number),
            processIdentifier: pid,
            ownerName: info[kCGWindowOwnerName as String] as? String ?? "",
            bundleIdentifier: bundleResolver(pid),
            title: info[kCGWindowName as String] as? String ?? "",
            layer: (info[kCGWindowLayer as String] as? NSNumber)?.intValue ?? 0,
            frame: CGRect(x: x, y: y, width: width, height: height)
        )
    }

    /// Full discovery pipeline: parse, eligibility filter, deterministic sort, cap at 12.
    nonisolated static func discoverWindows(
        raw: [[String: Any]],
        bundleResolver: @escaping (pid_t) -> String?,
        ownerAllowlist: [String],
        bundleAllowlist: [String]
    ) -> [DiscoveredWindow] {
        Array(
            raw.compactMap { parseDiscovered($0, bundleResolver: bundleResolver) }
                .filter { d in
                    guard d.processIdentifier > 0 else { return false }
                    guard WindowFilter.isNormalWindow(
                        isOnScreen: true,
                        windowLayer: d.layer,
                        title: d.title.isEmpty ? nil : d.title,
                        frame: d.frame
                    ) else {
                        return false
                    }
                    return WindowFilter.isEligible(
                        ownerName: d.ownerName,
                        bundleIdentifier: d.bundleIdentifier,
                        exactBundleIdentifiers: bundleAllowlist,
                        exactOwnerNames: ownerAllowlist
                    )
                }
                .sorted { lhs, rhs in
                    if lhs.ownerName == rhs.ownerName {
                        if lhs.title == rhs.title {
                            if lhs.frame.origin.y == rhs.frame.origin.y {
                                return lhs.frame.origin.x < rhs.frame.origin.x
                            }
                            return lhs.frame.origin.y < rhs.frame.origin.y
                        }
                        return lhs.title < rhs.title
                    }
                    return lhs.ownerName < rhs.ownerName
                }
                .prefix(12)
        )
    }

    private func logDiscoverySummary(totalOnScreen: Int, discovered: [DiscoveredWindow]) {
        let now = Date.now
        let countChanged = discovered.count != lastCandidateCount
        guard countChanged || now.timeIntervalSince(lastDiscoveryLog) >= 5.0 else { return }
        lastCandidateCount = discovered.count
        lastDiscoveryLog = now
        discoveryLog.info("discovered=\(discovered.count, privacy: .public) totalOnScreen=\(totalOnScreen, privacy: .public)")
    }

    // MARK: - Refresh cycle

    func refresh() async {
        // P1-4: Skip capture while paused and keep the previous frame.
        guard !settings.isPaused else { return }
        refreshSequence += 1
        let sequence = refreshSequence

        guard CGPreflightScreenCaptureAccess() else {
            windows = []
            selectedWindowID = nil
            activeWindowID = nil
            captureState = .permissionRequired
            return
        }

        // Keep the ready state stable during background refreshes. The initial
        // scan still exposes a loading state, but periodic thumbnail updates
        // should not make the status bar alternate between two labels.
        if !hasCompletedRefresh {
            captureState = .refreshing
        }

        // ---- Cheap synchronous discovery every cycle (P1). Microseconds; no XPC,
        // no timeout class. New windows are visible within one refresh period.
        let rawInfo = (CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID) as? [[String: Any]]) ?? []
        let discovered = Self.discoverWindows(
            raw: rawInfo,
            bundleResolver: { pid in NSRunningApplication(processIdentifier: pid)?.bundleIdentifier },
            ownerAllowlist: settings.exactOwnerNameList,
            bundleAllowlist: settings.exactBundleIdentifierList
        )
        logDiscoverySummary(totalOnScreen: rawInfo.count, discovered: discovered)

        // ---- Bind SCK handles only when an unknown windowID appeared (rare event).
        let unknownIDs = discovered.filter { scWindowsByID[$0.windowID] == nil }.map(\.windowID)
        var bindFailed = false
        if !unknownIDs.isEmpty, Date.now >= handleBindBackoffUntil,
           Date.now.timeIntervalSince(lastHandleBindAttempt) >= 0.5 {
            lastHandleBindAttempt = Date.now
            do {
                let content = try await withTimeout(.milliseconds(bindTimeoutMs)) {
                    try await SCShareableContent.excludingDesktopWindows(
                        true,
                        onScreenWindowsOnly: true
                    )
                }
                guard sequence == refreshSequence else { return }
                scWindowsByID = Dictionary(content.windows.map { ($0.windowID, $0) },
                                           uniquingKeysWith: { _, new in new })
                consecutiveBindTimeouts = 0
                bindTimeoutMs = 2_000
                discoveryLog.info("handle bind ok windows=\(content.windows.count, privacy: .public)")
            } catch is TimeoutError {
                bindFailed = true
                consecutiveBindTimeouts += 1
                bindTimeoutMs = min(bindTimeoutMs * 2, 8_000)
                let backoffSeconds = min(Double(consecutiveBindTimeouts) * 2.0, 15.0)
                handleBindBackoffUntil = Date.now.addingTimeInterval(backoffSeconds)
                discoveryLog.error("handle bind TIMEOUT #\(self.consecutiveBindTimeouts, privacy: .public) backoff=\(Int(backoffSeconds), privacy: .public)s pendingIDs=\(unknownIDs.count, privacy: .public)")
            } catch {
                bindFailed = true
                discoveryLog.error("handle bind error \(error.localizedDescription, privacy: .public)")
            }
        }

        // P0 truth-telling: staleness only when freshly discovered IDs still lack
        // pixel-bound handles because binding is backing off.
        listStale = bindFailed && !unknownIDs.isEmpty

        // ---- Snapshot MainActor state before entering concurrent captures.
        // Unbound IDs skip capture fast instead of burning per-window timeouts.
        let captureJobs: [(window: DiscoveredWindow, handle: HandleBox)] = discovered.map {
            ($0, HandleBox(scWindow: scWindowsByID[$0.windowID]))
        }

        // ---- Concurrent per-window preview capture (800ms each).
        var previewMap: [CGWindowID: SendablePreview?] = [:]
        do {
            try await withThrowingTaskGroup(of: (CGWindowID, SendablePreview?).self) { group in
                for job in captureJobs {
                    let window = job.window
                    let box = job.handle
                    group.addTask {
                        guard let handle = box.scWindow else {
                            // No SCK handle yet — skip fast, preview stays nil this cycle.
                            return (window.windowID, nil)
                        }
                        let preview: SendablePreview? = try? await withTimeout(.milliseconds(800)) {
                            try await WindowCaptureService.capturePreview(of: window, scWindow: handle)
                        }
                        return (window.windowID, preview)
                    }
                }
                for try await (wid, preview) in group {
                    if Task.isCancelled { group.cancelAll(); break }
                    previewMap[wid] = preview
                }
            }
        } catch is TimeoutError {
            // Capture-phase timeout cannot happen per-window (children swallow);
            // a group-level timeout only surfaces from infrastructure — treat as failure.
            if !hasCompletedRefresh {
                captureState = .failed("Preview capture timed out")
            }
            return
        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }
            if !hasCompletedRefresh {
                captureState = .failed(error.localizedDescription)
            }
            return
        }

        guard sequence == refreshSequence else { return }
        if Task.isCancelled { return }

        // ---- Publish. List is always derived from this cycle's live enumeration,
        // so timestamps can never outrun the underlying truth (kills fake-update A).
        var nextWindows: [CapturedWindow] = []
        var instanceOrdinals: [String: Int] = [:]
        for window in discovered {
            let identity = [
                String(window.processIdentifier),
                window.title,
                String(Int(window.frame.width.rounded())),
                String(Int(window.frame.height.rounded()))
            ].joined(separator: "\u{0}")
            let ordinal = instanceOrdinals[identity, default: 0]
            instanceOrdinals[identity] = ordinal + 1

            let nsPreview: NSImage? = {
                guard let p = previewMap[window.windowID] ?? nil else { return nil }
                return NSImage(cgImage: p.cgImage, size: p.size)
            }()

            nextWindows.append(
                CapturedWindow(
                    id: window.windowID,
                    processIdentifier: window.processIdentifier,
                    ownerName: window.ownerName.isEmpty ? "Unknown" : window.ownerName,
                    bundleIdentifier: window.bundleIdentifier,
                    title: window.title,
                    frame: window.frame,
                    instanceOrdinal: ordinal,
                    preview: nsPreview
                )
            )
        }

        windows = nextWindows
        normalizeSelection()
        updateActiveWindowID()
        captureState = .ready
        lastRefresh = Date()
        hasCompletedRefresh = true
    }

    @discardableResult
    func select(_ windowID: CGWindowID, activate: Bool = true) async -> Bool {
        guard let window = windows.first(where: { $0.id == windowID }) else { return false }
        selectedWindowID = windowID

        guard activate else { return true }

        // P0-1: Run AX activation off MainActor with timeout to avoid blocking UI
        // Capture Sendable primitives only to satisfy @Sendable closure.
        let pid = window.processIdentifier
        let wid = window.id
        let title = window.title
        let frame = window.frame
        let result: WindowActivationResult
        do {
            result = try await withTimeout(.milliseconds(1_500)) {
                await Task.detached(priority: .userInitiated) {
                    AccessibilityService.activate(
                        processIdentifier: pid,
                        windowID: wid,
                        windowTitle: title,
                        windowFrame: frame
                    )
                }.value
            }
        } catch is TimeoutError {
            result = .activationFailed
        } catch {
            result = .activationFailed
        }

        switch result {
        case .success:
            activationError = nil
            scheduleActiveWindowRefresh()
            return true
        case .permissionRequired:
            activationError = .permissionRequired
        case .processUnavailable:
            activationError = .processUnavailable
        case .targetWindowNotFound:
            activationError = .targetWindowNotFound
        case .activationFailed:
            activationError = .activationFailed
        }

        return false
    }

    func selectRelative(_ offset: Int) async {
        guard !windows.isEmpty else { return }
        let currentIndex = windows.firstIndex { $0.id == selectedWindowID } ?? 0
        let nextIndex = (currentIndex + offset + windows.count) % windows.count
        await select(windows[nextIndex].id)
    }

    func window(withID id: CGWindowID) -> CapturedWindow? {
        windows.first { $0.id == id }
    }

    nonisolated private static func capturePreview(of window: DiscoveredWindow, scWindow: SCWindow) async throws -> SendablePreview {
        let configuration = SCStreamConfiguration()
        let aspectRatio = max(window.frame.width / max(window.frame.height, 1), 0.1)
        configuration.width = 720
        configuration.height = max(240, Int(720 / aspectRatio))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: scWindow)
        let cgImage = try await SCScreenshotManager.captureImage(
            contentFilter: filter,
            configuration: configuration
        )

        return SendablePreview(
            cgImage: cgImage,
            size: NSSize(width: configuration.width, height: configuration.height)
        )
    }

    private func normalizeSelection() {
        if let selectedWindowID, windows.contains(where: { $0.id == selectedWindowID }) {
            // Keep the current selection when it is still present.
        } else {
            selectedWindowID = windows.first?.id
        }

        if let activeWindowID, !windows.contains(where: { $0.id == activeWindowID }) {
            self.activeWindowID = nil
        }
    }

    private func scheduleActiveWindowRefresh() {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            self?.updateActiveWindowID(force: true)
        }
    }

    private func updateActiveWindowID(force: Bool = false) {
        // Throttle to 200ms to avoid synchronous CGWindowListCopyWindowInfo on every frame.
        if !force, Date.now.timeIntervalSince(lastActiveUpdate) < 0.2 {
            return
        }
        lastActiveUpdate = Date.now

        guard !windows.isEmpty,
              let frontmostProcessID = NSWorkspace.shared.frontmostApplication?.processIdentifier
        else {
            activeWindowID = nil
            return
        }

        let candidateIDs = Set(windows.map(\.id))
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let windowInfo = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            activeWindowID = nil
            return
        }

        for info in windowInfo {
            guard let ownerPID = (info[kCGWindowOwnerPID as String] as? NSNumber)?.int32Value,
                  ownerPID == frontmostProcessID,
                  let number = (info[kCGWindowNumber as String] as? NSNumber)?.uint32Value else {
                continue
            }

            let windowID = CGWindowID(number)
            if candidateIDs.contains(windowID) {
                activeWindowID = windowID
                return
            }
        }

        activeWindowID = nil
    }
}
