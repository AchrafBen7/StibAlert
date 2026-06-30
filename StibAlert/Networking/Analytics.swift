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
    private static let appID = "REMPLACER-PAR-VOTRE-APP-ID"

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
        TelemetryDeck.signal(event.rawValue, parameters: parameters)
        #endif
    }

    /// Les 6 événements qui comptent pour mesurer usage, rétention et funnel.
    enum Event: String {
        case appOpened           = "App.opened"
        case onboardingCompleted = "Onboarding.completed"
        case signalementCreated  = "Signalement.created"
        case routeCalculated     = "Route.calculated"
        case favoriteAdded       = "Favorite.added"
        case pushOpened          = "Push.opened"
    }
}
