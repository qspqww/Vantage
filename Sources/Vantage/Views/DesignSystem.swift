import SwiftUI

enum VantageTheme {
    static let background = Color(red: 0.059, green: 0.063, blue: 0.071)
    static let panel = Color(red: 0.082, green: 0.090, blue: 0.102)
    static let panelElevated = Color(red: 0.118, green: 0.129, blue: 0.145)
    static let selection = Color.white.opacity(0.07)
    static let line = Color.white.opacity(0.12)
    static let strongLine = Color.white.opacity(0.20)
    static let primaryText = Color(red: 0.941, green: 0.949, blue: 0.961)
    static let secondaryText = Color(red: 0.671, green: 0.694, blue: 0.729)
    static let tertiaryText = Color(red: 0.447, green: 0.475, blue: 0.518)
    static let success = Color(red: 0.286, green: 0.749, blue: 0.431)
    static let warning = Color(red: 0.918, green: 0.624, blue: 0.196)
    static let danger = Color(red: 0.918, green: 0.322, blue: 0.302)
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(size: 10, weight: .medium))
            .foregroundStyle(VantageTheme.secondaryText)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct CaptureStatusLabel: View {
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(color)
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11, weight: .medium))
        }
        .foregroundStyle(VantageTheme.secondaryText)
    }
}
