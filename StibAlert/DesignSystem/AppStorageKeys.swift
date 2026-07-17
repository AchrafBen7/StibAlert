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

    // Calques de la carte — préférences persistantes.
    //
    // Le défaut n'est PLUS « tout allumé ». L'ancien commentaire disait « tous
    // visibles pour ne pas dérouter au 1er lancement » : c'était l'inverse. Six
    // calques simultanés (dont Villo et ses ~350 stations) saturent la carte, et
    // l'utilisateur ne sait plus ce qu'il regarde.
    //
    // Par défaut on répond à UNE question : « qu'est-ce qui roule autour de moi,
    // et est-ce que ça va ? » → arrêts STIB + gares SNCB + alertes. Villo, les
    // événements, De Lijn et TEC restent à un tap, dans le panneau Calques.
    static let mapLayerShowStibStops = "mapLayerShowStibStops"
    static let mapLayerShowSncbStations = "mapLayerShowSncbStations"
    static let mapLayerShowVilloStations = "mapLayerShowVilloStations"
    static let mapLayerShowEventImpacts = "mapLayerShowEventImpacts"
    static let mapLayerShowDelijnStops = "mapLayerShowDelijnStops"
    static let mapLayerShowTecStops = "mapLayerShowTecStops"
    // Signalements sur la carte : communauté (orange) + officiels (bleu). Défaut
    // visible (true) — c'est le cœur de l'app — mais l'utilisateur peut masquer
    // ces gros blocs pour une carte épurée.
    static let mapLayerShowCommunitySignals = "mapLayerShowCommunitySignals"
    static let mapLayerShowOfficialSignals = "mapLayerShowOfficialSignals"
    /// Restreint les signalements communautaires à ceux qui concernent
    /// l'utilisateur (lignes favorites + arrêts domicile/travail). Défaut off.
    static let mapLayerSignalsFavoritesOnly = "mapLayerSignalsFavoritesOnly"

    /// Migration unique. `@AppStorage` n'applique sa valeur par défaut que si la
    /// clé est **absente** : les installations existantes ont déjà `true` écrit en
    /// dur pour les 4 calques secondaires. Sans cette migration, elles gardent la
    /// carte saturée et le nouveau défaut ne se voit jamais.
    static let mapLayersCalmDefaultApplied = "mapLayersCalmDefaultApplied.v1"

    // RGPD / Privacy consent
    static let hasAcceptedPrivacyConsent = "hasAcceptedPrivacyConsent"
    static let privacyConsentAcceptedAt = "privacyConsentAcceptedAt"
    static let privacyConsentVersion = "privacyConsentVersion"
    static let analyticsOptIn = "analyticsOptIn"
}

enum PrivacyConsent {
    static let currentVersion = "v1-2026-05"
}

enum MapLayerDefaults {
    /// Calques à la demande : ils ajoutent des marqueurs sans répondre à la
    /// question principale (« ça roule autour de moi ? »). Villo pèse le plus
    /// lourd — ~350 stations rien qu'à Bruxelles.
    static let secondary = [
        AppStorageKeys.mapLayerShowVilloStations,
        AppStorageKeys.mapLayerShowEventImpacts,
        AppStorageKeys.mapLayerShowDelijnStops,
        AppStorageKeys.mapLayerShowTecStops,
    ]

    /// Éteint les calques secondaires **une seule fois**, pour les installations
    /// antérieures à ce changement (elles ont déjà `true` écrit en dur, que le
    /// nouveau défaut de `@AppStorage` ne peut pas atteindre). Une fois la
    /// migration passée, le choix de l'utilisateur redevient roi : jamais réécrasé.
    static func applyCalmDefaultIfNeeded() {
        let defaults = UserDefaults.standard
        guard !defaults.bool(forKey: AppStorageKeys.mapLayersCalmDefaultApplied) else { return }
        secondary.forEach { defaults.set(false, forKey: $0) }
        defaults.set(true, forKey: AppStorageKeys.mapLayersCalmDefaultApplied)
    }
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
