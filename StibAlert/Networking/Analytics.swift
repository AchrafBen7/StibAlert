import Foundation
#if canImport(TelemetryDeck)
import TelemetryDeck
#endif

/// Analytics produit, centralisé. Fournisseur : TelemetryDeck (privacy-first,
/// hébergé en EU, sans collecte de données personnelles → pas de bannière de
/// consentement requise).
///
/// IMPORTANT — ce wrapper compile **en no-op** tant que le package SPM
/// TelemetryDeck n'est pas ajouté au projet. Pour l'activer :
///   1. Xcode > File > Add Package Dependencies…
///      URL : https://github.com/TelemetryDeck/SwiftSDK
///   2. Créer une app sur https://dashboard.telemetrydeck.com (gratuit),
///      récupérer l'App ID, et le coller dans `appID` ci-dessous.
/// Dès que le package est présent, `canImport(TelemetryDeck)` devient vrai et
/// les événements partent automatiquement — aucun autre changement de code.
enum Analytics {

    /// App ID TelemetryDeck. À remplacer par le vôtre (dashboard TelemetryDeck).
    private static let appID = "C7C53B67-F546-47A9-BCAF-B70A124890CE"

    /// À appeler une fois au démarrage de l'app.
    static func start() {
        #if canImport(TelemetryDeck)
        guard !appID.hasPrefix("REMPLACER") else {
            #if DEBUG
            print("⚠️ Analytics: App ID TelemetryDeck non configuré — analytics inactif.")
            #endif
            return
        }
        TelemetryDeck.initialize(config: TelemetryDeck.Config(appID: appID))
        #endif
    }

    /// Envoie un événement. No-op si le SDK n'est pas présent.
    static func track(_ event: Event, _ parameters: [String: String] = [:]) {
        #if canImport(TelemetryDeck)
        // L'écran de consentement promet un opt-in (« Statistiques (optionnel) »,
        // défaut décoché) et un réglage dans Profil → Confidentialité. Avant ce
        // garde, la clé `analyticsOptIn` n'était LUE nulle part : TelemetryDeck
        // émettait même après refus. Un consentement qui ne contrôle rien est un
        // mensonge — et le questionnaire App Privacy déclare cette collecte.
        guard UserDefaults.standard.bool(forKey: AppStorageKeys.analyticsOptIn) else { return }
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
        #endif
    }

    /// Les événements du funnel d'activation + rétention.
    ///
    /// ⚠️ RÈGLE ABSOLUE : un événement ne porte JAMAIS de donnée identifiante —
    /// pas de nom d'arrêt, pas de coordonnées, pas d'id utilisateur. Seulement un
    /// TYPE anonyme (`kind: stop|line`). Un événement ne doit jamais permettre de
    /// reconstituer la routine de quelqu'un. C'est ce qui garde TelemetryDeck
    /// hors du champ « donnée personnelle » du RGPD (+ opt-in décoché par défaut).
    ///
    /// La rétention J+1 / J+7 n'a PAS d'événement dédié : TelemetryDeck la calcule
    /// depuis la récurrence de `App.opened` (d'où le passage en foreground, pas
    /// seulement au démarrage à froid).
    enum Event: String {
        case appOpened           = "App.opened"
        case onboardingCompleted = "Onboarding.completed"
        case locationGranted     = "Location.granted"   // le premier goulot du funnel
        case locationDenied      = "Location.denied"
        case favoriteAdded       = "Favorite.added"     // paramètre kind: stop | line
        case routeCalculated     = "Route.calculated"
        case alertViewed         = "Alert.viewed"
        case signalementStarted  = "Signalement.started"   // feuille ouverte
        case signalementCreated  = "Signalement.created"   // réellement envoyé
        case pushOpened          = "Push.opened"
    }
}
