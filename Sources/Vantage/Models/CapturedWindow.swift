import AppKit
import CoreGraphics
import SwiftUI

struct CapturedWindow: Identifiable {
    let id: CGWindowID
    let processIdentifier: pid_t
    let ownerName: String
    let bundleIdentifier: String?
    let title: String
    let frame: CGRect
    let instanceOrdinal: Int
    var preview: NSImage?

    var displayTitle: String {
        title.isEmpty ? ownerName : title
    }

    var subtitle: String {
        ownerName
    }

    func subtitle(language: AppLanguage) -> String {
        title.isEmpty ? L10n.string("window.fallbackTitle", language: language, values: ["id": "\(id)"]) : ownerName
    }

    /// Stable while the application's duplicate-window ordering and geometry remain consistent.
    var overlayPositionKey: String {
        let identity = [
            bundleIdentifier ?? ownerName,
            ownerName,
            title,
            String(instanceOrdinal),
            String(Int(frame.width.rounded())),
            String(Int(frame.height.rounded()))
        ].joined(separator: "\u{0}")
        return Data(identity.utf8).base64EncodedString()
    }
}

enum CaptureState: Equatable {
    case idle
    case refreshing
    case ready
    case permissionRequired
    case failed(String)

    func label(for language: AppLanguage) -> String {
        switch self {
        case .idle:
            L10n.string("capture.idle", language: language)
        case .refreshing:
            L10n.string("capture.refreshing", language: language)
        case .ready:
            L10n.string("capture.ready", language: language)
        case .permissionRequired:
            L10n.string("capture.permissionRequired", language: language)
        case .failed:
            L10n.string("capture.failed", language: language)
        }
    }

    var symbolName: String {
        switch self {
        case .idle:
            "circle"
        case .refreshing:
            "arrow.trianglehead.2.clockwise.rotate.90"
        case .ready:
            "checkmark.circle.fill"
        case .permissionRequired:
            "lock.trianglebadge.exclamationmark"
        case .failed:
            "exclamationmark.triangle.fill"
        }
    }
}

enum WindowActivationError: Equatable {
    case permissionRequired
    case processUnavailable
    case targetWindowNotFound
    case activationFailed

    var messageKey: String {
        switch self {
        case .permissionRequired: "activation.permissionRequired"
        case .processUnavailable: "activation.processUnavailable"
        case .targetWindowNotFound: "activation.targetWindowNotFound"
        case .activationFailed: "activation.activationFailed"
        }
    }
}

enum PreviewLayout: String, CaseIterable, Identifiable {
    case grid
    case vertical
    case horizontal

    var id: String { rawValue }

    func title(for language: AppLanguage) -> String {
        switch self {
        case .grid: L10n.string("layout.grid", language: language)
        case .vertical: L10n.string("layout.vertical", language: language)
        case .horizontal: L10n.string("layout.horizontal", language: language)
        }
    }

    var symbolName: String {
        switch self {
        case .grid: "square.grid.2x2"
        case .vertical: "rectangle.stack"
        case .horizontal: "rectangle.split.3x1"
        }
    }
}

enum PreviewRefreshRate: Int, CaseIterable, Identifiable {
    case fps1 = 1
    case fps2 = 2
    case fps4 = 4
    case fps8 = 8

    var id: Int { rawValue }

    func title(for language: AppLanguage) -> String {
        "\(rawValue) FPS"
    }

    var interval: Duration {
        .milliseconds(1_000 / rawValue)
    }
}

enum AccentChoice: String, CaseIterable, Identifiable {
    case blue
    case green
    case orange
    case red

    var id: String { rawValue }

    var color: Color {
        switch self {
        case .blue: Color(red: 0.039, green: 0.518, blue: 1.0)
        case .green: Color(red: 0.188, green: 0.820, blue: 0.345)
        case .orange: Color(red: 1.0, green: 0.624, blue: 0.039)
        case .red: Color(red: 1.0, green: 0.271, blue: 0.227)
        }
    }

    var nsColor: NSColor {
        NSColor(color)
    }
}
