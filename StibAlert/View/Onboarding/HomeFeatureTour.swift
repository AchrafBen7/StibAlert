import SwiftUI
import TipKit

// 3-tip onboarding tour shown the first time the user reaches HomeView after
// completing onboarding (push permission step). Tips are sequenced via
// TipGroup so only one shows at a time, in declared order.

@available(iOS 17.0, *)
struct HomeMapTip: Tip {
    var title: Text {
        Text("Voici la carte")
    }

    var message: Text? {
        Text("Tu vois les arrêts, les signalements de la communauté et les perturbations en temps réel autour de toi.")
    }

    var image: Image? {
        Image(systemName: "map.fill")
    }
}

@available(iOS 17.0, *)
struct HomeVerdictTip: Tip {
    var title: Text {
        Text("Trouve ton verdict")
    }

    var message: Text? {
        Text("Cherche un arrêt ou une destination ici. StibAlert te dit si la route est libre et te propose un plan B.")
    }

    var image: Image? {
        Image(systemName: "checkmark.seal.fill")
    }
}

@available(iOS 17.0, *)
struct HomeReportTip: Tip {
    var title: Text {
        Text("Signale en 2 tap")
    }

    var message: Text? {
        Text("Tu vois un retard, une panne, un incident ? Préviens la communauté en quelques secondes.")
    }

    var image: Image? {
        Image(systemName: "exclamationmark.triangle.fill")
    }
}

@available(iOS 17.0, *)
enum HomeFeatureTour {
    static let map = HomeMapTip()
    static let verdict = HomeVerdictTip()
    static let report = HomeReportTip()

    @MainActor
    static func configure() {
        try? Tips.configure([
            .displayFrequency(.immediate),
            .datastoreLocation(.applicationDefault),
        ])
    }

    #if DEBUG
    /// Wipes TipKit datastore so all tips show again on next launch.
    /// Hook this to a dev menu (or call from `init()` temporarily) when
    /// re-testing the onboarding tour.
    @MainActor
    static func resetForTesting() {
        try? Tips.resetDatastore()
    }
    #endif
}

enum HomeTipKind {
    case map
    case verdict
    case report
}

extension View {
    /// Apply a HomeFeatureTour tip on iOS 17+, no-op on older iOS.
    ///
    /// Currently DISABLED: the popoverTip rendered as an empty white card on
    /// the first TestFlight build (no title/message visible, just an X), so we
    /// short-circuit it. Re-enable once we've reproduced + fixed the rendering
    /// issue (likely a TipKit datastore / iOS version quirk).
    func homeFeatureTip(_ kind: HomeTipKind) -> some View {
        self
    }
}
