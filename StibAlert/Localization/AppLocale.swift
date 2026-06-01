import Foundation
import Combine

/// Single source of truth for the in-app language override. We keep both an
/// observable @Published (so SwiftUI can react to a change inside Profil →
/// Langues) AND a plain UserDefaults read (so non-actor code like networking
/// or date formatters can resolve the locale safely on any thread).
@MainActor
final class AppLanguageStore: ObservableObject {
    static let shared = AppLanguageStore()

    nonisolated static let storageKey = "appLanguageOverride"

    @Published private(set) var languageOverride: String?

    private init() {
        let stored = UserDefaults.standard.string(forKey: Self.storageKey)
        self.languageOverride = (stored?.isEmpty == false) ? stored : nil
    }

    /// Pass nil (or an empty string) to fall back to the iOS system language.
    func setOverride(_ code: String?) {
        let normalized = code?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if let normalized, !normalized.isEmpty {
            languageOverride = normalized
            UserDefaults.standard.set(normalized, forKey: Self.storageKey)
        } else {
            languageOverride = nil
            UserDefaults.standard.removeObject(forKey: Self.storageKey)
        }
    }
}

enum AppLocale {
    static var languageCode: String {
        // 1. In-app override (Profil → Langues) read straight from UserDefaults
        // so this stays safe to call from any thread.
        if let override = UserDefaults.standard.string(forKey: AppLanguageStore.storageKey)?.lowercased(),
           !override.isEmpty {
            return override.hasPrefix("nl") ? "nl" : "fr"
        }
        // 2. Fall back to the iOS system language.
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

enum AppLocalizer {
    private static var localizedBundle: Bundle {
        guard let path = Bundle.main.path(forResource: AppLocale.languageCode, ofType: "lproj"),
              let bundle = Bundle(path: path) else {
            return .main
        }
        return bundle
    }

    static func string(_ key: String, defaultValue: String? = nil) -> String {
        localizedBundle.localizedString(forKey: key, value: defaultValue ?? key, table: nil)
    }

    static func format(_ key: String, defaultValue: String? = nil, _ arguments: CVarArg...) -> String {
        String(format: string(key, defaultValue: defaultValue), locale: AppLocale.current, arguments: arguments)
    }
}
