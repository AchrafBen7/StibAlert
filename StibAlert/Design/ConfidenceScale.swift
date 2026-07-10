import SwiftUI

// Source unique de vérité pour la confiance AFFICHÉE.
//
// Avant, les seuils étaient recopiés dans cinq fichiers. `SignalementsView`
// utilisait 85/65 pendant que `TransportViewAdapters` utilisait 90/75 : une
// confiance de 80 % s'affichait « Assez sûr » sur un écran et « Faible
// confirmation » sur l'autre. Un seul endroit décide désormais.
//
// ⚠️ Deux échelles DIFFÉRENTES, à ne pas confondre :
//   • `RouteConfidence`  — fiabilité d'un itinéraire recommandé (0…1)
//   • `ReportFreshness`  — fraîcheur d'un signalement communautaire, qui décroît
//                          avec le temps (`SignalementDTO.liveConfidence`)

/// Fiabilité d'un itinéraire recommandé.
enum RouteConfidence {
    case verySure
    case quiteSure
    case weak

    static let verySureThreshold = 0.90
    static let quiteSureThreshold = 0.75

    static func level(_ confidence: Double) -> RouteConfidence {
        switch confidence {
        case verySureThreshold...: return .verySure
        case quiteSureThreshold...: return .quiteSure
        default: return .weak
        }
    }

    /// « Très sûr »
    var label: String {
        switch self {
        case .verySure: return AppLocalizer.string("confidence.very_sure", defaultValue: "Très sûr")
        case .quiteSure: return AppLocalizer.string("confidence.quite_sure", defaultValue: "Assez sûr")
        case .weak: return AppLocalizer.string("confidence.weak", defaultValue: "Faible confirmation")
        }
    }

    /// « 92 % • très sûr »
    static func percentLabel(_ confidence: Double) -> String {
        let percent = Int((confidence * 100).rounded())
        switch level(confidence) {
        case .verySure:
            return AppLocalizer.format("confidence.pct.very_sure", defaultValue: "%lld%% • très sûr", percent)
        case .quiteSure:
            return AppLocalizer.format("confidence.pct.quite_sure", defaultValue: "%lld%% • assez sûr", percent)
        case .weak:
            return AppLocalizer.format("confidence.pct.weak", defaultValue: "%lld%% • faible confirmation", percent)
        }
    }
}

/// Fraîcheur d'un signalement communautaire (confiance décroissante).
enum ReportFreshness {
    case fresh
    case moderate
    case low

    static let freshThreshold = 0.70
    static let moderateThreshold = 0.35

    static func level(_ liveConfidence: Double) -> ReportFreshness {
        switch liveConfidence {
        case freshThreshold...: return .fresh
        case moderateThreshold..<freshThreshold: return .moderate
        default: return .low
        }
    }

    var label: String {
        switch self {
        case .fresh: return AppLocalizer.string("confidence.fresh", defaultValue: "Fraîche")
        case .moderate: return AppLocalizer.string("confidence.moderate", defaultValue: "Modérée")
        case .low: return AppLocalizer.string("confidence.low", defaultValue: "Faible")
        }
    }

    var tint: Color {
        switch self {
        case .fresh: return DS.Color.statusOK
        case .moderate: return DS.Color.statusMinor
        case .low: return DS.Color.inkMute
        }
    }

    var icon: String {
        switch self {
        case .fresh: return "checkmark.seal.fill"
        case .moderate: return "hourglass"
        case .low: return "questionmark.circle"
        }
    }
}
