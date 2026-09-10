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
    /// Les langues que l'app SAIT afficher. Ajouter un code ici ne suffit pas :
    /// il faut aussi le déclarer dans le projet Xcode (`knownRegions`), sinon
    /// aucun `.lproj` n'est produit et `AppLocalizer` retombe silencieusement
    /// sur le bundle principal — donc sur le français.
    static let supported = ["fr", "nl", "en"]

    /// Ramène n'importe quelle étiquette de langue ("en-GB", "NL", "fr_BE") à
    /// un code géré. Le repli est le français, langue source du catalogue.
    static func normalize(_ raw: String?) -> String {
        let value = (raw ?? "").lowercased()
        for code in supported where value.hasPrefix(code) {
            return code
        }
        return "fr"
    }

    static var languageCode: String {
        // 1. In-app override (Profil → Langues) read straight from UserDefaults
        // so this stays safe to call from any thread.
        if let override = UserDefaults.standard.string(forKey: AppLanguageStore.storageKey)?.lowercased(),
           !override.isEmpty {
            return normalize(override)
        }
        // 2. Sinon, on suit la langue RÉELLEMENT affichée par l'app
        // (Bundle.main.preferredLocalizations = intersection des langues du
        // téléphone avec celles fournies par l'app). C'est « la langue de l'app »
        // telle que l'utilisateur la voit à l'écran — donc la reconnaissance
        // vocale et la réponse de l'assistant collent à ce qui est affiché,
        // au lieu de suivre une langue système que l'app ne parle même pas.
        let appLang = (Bundle.main.preferredLocalizations.first
            ?? Locale.preferredLanguages.first
            ?? "fr").lowercased()
        return normalize(appLang)
    }

    /// Identifiant de locale pour un code donné, sans relire les préférences.
    /// Utile quand on connaît déjà la langue visée (override en cours
    /// d'application, prévisualisation, test).
    static func localeIdentifier(for code: String) -> String {
        switch code {
        case "nl": return "nl_BE"
        case "en": return "en_BE"
        default:   return "fr_BE"
        }
    }

    static var localeIdentifier: String {
        switch languageCode {
        case "nl": return "nl_BE"
        // en_BE existe et donne les conventions belges : 24 h, jour/mois.
        // en_US retournerait 12 h AM/PM et mois/jour — faux pour Bruxelles.
        case "en": return "en_BE"
        default:   return "fr_BE"
        }
    }

    static var speechIdentifier: String {
        switch languageCode {
        case "nl": return "nl-BE"
        // Pas d'« en-BE » en reconnaissance vocale iOS : en-GB est le variant
        // le plus proche de l'anglais entendu à Bruxelles.
        case "en": return "en-GB"
        default:   return "fr-BE"
        }
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
