import SwiftUI

struct MainView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var captureService: WindowCaptureService
    @EnvironmentObject private var overlayController: OverlayWindowController

    @State private var searchText = ""
    @State private var showInspector = false

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
            Task { await captureService.refresh() }
        }
        .onChange(of: settings.exactOwnerNames) {
            Task { await captureService.refresh() }
        }
        .onChange(of: settings.isPaused) {
            if !settings.isPaused {
                Task { await captureService.refresh() }
            }
        }
        .onKeyPress { press in
            guard press.modifiers.contains(.command),
                  let number = Int(press.characters),
                  (1...9).contains(number),
                  filteredWindows.indices.contains(number - 1)
            else {
                return .ignored
            }

            captureService.select(filteredWindows[number - 1].id)
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
                    captureService.selectRelative(1)
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
                    let layout = previewLayout(for: proxy.size.width)

                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 14) {
                            ForEach(0..<layout.rowCount, id: \.self) { row in
                                HStack(alignment: .top, spacing: layout.gap) {
                                    ForEach(0..<layout.columnCount, id: \.self) { column in
                                        let index = row * layout.columnCount + column

                                        if filteredWindows.indices.contains(index) {
                                            PreviewCardView(
                                                window: filteredWindows[index],
                                                index: index,
                                                compact: false
                                            )
                                            .frame(width: layout.cardWidth)
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

    private func previewLayout(for width: CGFloat) -> PreviewGridLayout {
        let availableWidth = max(1, width - 28)
        let preferredCardWidth = 250.0
        let gap = 12.0
        let fittingColumnCount = max(
            1,
            Int(floor((availableWidth + gap) / (preferredCardWidth + gap)))
        )
        let columnCount = min(max(1, filteredWindows.count), fittingColumnCount)
        let gapsWidth = Double(max(0, columnCount - 1)) * gap
        let cardWidth = min(
            preferredCardWidth,
            floor((availableWidth - gapsWidth) / Double(columnCount))
        )
        let contentWidth = Double(columnCount) * cardWidth + gapsWidth
        let rowCount = Int(ceil(Double(filteredWindows.count) / Double(columnCount)))

        return PreviewGridLayout(
            columnCount: columnCount,
            rowCount: rowCount,
            cardWidth: cardWidth,
            contentWidth: contentWidth,
            gap: gap
        )
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

    private func localized(_ key: String, values: [String: String] = [:]) -> String {
        settings.localized(key, values: values)
    }
}

private struct PreviewGridLayout {
    let columnCount: Int
    let rowCount: Int
    let cardWidth: CGFloat
    let contentWidth: CGFloat
    let gap: CGFloat
}
