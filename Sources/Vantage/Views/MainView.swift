import AppKit
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var captureService: WindowCaptureService
    @EnvironmentObject private var overlayController: OverlayWindowController

    @State private var searchText = ""
    @State private var showInspector = false
    @State private var filterDebounceTask: Task<Void, Never>?
    @State private var isAppActive = NSApp.isActive

    private var filteredWindows: [CapturedWindow] {
        captureService.windows.filter { WindowFilter.matchesSearch($0, query: searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                SidebarView(searchText: $searchText)
                    .frame(width: 224)

                Rectangle()
                    .fill(VantageTheme.line)
                    .frame(width: 1)

                workspace

                if showInspector {
                    Rectangle()
                        .fill(VantageTheme.line)
                        .frame(width: 1)
                    InspectorView()
                        .frame(width: 270)
                }
            }

            statusBar
        }
        .background(VantageTheme.background)
        .foregroundStyle(VantageTheme.primaryText)
        .tint(settings.accentChoice.color)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button {
                    showInspector.toggle()
                } label: {
                    Label(
                        localized(showInspector ? "workspace.hideInspector" : "workspace.showInspector"),
                        systemImage: "sidebar.right"
                    )
                }
                .help(localized(showInspector ? "workspace.hideInspector" : "workspace.showInspector"))

                Button {
                    settings.showOverlays.toggle()
                } label: {
                    Label(
                        localized(settings.showOverlays ? "menu.hideOverlays" : "menu.showOverlays"),
                        systemImage: "rectangle.on.rectangle"
                    )
                }
            }
        }
        .onChange(of: settings.exactBundleIdentifiers) {
            debounceFilterRefresh()
        }
        .onChange(of: settings.exactOwnerNames) {
            debounceFilterRefresh()
        }
        .onChange(of: settings.isPaused) {
            if !settings.isPaused {
                Task { await captureService.refresh() }
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in isAppActive = true }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didResignActiveNotification)) { _ in isAppActive = false }
        .onKeyPress { press in
            guard press.modifiers.contains(.command),
                  let number = Int(press.characters),
                  (1...9).contains(number),
                  let window = captureService.window(atHotKeySlot: number)
            else {
                return .ignored
            }

            Task { await captureService.select(window.id) }
            return .handled
        }
        .alert(
            localized("workspace.activationFailedTitle"),
            isPresented: Binding(
                get: { captureService.activationError != nil },
                set: { isPresented in
                    if !isPresented {
                        captureService.activationError = nil
                    }
                }
            )
        ) {
            Button(localized("workspace.openAccessibilitySettings")) {
                AccessibilityService.openSettings()
            }
            Button(localized("common.close"), role: .cancel) {
                captureService.activationError = nil
            }
        } message: {
            Text(localized(captureService.activationError?.messageKey ?? "workspace.activationFailedMessage"))
        }
    }

    private var workspace: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 2) {
                        Text(localized("workspace.title"))
                        .font(.system(size: 14, weight: .semibold))
                    Text(
                        localized(
                            "workspace.summary",
                            values: [
                                "count": "\(filteredWindows.count)",
                                "rate": settings.previewRefreshRate.title(for: settings.language)
                            ]
                        )
                    )
                        .font(.system(size: 10))
                        .foregroundStyle(VantageTheme.tertiaryText)
                }
                Spacer()
                CaptureStatusLabel(
                    label: settings.isPaused
                        ? localized("menu.pauseCapture")
                        : captureService.captureState.label(for: settings.language),
                    color: settings.isPaused ? VantageTheme.warning : VantageTheme.success
                )
                Button(localized(settings.isPaused ? "menu.resumeCapture" : "menu.pauseCapture")) {
                    settings.isPaused.toggle()
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                Button {
                    Task { await captureService.selectRelative(1) }
                } label: {
                    Image(systemName: "arrow.right")
                }
                .buttonStyle(.bordered)
                .controlSize(.small)
                .help(localized("workspace.nextClient"))
            }
            .padding(.horizontal, 16)
            .frame(height: 58)
            .background(VantageTheme.panel)
            .overlay(alignment: .bottom) {
                Rectangle().fill(VantageTheme.line).frame(height: 1)
            }

            if captureService.captureState == .permissionRequired {
                permissionView
            } else if case .failed(let message) = captureService.captureState, filteredWindows.isEmpty {
                errorView(message: message)
            } else if captureService.captureState == .refreshing,
                      filteredWindows.isEmpty,
                      !captureService.hasCompletedRefresh {
                loadingView
            } else if filteredWindows.isEmpty {
                emptyView
            } else {
                GeometryReader { proxy in
                    // Tallest aspect (smallest ratio) drives the fit estimate:
                    // every card in every row is then guaranteed to fit.
                    let minAspect = filteredWindows.map(\.displayAspectRatio).min() ?? CGFloat(16) / 9
                    let layout = PreviewGridSolver.solve(
                        width: proxy.size.width,
                        height: proxy.size.height,
                        count: filteredWindows.count,
                        minAspect: minAspect
                    )

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(0..<layout.rowCount, id: \.self) { row in
                                HStack(alignment: .top, spacing: layout.gap) {
                                    ForEach(0..<layout.columnCount, id: \.self) { column in
                                        let index = row * layout.columnCount + column

                                        if filteredWindows.indices.contains(index) {
                                            // Width AND height pinned: lazy
                                            // stacks measure with unbounded
                                            // height, and an unpinned card
                                            // falls back to the preview
                                            // image's natural pixel height,
                                            // inflating rows by hundreds of
                                            // points (giant gaps, pushed-off
                                            // second row).
                                            PreviewCardView(
                                                window: filteredWindows[index],
                                                compact: false,
                                                showsOwnerSubtitle: showsOwnerSubtitle
                                            )
                                            .frame(
                                                width: layout.cardWidth,
                                                height: PreviewGridSolver.cardHeight(
                                                    cardWidth: layout.cardWidth,
                                                    aspect: filteredWindows[index].displayAspectRatio
                                                )
                                            )
                                            .clipped()
                                        } else {
                                            Color.clear
                                                .frame(width: layout.cardWidth, height: 1)
                                        }
                                    }
                                }
                                .frame(width: layout.contentWidth, alignment: .leading)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(14)
                    }
                    .background(VantageTheme.background)
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// Every card repeating one identical owner name is noise, not metadata:
    /// hide the subtitle when the whole filtered set belongs to one owner.
    private var showsOwnerSubtitle: Bool {
        Set(filteredWindows.map(\.ownerName)).count > 1
    }

    private var permissionView: some View {
        VStack(alignment: .leading, spacing: 12) {
            Image(systemName: "rectangle.inset.filled.and.person.filled")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(settings.accentChoice.color)
            Text(localized("permission.screenRecordingTitle"))
                .font(.system(size: 16, weight: .semibold))
            Text(localized("permission.screenRecordingMessage"))
                .font(.system(size: 12))
                .foregroundStyle(VantageTheme.secondaryText)
            Button(localized("permission.openScreenRecording")) {
                captureService.openScreenCaptureSettings()
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(VantageTheme.background)
    }

    private var emptyView: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 24, weight: .light))
                .foregroundStyle(settings.accentChoice.color)
            Text(localized("empty.title"))
                .font(.system(size: 16, weight: .semibold))
            Text(localized("empty.message"))
                .font(.system(size: 12))
                .foregroundStyle(VantageTheme.secondaryText)
            Button(localized("common.rescan")) {
                Task { await captureService.refresh() }
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(VantageTheme.background)
    }

    private var loadingView: some View {
        VStack(alignment: .leading, spacing: 10) {
            ProgressView()
                .controlSize(.small)
            Text(localized("loading.title"))
                .font(.system(size: 16, weight: .semibold))
            Text(localized("loading.message"))
                .font(.system(size: 12))
                .foregroundStyle(VantageTheme.secondaryText)
        }
        .frame(maxWidth: 360, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(VantageTheme.background)
    }

    private func errorView(message: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 22, weight: .light))
                .foregroundStyle(VantageTheme.danger)
            Text(localized("error.title"))
                .font(.system(size: 16, weight: .semibold))
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(VantageTheme.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
            Button(localized("common.retry")) {
                Task { await captureService.refresh() }
            }
            .buttonStyle(.bordered)
        }
        .frame(maxWidth: 380, alignment: .leading)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .padding(24)
        .background(VantageTheme.background)
    }

    private var statusBar: some View {
        HStack(spacing: 12) {
            Label(
                captureService.captureState.label(for: settings.language),
                systemImage: captureService.captureState.symbolName
            )
                .lineLimit(1)
                .foregroundStyle(statusColor)
            if let lastRefresh = captureService.lastRefresh {
                Text(
                    localized(
                        "status.updatedAt",
                        values: ["time": lastRefresh.formatted(date: .omitted, time: .standard)]
                    )
                )
                    .lineLimit(1)
            }
            Spacer()
            // P2-2: Overlay hidden while main window is active is intentional; show hint to avoid perceived freeze.
            if settings.showOverlays && isAppActive {
                Label(localized("status.overlayHidden"), systemImage: "eye.slash")
                    .foregroundStyle(VantageTheme.warning)
                    .lineLimit(1)
                    .help(localized("status.overlayHidden"))
            }
            // P0 truth-telling: fresh windows discovered but pixels not bound yet.
            if captureService.listStale {
                Label(localized("status.listStale"), systemImage: "arrow.triangle.2.circlepath")
                    .foregroundStyle(VantageTheme.warning)
                    .lineLimit(1)
            }
            if let activeWindowID = captureService.activeWindowID,
               let activeWindow = captureService.window(withID: activeWindowID) {
                Label(
                    localized("status.active", values: ["window": activeWindow.displayTitle]),
                    systemImage: "circle.fill"
                )
                    .foregroundStyle(VantageTheme.success)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            Text(
                localized(
                    AccessibilityService.isTrusted
                        ? "status.accessibilityEnabled"
                        : "status.accessibilityDisabled"
                )
            )
                .lineLimit(1)
        }
        .font(.system(size: 9, weight: .medium))
        .foregroundStyle(VantageTheme.tertiaryText)
        .padding(.horizontal, 12)
        .frame(height: 31)
        .background(VantageTheme.panel)
        .overlay(alignment: .top) {
            Rectangle().fill(VantageTheme.line).frame(height: 1)
        }
    }

    private var statusColor: Color {
        switch captureService.captureState {
        case .ready:
            return VantageTheme.success
        case .failed:
            return VantageTheme.danger
        case .permissionRequired:
            return VantageTheme.warning
        default:
            return VantageTheme.secondaryText
        }
    }

    private func debounceFilterRefresh() {
        // P1-3: 250ms debounce to avoid per-character full SCK scans; skip while paused.
        guard !settings.isPaused else { return }
        filterDebounceTask?.cancel()
        filterDebounceTask = Task {
            do {
                try await Task.sleep(for: .milliseconds(250))
            } catch { return }
            guard !Task.isCancelled else { return }
            await captureService.refresh()
        }
    }

    private func localized(_ key: String, values: [String: String] = [:]) -> String {
        settings.localized(key, values: values)
    }
}
