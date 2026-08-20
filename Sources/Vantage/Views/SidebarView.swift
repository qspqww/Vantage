import SwiftUI

struct SidebarView: View {
    @EnvironmentObject private var captureService: WindowCaptureService
    @EnvironmentObject private var settings: SettingsStore
    @Binding var searchText: String

    private var filteredWindows: [CapturedWindow] {
        captureService.windows.filter { WindowFilter.matchesSearch($0, query: searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            searchField

            HStack(alignment: .firstTextBaseline) {
                Text(settings.localized("clients.title"))
                    .font(.system(size: 11, weight: .semibold))
                Spacer()
                Text("\(filteredWindows.count)")
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundStyle(VantageTheme.tertiaryText)
            }
            .padding(.horizontal, 14)
            .padding(.top, 18)
            .padding(.bottom, 7)

            ScrollView {
                LazyVStack(spacing: 1) {
                    ForEach(Array(filteredWindows.enumerated()), id: \.element.id) { index, window in
                        clientRow(window: window, index: index)
                    }
                }
                .padding(.horizontal, 6)
                .padding(.bottom, 10)
            }

            Divider()
                .overlay(VantageTheme.line)

            Button {
                Task { await captureService.refresh() }
            } label: {
                Label(settings.localized("clients.refresh"), systemImage: "arrow.clockwise")
                    .font(.system(size: 11, weight: .medium))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .buttonStyle(.plain)
            .foregroundStyle(VantageTheme.secondaryText)
            .padding(.horizontal, 14)
            .frame(height: 42)
        }
        .background(VantageTheme.panel)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(settings.localized("app.name"))
                .font(.system(size: 16, weight: .semibold))
            Text(settings.localized("app.subtitle"))
                .font(.system(size: 10))
                .foregroundStyle(VantageTheme.tertiaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.top, 16)
        .padding(.bottom, 13)
    }

    private var searchField: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 10, weight: .medium))
                .foregroundStyle(VantageTheme.tertiaryText)
            TextField(settings.localized("clients.search"), text: $searchText)
                .textFieldStyle(.plain)
                .font(.system(size: 11))
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(VantageTheme.tertiaryText)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 30)
        .background(VantageTheme.background)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(VantageTheme.line, lineWidth: 1)
        }
        .padding(.horizontal, 12)
    }

    private func clientRow(window: CapturedWindow, index: Int) -> some View {
        let isSelected = captureService.selectedWindowID == window.id
        let isActive = captureService.activeWindowID == window.id

        return Button {
            captureService.select(window.id)
        } label: {
            HStack(spacing: 8) {
                Rectangle()
                    .fill(isActive ? settings.accentChoice.color : (isSelected ? settings.accentChoice.color.opacity(0.6) : Color.clear))
                    .frame(width: isActive ? 3 : 2)

                VStack(alignment: .leading, spacing: 3) {
                    Text(window.displayTitle)
                        .font(.system(size: 11, weight: isActive || isSelected ? .semibold : .regular))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(window.subtitle(language: settings.language))
                        .font(.system(size: 9))
                        .foregroundStyle(VantageTheme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if isActive {
                    Image(systemName: "circle.fill")
                        .font(.system(size: 6))
                        .foregroundStyle(VantageTheme.success)
                        .help(settings.localized("window.active"))
                        .accessibilityLabel(settings.localized("window.active"))
                }

                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(isActive || isSelected ? settings.accentChoice.color : VantageTheme.tertiaryText)
                }
            }
            .padding(.trailing, 8)
            .frame(height: 45)
            .background(
                isActive
                    ? settings.accentChoice.color.opacity(0.16)
                    : (isSelected ? VantageTheme.selection : Color.clear)
            )
            .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .stroke(
                        isActive ? settings.accentChoice.color : Color.clear,
                        lineWidth: isActive ? 1 : 0
                    )
            }
        }
        .buttonStyle(.plain)
    }
}
