import CoreGraphics
import Foundation

enum WindowFilter {
    static let defaultExactApplicationOwnerNames = [
        "EVE Online",
        "EVE",
        "Wine64-preloader",
        "PlayCover"
    ]

    static let ignoredOwners = [
        "Window Server",
        "Dock",
        "Control Center",
        "Notification Center",
        "Spotlight",
        "Vantage"
    ]

    static func isEligible(
        ownerName: String,
        bundleIdentifier: String?,
        exactBundleIdentifiers: [String],
        exactOwnerNames: [String]
    ) -> Bool {
        guard !ignoredOwners.contains(ownerName) else { return false }
        guard !ownerName.isEmpty else { return false }

        let normalizedOwner = normalize(ownerName)
        let normalizedBundle = bundleIdentifier.map(normalize)
        let ownerMatches = exactOwnerNames
            .map(normalize)
            .contains(normalizedOwner)
        let bundleMatches = normalizedBundle.map { bundle in
            exactBundleIdentifiers.map(normalize).contains(bundle)
        } ?? false

        return ownerMatches || bundleMatches
    }

    static func isNormalWindow(
        isOnScreen: Bool,
        windowLayer: Int,
        title: String?,
        frame: CGRect
    ) -> Bool {
        guard isOnScreen, windowLayer == 0 else { return false }
        guard frame.width >= 320, frame.height >= 180 else { return false }
        guard let title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return false
        }
        return true
    }

    private static func normalize(_ value: String) -> String {
        value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func matchesSearch(_ window: CapturedWindow, query: String) -> Bool {
        let normalizedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        guard !normalizedQuery.isEmpty else { return true }

        return [window.ownerName, window.title, window.bundleIdentifier ?? ""]
            .joined(separator: " ")
            .lowercased()
            .contains(normalizedQuery)
    }
}
