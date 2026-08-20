import SwiftUI

struct PreferencesView: View {
    @EnvironmentObject private var settings: SettingsStore
    @EnvironmentObject private var captureService: WindowCaptureService

    var body: some View {
        Form {
            Section {
                TextField(settings.localized("settings.exactOwnerName"), text: $settings.exactOwnerNames)
                TextField(settings.localized("settings.exactBundleID"), text: $settings.exactBundleIdentifiers)
                Text(settings.localized("settings.discoveryHelp"))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } header: {
                Text(settings.localized("settings.windowDiscovery"))
            }

            Section {
                Picker(settings.localized("settings.refreshRate"), selection: refreshRateBinding) {
                    ForEach(PreviewRefreshRate.allCases) { rate in
                        Text(rate.title(for: settings.language)).tag(rate)
                    }
                }
                Toggle(settings.localized("settings.showMetadata"), isOn: $settings.showMetadata)
            } header: {
                Text(settings.localized("settings.preview"))
            }

            Section {
                Picker(settings.localized("settings.language"), selection: $settings.language) {
                    ForEach(AppLanguage.allCases) { language in
                        Text(language.displayName(in: settings.language)).tag(language)
                    }
                }
            } header: {
                Text(settings.localized("settings.language"))
            }

            Section {
                permissionRow(settings.localized("settings.screenRecording"), isGranted: captureService.hasScreenCapturePermission)
                permissionRow(settings.localized("settings.accessibility"), isGranted: AccessibilityService.isTrusted)

                HStack(spacing: 8) {
                    Button(settings.localized("permission.openScreenRecording")) {
                        captureService.openScreenCaptureSettings()
                    }
                    Button(settings.localized("settings.openAccessibility")) {
                        AccessibilityService.openSettings()
                    }
                }
            } header: {
                Text(settings.localized("settings.permissions"))
            }
        }
        .formStyle(.grouped)
        .padding()
        .frame(minWidth: 480, minHeight: 330)
    }

    private func permissionRow(_ title: String, isGranted: Bool) -> some View {
        LabeledContent(title) {
            HStack(spacing: 6) {
                Circle()
                    .fill(isGranted ? VantageTheme.success : VantageTheme.warning)
                    .frame(width: 7, height: 7)
                Text(settings.localized(isGranted ? "settings.granted" : "settings.notGranted"))
                    .foregroundStyle(.secondary)
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
