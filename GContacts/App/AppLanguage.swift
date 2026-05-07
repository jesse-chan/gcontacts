import Foundation

enum AppLanguage: String, CaseIterable, Identifiable {
    case system
    case english
    case traditionalChinese

    var id: String { rawValue }

    var localizedTitle: String.LocalizationValue {
        switch self {
        case .system: "language.system"
        case .english: "language.english"
        case .traditionalChinese: "language.traditionalChinese"
        }
    }

    var locale: Locale {
        Locale(identifier: localeIdentifier)
    }

    private var localeIdentifier: String {
        switch self {
        case .system: Self.systemLocaleIdentifier
        case .english: "en"
        case .traditionalChinese: "zh-Hant"
        }
    }

    private static var systemLocaleIdentifier: String {
        guard let languageCode = Locale.current.language.languageCode?.identifier else {
            return "en"
        }

        if languageCode == "zh" {
            return "zh-Hant"
        }

        if languageCode == "en" {
            return "en"
        }

        return "en"
    }
}
