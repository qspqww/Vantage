import AppKit
import CoreGraphics
@preconcurrency import ScreenCaptureKit

private struct SendablePreview: @unchecked Sendable {
    let cgImage: CGImage
    let size: NSSize
}

@MainActor
final class WindowCaptureService: ObservableObject {
    @Published private(set) var windows: [CapturedWindow] = []
    @Published var selectedWindowID: CGWindowID?
    @Published private(set) var activeWindowID: CGWindowID?
    @Published private(set) var hasCompletedRefresh = false
    @Published private(set) var captureState: CaptureState = .idle
    @Published private(set) var lastRefresh: Date?
    @Published var activationError: WindowActivationError?

    private let settings: SettingsStore
    private var updateTask: Task<Void, Never>?
    private var refreshSequence = 0
    private var lastActiveUpdate = Date.distantPast

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
                if remaining > .zero {
                    do {
                        try await Task.sleep(for: remaining)
                    } catch {
                        // Task cancelled — exit promptly instead of swallowing
                        break
                    }
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

        do {
            let content = try await withTimeout(.milliseconds(2_000)) {
                try await SCShareableContent.excludingDesktopWindows(
                    true,
                    onScreenWindowsOnly: true
                )
            }

            guard sequence == refreshSequence else {
                // Stale result discarded — recover visible state if first refresh
                if !hasCompletedRefresh {
                    // Do not leave perpetual refreshing; will retry next cycle
                }
                return
            }

            let candidates = content.windows
                .filter { window in
                    guard WindowFilter.isNormalWindow(
                        isOnScreen: window.isOnScreen,
                        windowLayer: window.windowLayer,
                        title: window.title,
                        frame: window.frame
                    ) else {
                        return false
                    }

                    let ownerName = window.owningApplication?.applicationName ?? ""
                    guard window.owningApplication?.processID ?? 0 > 0 else { return false }
                    return WindowFilter.isEligible(
                        ownerName: ownerName,
                        bundleIdentifier: window.owningApplication?.bundleIdentifier,
                        exactBundleIdentifiers: settings.exactBundleIdentifierList,
                        exactOwnerNames: settings.exactOwnerNameList
                    )
                }
                .sorted { lhs, rhs in
                    let lhsOwner = lhs.owningApplication?.applicationName ?? ""
                    let rhsOwner = rhs.owningApplication?.applicationName ?? ""
                    if lhsOwner == rhsOwner {
                        if (lhs.title ?? "") == (rhs.title ?? "") {
                            if lhs.frame.origin.y == rhs.frame.origin.y {
                                return lhs.frame.origin.x < rhs.frame.origin.x
                            }
                            return lhs.frame.origin.y < rhs.frame.origin.y
                        }
                        return (lhs.title ?? "") < (rhs.title ?? "")
                    }
                    return lhsOwner < rhsOwner
                }
                .prefix(12)

            // Concurrent capture with per-window timeout (800ms) — P0-3
            // Use CGImage via SendablePreview to satisfy Swift 6 Sendable checks; NSImage is created on MainActor after.
            var previewMap: [CGWindowID: SendablePreview?] = [:]
            if !candidates.isEmpty {
                try await withThrowingTaskGroup(of: (CGWindowID, SendablePreview?).self) { group in
                    for window in candidates {
                        group.addTask {
                            let preview: SendablePreview? = try? await withTimeout(.milliseconds(800)) {
                                try await WindowCaptureService.capturePreview(of: window)
                            }
                            return (window.windowID, preview)
                        }
                    }
                    for try await (wid, preview) in group {
                        if Task.isCancelled { group.cancelAll(); break }
                        previewMap[wid] = preview
                    }
                }
            }

            guard sequence == refreshSequence else { return }
            if Task.isCancelled { return }

            var nextWindows: [CapturedWindow] = []
            var instanceOrdinals: [String: Int] = [:]
            for window in candidates {
                let owner = window.owningApplication
                let processIdentifier = owner?.processID ?? 0
                let title = window.title ?? ""
                let identity = [
                    String(processIdentifier),
                    title,
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
                        processIdentifier: processIdentifier,
                        ownerName: owner?.applicationName ?? "Unknown",
                        bundleIdentifier: owner?.bundleIdentifier,
                        title: title,
                        frame: window.frame,
                        instanceOrdinal: ordinal,
                        preview: nsPreview
                    )
                )
            }

            guard sequence == refreshSequence else { return }

            windows = nextWindows
            normalizeSelection()
            updateActiveWindowID()
            captureState = .ready
            lastRefresh = Date()
            hasCompletedRefresh = true
        } catch is TimeoutError {
            // Timeout is recoverable — keep last windows, surface transient failure without clearing hasCompletedRefresh
            if hasCompletedRefresh {
                captureState = .ready
            } else {
                captureState = .failed("Screen capture timed out")
            }
        } catch {
            if Task.isCancelled || error is CancellationError {
                return
            }
            // If this was first refresh and we failed, leave refreshing -> failed to avoid perpetual spinner
            captureState = .failed(error.localizedDescription)
        }
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

    nonisolated private static func capturePreview(of window: SCWindow) async throws -> SendablePreview {
        let configuration = SCStreamConfiguration()
        let aspectRatio = max(window.frame.width / max(window.frame.height, 1), 0.1)
        configuration.width = 720
        configuration.height = max(240, Int(720 / aspectRatio))
        configuration.showsCursor = false
        configuration.scalesToFit = true
        configuration.ignoreShadowsSingleWindow = true

        let filter = SCContentFilter(desktopIndependentWindow: window)
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
        // P2-1: Throttle to 200ms to avoid synchronous CGWindowListCopyWindowInfo on every frame.
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
