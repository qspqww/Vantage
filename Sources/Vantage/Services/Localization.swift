import Foundation

enum AppLanguage: String, CaseIterable, Identifiable, Codable {
    case english = "en"
    case simplifiedChinese = "zh-Hans"

    var id: String { rawValue }

    func displayName(in language: AppLanguage) -> String {
        switch self {
        case .english:
            return L10n.string("language.english", language: language)
        case .simplifiedChinese:
            return L10n.string("language.simplifiedChinese", language: language)
        }
    }

    static var systemDefault: AppLanguage {
        Locale.current.identifier.lowercased().hasPrefix("zh") ? .simplifiedChinese : .english
    }
}

enum L10n {
    private static let catalogs: [AppLanguage: [String: String]] = [
        .english: loadCatalog(.english),
        .simplifiedChinese: loadCatalog(.simplifiedChinese)
    ]

    static func string(
        _ key: String,
        language: AppLanguage,
        values: [String: String] = [:]
    ) -> String {
        let template = catalogs[language]?[key]
            ?? catalogs[.english]?[key]
            ?? key

        return values.reduce(template) { result, item in
            result.replacingOccurrences(of: "{" + item.key + "}", with: item.value)
        }
    }

    private static func loadCatalog(_ language: AppLanguage) -> [String: String] {
        let resourceBundle = Bundle.main.url(
            forResource: "Vantage_Vantage",
            withExtension: "bundle"
        ).flatMap(Bundle.init(url:)) ?? Bundle.module

        let url = resourceBundle.url(
            forResource: language.rawValue,
            withExtension: "json",
            subdirectory: "Localization"
        ) ?? resourceBundle.url(
            forResource: language.rawValue,
            withExtension: "json"
        )

        guard let url,
        let data = try? Data(contentsOf: url),
        let catalog = try? JSONDecoder().decode([String: String].self, from: data)
        else {
            return [:]
        }

        return catalog
    }
}
