import Foundation

enum AppStorageKeys {
    static let hasSeenOnboarding = "hasSeenOnboarding"
    /// Tour 3-cards montré APRÈS l'onboarding (carte → signalement → voix).
    /// Mis à true à la fin du tour OU sur skip. Réinitialisable depuis
    /// Profil → Aide → "Revoir la visite guidée".
    static let hasSeenFeatureTour = "hasSeenFeatureTour"
    static let hasLaunchedBefore = "hasLaunchedBefore"
    static let lastUpdateDate = "lastUpdateDate"
    static let onboardingFavoriteLines = "onboardingFavoriteLines"
    static let onboardingStibFavoriteStops = "onboardingStibFavoriteStops"
    static let onboardingHomeLabel = "onboardingHomeLabel"
    static let onboardingDepartureTime = "onboardingDepartureTime"
    static let onboardingNeedsProfileSync = "onboardingNeedsProfileSync"
    static let onboardingLastAppliedUserId = "onboardingLastAppliedUserId"
    static let onboardingPendingPushPermission = "onboardingPendingPushPermission"
    /// Nudge "configure ton trajet quotidien" sur la Home : une fois écarté
    /// (ou la routine activée), on ne le ré-affiche plus.
    static let commuteNudgeDismissed = "commuteNudgeDismissed"

    // Calques de la carte — préférences persistantes pour que l'utilisateur
    // n'ait pas à re-décocher Villo/SNCB à chaque ouverture de l'app. Default
    // true (tous visibles) pour ne pas dérouter au 1er lancement.
    static let mapLayerShowStibStops = "mapLayerShowStibStops"
    static let mapLayerShowSncbStations = "mapLayerShowSncbStations"
    static let mapLayerShowVilloStations = "mapLayerShowVilloStations"
    static let mapLayerShowEventImpacts = "mapLayerShowEventImpacts"
    static let mapLayerShowDelijnStops = "mapLayerShowDelijnStops"
    static let mapLayerShowTecStops = "mapLayerShowTecStops"

    // RGPD / Privacy consent
    static let hasAcceptedPrivacyConsent = "hasAcceptedPrivacyConsent"
    static let privacyConsentAcceptedAt = "privacyConsentAcceptedAt"
    static let privacyConsentVersion = "privacyConsentVersion"
    static let analyticsOptIn = "analyticsOptIn"
}

enum PrivacyConsent {
    static let currentVersion = "v1-2026-05"
}

struct OnboardingPreferences: Equatable {
    let favoriteLines: [String]
    /// STIB stop backend ids the user picked during onboarding. Applied to the
    /// backend favourites once they sign in (SNCB / De Lijn / TEC favourites
    /// live in their own local stores and don't need this).
    let stibFavoriteStopIds: [String]
    let homeLabel: String
    let departureTime: String

    var hasUsefulData: Bool {
        !favoriteLines.isEmpty
            || !stibFavoriteStopIds.isEmpty
            || !homeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
}

enum OnboardingPreferenceStore {
    static func load() -> OnboardingPreferences {
        let defaults = UserDefaults.standard
        return OnboardingPreferences(
            favoriteLines: defaults.stringArray(forKey: AppStorageKeys.onboardingFavoriteLines) ?? [],
            stibFavoriteStopIds: defaults.stringArray(forKey: AppStorageKeys.onboardingStibFavoriteStops) ?? [],
            homeLabel: defaults.string(forKey: AppStorageKeys.onboardingHomeLabel) ?? "",
            departureTime: defaults.string(forKey: AppStorageKeys.onboardingDepartureTime) ?? "08:15"
        )
    }

    static func save(_ preferences: OnboardingPreferences) {
        let defaults = UserDefaults.standard
        defaults.set(preferences.favoriteLines, forKey: AppStorageKeys.onboardingFavoriteLines)
        defaults.set(preferences.stibFavoriteStopIds, forKey: AppStorageKeys.onboardingStibFavoriteStops)
        defaults.set(preferences.homeLabel, forKey: AppStorageKeys.onboardingHomeLabel)
        defaults.set(preferences.departureTime, forKey: AppStorageKeys.onboardingDepartureTime)
        defaults.set(true, forKey: AppStorageKeys.onboardingNeedsProfileSync)
    }

    static func shouldApply(for userId: String) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.bool(forKey: AppStorageKeys.onboardingNeedsProfileSync) else { return false }
        return defaults.string(forKey: AppStorageKeys.onboardingLastAppliedUserId) != userId
    }

    static func markApplied(for userId: String) {
        let defaults = UserDefaults.standard
        defaults.set(false, forKey: AppStorageKeys.onboardingNeedsProfileSync)
        defaults.set(userId, forKey: AppStorageKeys.onboardingLastAppliedUserId)
    }
}
