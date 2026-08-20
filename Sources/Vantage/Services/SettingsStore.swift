import Foundation

struct SavedOverlayPosition: Codable, Equatable {
    let x: Double
    let y: Double

    init(x: Double, y: Double) {
        self.x = x
        self.y = y
    }
}

@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let exactBundleIdentifiers = "exactBundleIdentifiers"
        static let exactOwnerNames = "exactOwnerNames"
        static let showOverlays = "showOverlays"
        static let activateOnOverlayClick = "activateOnOverlayClick"
        static let alwaysOnTop = "alwaysOnTop"
        static let overlayOpacity = "overlayOpacity"
        static let previewWidth = "previewWidth"
        static let previewRefreshRate = "previewRefreshRate"
        static let previewLayout = "previewLayout"
        static let accentChoice = "accentChoice"
        static let showMetadata = "showMetadata"
        static let language = "language"
        static let overlayPositions = "overlayPositions"
    }

    private let defaults: UserDefaults

    @Published var exactBundleIdentifiers: String {
        didSet { defaults.set(exactBundleIdentifiers, forKey: Key.exactBundleIdentifiers) }
    }

    @Published var exactOwnerNames: String {
        didSet { defaults.set(exactOwnerNames, forKey: Key.exactOwnerNames) }
    }

    @Published var showOverlays: Bool {
        didSet { defaults.set(showOverlays, forKey: Key.showOverlays) }
    }

    @Published var activateOnOverlayClick: Bool {
        didSet { defaults.set(activateOnOverlayClick, forKey: Key.activateOnOverlayClick) }
    }

    @Published var alwaysOnTop: Bool {
        didSet { defaults.set(alwaysOnTop, forKey: Key.alwaysOnTop) }
    }

    @Published var overlayOpacity: Double {
        didSet { defaults.set(overlayOpacity, forKey: Key.overlayOpacity) }
    }

    @Published var previewWidth: Double {
        didSet { defaults.set(previewWidth, forKey: Key.previewWidth) }
    }

    @Published var previewRefreshRate: PreviewRefreshRate {
        didSet { defaults.set(previewRefreshRate.rawValue, forKey: Key.previewRefreshRate) }
    }

    @Published var previewLayout: PreviewLayout {
        didSet { defaults.set(previewLayout.rawValue, forKey: Key.previewLayout) }
    }

    @Published var accentChoice: AccentChoice {
        didSet { defaults.set(accentChoice.rawValue, forKey: Key.accentChoice) }
    }

    @Published var showMetadata: Bool {
        didSet { defaults.set(showMetadata, forKey: Key.showMetadata) }
    }

    @Published var language: AppLanguage {
        didSet { defaults.set(language.rawValue, forKey: Key.language) }
    }

    @Published var isPaused = false

    private var overlayPositions: [String: SavedOverlayPosition]

    var exactBundleIdentifierList: [String] {
        exactBundleIdentifiers.split(separator: ",").map(String.init)
    }

    var exactOwnerNameList: [String] {
        exactOwnerNames.split(separator: ",").map(String.init)
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: [
            Key.exactBundleIdentifiers: "",
            Key.exactOwnerNames: WindowFilter.defaultExactApplicationOwnerNames.joined(separator: ", "),
            Key.showOverlays: false,
            Key.activateOnOverlayClick: true,
            Key.alwaysOnTop: true,
            Key.overlayOpacity: 0.94,
            Key.previewWidth: 300.0,
            Key.previewRefreshRate: PreviewRefreshRate.fps4.rawValue,
            Key.previewLayout: PreviewLayout.grid.rawValue,
            Key.accentChoice: AccentChoice.blue.rawValue,
            Key.showMetadata: true,
            Key.language: AppLanguage.systemDefault.rawValue,
            Key.overlayPositions: Data()
        ])

        exactBundleIdentifiers = defaults.string(forKey: Key.exactBundleIdentifiers) ?? ""
        exactOwnerNames = defaults.string(forKey: Key.exactOwnerNames)
            ?? WindowFilter.defaultExactApplicationOwnerNames.joined(separator: ", ")
        showOverlays = defaults.bool(forKey: Key.showOverlays)
        activateOnOverlayClick = defaults.bool(forKey: Key.activateOnOverlayClick)
        alwaysOnTop = defaults.bool(forKey: Key.alwaysOnTop)
        overlayOpacity = defaults.double(forKey: Key.overlayOpacity)
        previewWidth = defaults.double(forKey: Key.previewWidth)
        previewRefreshRate = PreviewRefreshRate(
            rawValue: defaults.integer(forKey: Key.previewRefreshRate)
        ) ?? .fps4
        previewLayout = PreviewLayout(rawValue: defaults.string(forKey: Key.previewLayout) ?? "") ?? .grid
        accentChoice = AccentChoice(rawValue: defaults.string(forKey: Key.accentChoice) ?? "") ?? .blue
        showMetadata = defaults.bool(forKey: Key.showMetadata)
        language = AppLanguage(rawValue: defaults.string(forKey: Key.language) ?? "") ?? .systemDefault
        if let data = defaults.data(forKey: Key.overlayPositions),
           let decoded = try? JSONDecoder().decode([String: SavedOverlayPosition].self, from: data) {
            overlayPositions = decoded
        } else {
            overlayPositions = [:]
        }
    }

    func savedOverlayOrigin(for key: String) -> CGPoint? {
        guard let position = overlayPositions[key] else { return nil }
        return CGPoint(x: position.x, y: position.y)
    }

    func saveOverlayOrigin(_ origin: CGPoint, for key: String) {
        overlayPositions[key] = SavedOverlayPosition(x: origin.x, y: origin.y)
        persistOverlayPositions()
    }

    private func persistOverlayPositions() {
        guard let data = try? JSONEncoder().encode(overlayPositions) else { return }
        defaults.set(data, forKey: Key.overlayPositions)
    }

    func localized(_ key: String, values: [String: String] = [:]) -> String {
        L10n.string(key, language: language, values: values)
    }
}
