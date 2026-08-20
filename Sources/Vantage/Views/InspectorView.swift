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

    private var refreshRateBinding: Binding<PreviewRefreshRate> {
        Binding(
            get: { settings.previewRefreshRate },
            set: { captureService.setRefreshRate($0) }
        )
    }
}
