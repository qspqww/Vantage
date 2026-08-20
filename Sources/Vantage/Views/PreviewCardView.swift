import AppKit
import SwiftUI

struct PreviewCardView: View {
    let window: CapturedWindow
    let index: Int
    let compact: Bool

    @EnvironmentObject private var captureService: WindowCaptureService
    @EnvironmentObject private var settings: SettingsStore
    @State private var didDragOverlay = false

    private var isSelected: Bool {
        captureService.selectedWindowID == window.id
    }

    private var isActive: Bool {
        captureService.activeWindowID == window.id
    }

    private var showsSelectedState: Bool {
        !compact && isSelected
    }

    private var showsActiveHighlight: Bool {
        isActive
    }

    private var windowAspectRatio: CGFloat {
        let width = max(window.frame.width, 1)
        let height = max(window.frame.height, 1)
        return min(max(width / height, 1), 3)
    }

    @ViewBuilder
    var body: some View {
        if compact {
            cardButton
        } else {
            cardButton
                .contextMenu {
                    Button(settings.localized("menu.activateWindow")) {
                        captureService.select(window.id)
                    }
                    Button(settings.localized("menu.showOverlays")) {
                        settings.showOverlays = true
                    }
                }
        }
    }

    private var cardButton: some View {
        Button {
            guard !compact || !didDragOverlay else { return }
            selectWindow()
        } label: {
            if compact {
                compactCard
            } else {
                mainCard
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .simultaneousGesture(overlayDragGuard)
        .accessibilityLabel(
            settings.localized("window.activateLabel", values: ["window": window.displayTitle])
        )
    }

    private var mainCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            previewImage
                .aspectRatio(windowAspectRatio, contentMode: .fit)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(window.displayTitle)
                        .font(.system(size: 11, weight: showsActiveHighlight || showsSelectedState ? .semibold : .medium))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(window.subtitle(language: settings.language))
                        .font(.system(size: 9))
                        .foregroundStyle(VantageTheme.tertiaryText)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 9, weight: .medium, design: .monospaced))
                        .foregroundStyle(
                            showsActiveHighlight || showsSelectedState
                                ? settings.accentChoice.color
                                : VantageTheme.tertiaryText
                        )
                }

                if isActive {
                    activeMark
                }
            }
            .padding(.horizontal, 10)
            .frame(height: 45)
            .background(VantageTheme.panelElevated)
        }
        .background(VantageTheme.panelElevated)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 7, style: .continuous)
                .stroke(
                    showsActiveHighlight || showsSelectedState
                        ? settings.accentChoice.color
                        : VantageTheme.line,
                    lineWidth: showsActiveHighlight ? 3 : (showsSelectedState ? 2 : 1)
                )
        }
    }

    private var compactCard: some View {
        ZStack(alignment: .bottomLeading) {
            previewImage
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            HStack(alignment: .bottom, spacing: 8) {
                Circle()
                    .fill(settings.isPaused ? VantageTheme.warning : VantageTheme.success)
                    .frame(width: 6, height: 6)
                    .padding(.bottom, 3)

                VStack(alignment: .leading, spacing: 2) {
                    Text(window.displayTitle)
                        .font(.system(size: 10, weight: .semibold))
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Text(window.subtitle(language: settings.language))
                        .font(.system(size: 8))
                        .foregroundStyle(.white.opacity(0.70))
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                if index < 9 {
                    Text("⌘\(index + 1)")
                        .font(.system(size: 8, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.78))
                }

                if isActive {
                    Text(settings.localized("window.active"))
                        .font(.system(size: 8, weight: .semibold))
                        .foregroundStyle(VantageTheme.success)
                }
            }
            .padding(8)
            .foregroundStyle(.white)
            .background(.black.opacity(0.68))
        }
        .aspectRatio(16 / 10, contentMode: .fit)
        .background(.black)
        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .stroke(
                    showsActiveHighlight ? settings.accentChoice.color : Color.white.opacity(0.18),
                    lineWidth: showsActiveHighlight ? 3 : 1
                )
        }
    }

    private func selectWindow() {
        let shouldActivate = compact ? settings.activateOnOverlayClick : true
        let didSelect = captureService.select(window.id, activate: shouldActivate)

        guard compact, shouldActivate, didSelect else { return }
        DispatchQueue.main.async {
            if NSApp.isActive {
                NSApp.deactivate()
            }
        }
    }

    private var activeMark: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(VantageTheme.success)
                .frame(width: 6, height: 6)
            Text(settings.localized("window.active"))
                .font(.system(size: 9, weight: .semibold))
                .foregroundStyle(VantageTheme.success)
        }
        .help(settings.localized("window.active"))
        .accessibilityLabel(settings.localized("window.active"))
    }

    @ViewBuilder
    private var previewImage: some View {
        if let image = window.preview {
            Image(nsImage: image)
                .resizable()
                .scaledToFit()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(.black)
                .clipped()
        } else {
            ZStack {
                VantageTheme.panel
                VStack(spacing: 6) {
                    Image(systemName: "rectangle.slash")
                        .font(.system(size: compact ? 18 : 22, weight: .light))
                    Text(settings.localized("window.previewUnavailable"))
                        .font(.system(size: compact ? 9 : 10))
                }
                .foregroundStyle(VantageTheme.secondaryText)
            }
        }
    }

    private var overlayDragGuard: some Gesture {
        DragGesture(minimumDistance: 6)
            .onChanged { value in
                guard compact else { return }
                if hypot(value.translation.width, value.translation.height) >= 6 {
                    didDragOverlay = true
                }
            }
            .onEnded { _ in
                guard compact else { return }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.12) {
                    didDragOverlay = false
                }
            }
    }
}

struct OverlayThumbnailView: View {
    let windowID: CGWindowID

    @EnvironmentObject private var captureService: WindowCaptureService
    @EnvironmentObject private var settings: SettingsStore

    var body: some View {
        Group {
            if let window = captureService.window(withID: windowID),
               let index = captureService.windows.firstIndex(where: { $0.id == windowID }) {
                PreviewCardView(window: window, index: index, compact: true)
            } else {
                Color.clear
            }
        }
        .padding(2)
        .background(Color.clear)
    }
}
