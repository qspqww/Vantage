import SwiftUI

struct InspectorView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var captureService: WindowCaptureService
    @EnvironmentObject private var overlayController: OverlayWindowController

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                inspectorHeader

                inspectorGroup(settings.localized("inspector.floatingPreview")) {
                    Toggle(settings.localized("menu.showOverlays"), isOn: $settings.showOverlays)
                    Toggle(settings.localized("inspector.activateOnClick"), isOn: $settings.activateOnOverlayClick)
                    Toggle(settings.localized("inspector.alwaysOnTop"), isOn: $settings.alwaysOnTop)
                    Toggle(settings.localized("settings.showMetadata"), isOn: $settings.showMetadata)
                }

                inspectorGroup(settings.localized("inspector.display")) {
                    sliderRow(
                        title: settings.localized("inspector.opacity"),
                        value: $settings.overlayOpacity,
                        range: 0.35...1,
                        valueText: "\(Int(settings.overlayOpacity * 100))%"
                    )
                    sliderRow(
                        title: settings.localized("inspector.width"),
                        value: $settings.previewWidth,
                        range: 180...460,
                        valueText: "\(Int(settings.previewWidth)) px"
                    )
                    HStack {
                        Text(settings.localized("settings.refreshRate"))
                        Spacer()
                        Picker(settings.localized("settings.refreshRate"), selection: refreshRateBinding) {
                            ForEach(PreviewRefreshRate.allCases) { rate in
                                Text(rate.title(for: settings.language)).tag(rate)
                            }
                        }
                        .labelsHidden()
                        .pickerStyle(.menu)
                    }
                }

                inspectorGroup(settings.localized("inspector.hotkeys")) {
                    Text(settings.localized("inspector.hotkeysHelp"))
                        .font(.system(size: 9))
                        .foregroundStyle(VantageTheme.tertiaryText)

                    if captureService.windows.isEmpty {
                        Text(settings.localized("inspector.hotkeysEmpty"))
                            .foregroundStyle(VantageTheme.tertiaryText)
                    } else {
                        ForEach(captureService.windows) { window in
                            HotKeyRow(
                                windowID: window.id,
                                displayTitle: window.displayTitle,
                                subtitleText: window.subtitle(language: settings.language),
                                positionKey: window.overlayPositionKey,
                                assignment: settings.hotKeyAssignments[window.overlayPositionKey]
                            )
                            .equatable()
                        }
                    }
                }

                inspectorGroup(settings.localized("inspector.arrangement")) {
                    Picker(settings.localized("inspector.arrangement"), selection: $settings.previewLayout) {
                        ForEach(PreviewLayout.allCases) { layout in
                            Text(layout.title(for: settings.language)).tag(layout)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Button {
                        overlayController.arrangePanels()
                    } label: {
                        Label(settings.localized("inspector.rearrange"), systemImage: "rectangle.3.group")
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(VantageTheme.secondaryText)
                }
            }
        }
        .background(VantageTheme.panel)
        .toggleStyle(.switch)
    }

    private var inspectorHeader: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(settings.localized("inspector.title"))
                .font(.system(size: 14, weight: .semibold))
            Text(settings.localized("inspector.subtitle"))
                .font(.system(size: 10))
                .foregroundStyle(VantageTheme.tertiaryText)
        }
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 14)
    }

    private func inspectorGroup<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(VantageTheme.secondaryText)
            content()
                .font(.system(size: 11))
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(VantageTheme.line)
                .frame(height: 1)
        }
    }

    private func sliderRow(
        title: String,
        value: Binding<Double>,
        range: ClosedRange<Double>,
        valueText: String
    ) -> some View {
        VStack(spacing: 7) {
            HStack {
                Text(title)
                Spacer()
                Text(valueText)
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .foregroundStyle(VantageTheme.tertiaryText)
            }
            Slider(value: value, in: range)
                .tint(settings.accentChoice.color)
        }
    }

    /// Value-only row. Equatable gating is what keeps the picker popup
    /// stable: the capture stream republishes `windows` every refresh cycle
    /// (new thumbnail images), and without the gate each cycle would rebuild
    /// the Picker under an open popup menu.
    private struct HotKeyRow: View, Equatable {
        let windowID: CGWindowID
        let displayTitle: String
        let subtitleText: String
        let positionKey: String
        let assignment: Int?

        @EnvironmentObject private var settings: SettingsStore

        nonisolated static func == (lhs: HotKeyRow, rhs: HotKeyRow) -> Bool {
            lhs.windowID == rhs.windowID
                && lhs.displayTitle == rhs.displayTitle
                && lhs.subtitleText == rhs.subtitleText
                && lhs.positionKey == rhs.positionKey
                && lhs.assignment == rhs.assignment
        }

        /// Shows the persisted pin (nil = auto). The ⌘N badge in the sidebar
        /// and cards shows the *resolved* slot instead; the two differ exactly
        /// when a window is auto-filling whatever slot happens to be free.
        var body: some View {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(displayTitle)
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(subtitleText)
                        .font(.system(size: 9))
                        .foregroundStyle(VantageTheme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Picker(
                    settings.localized("menu.assignHotkey"),
                    selection: Binding(
                        get: { assignment },
                        set: { settings.setHotKeySlot($0, for: positionKey) }
                    )
                ) {
                    Text(settings.localized("hotkey.auto")).tag(Int?.none)
                    ForEach(1...HotKeySlotResolver.slotCount, id: \.self) { slot in
                        Text("⌘\(slot)").tag(Int?.some(slot))
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
            }
        }
    }

    private var refreshRateBinding: Binding<PreviewRefreshRate> {
        Binding(
            get: { settings.previewRefreshRate },
            set: { captureService.setRefreshRate($0) }
        )
    }
}
