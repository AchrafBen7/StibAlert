import Foundation

enum AppLocale {
    static var languageCode: String {
        let preferred = Locale.preferredLanguages.first?.lowercased() ?? "fr"
        return preferred.hasPrefix("nl") ? "nl" : "fr"
    }

    static var localeIdentifier: String {
        languageCode == "nl" ? "nl_BE" : "fr_BE"
    }

    static var speechIdentifier: String {
        languageCode == "nl" ? "nl-BE" : "fr-BE"
    }

    static var current: Locale {
        Locale(identifier: localeIdentifier)
    }
}
