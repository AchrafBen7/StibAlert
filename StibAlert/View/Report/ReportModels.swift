import SwiftUI
import CoreLocation

struct StopLine: Identifiable {
    let id = UUID()
    let number: String
    let color: Color
}

struct NearbyStop: Identifiable {
    let id = UUID()
    let backendId: String?
    let stopId: String?
    let name: String
    let lines: [StopLine]
    let distanceMeters: Int
    let issueLines: [NearbyIssueLine]
    var coordinate: CLLocationCoordinate2D? = nil

    init(backendId: String?, stopId: String? = nil, name: String, lines: [StopLine], distanceMeters: Int, issueLines: [NearbyIssueLine], coordinate: CLLocationCoordinate2D? = nil) {
        self.backendId = backendId
        self.stopId = stopId
        self.name = name
        self.lines = lines
        self.distanceMeters = distanceMeters
        self.issueLines = issueLines
        self.coordinate = coordinate
    }
}

struct NearbyIssueLine: Identifiable {
    let id = UUID()
    let number: String
    let color: Color
    let direction: String
    let crowding: IssueLineCrowding
    let reliability: Int
    let lineTextColor: Color
}

enum IssueLineCrowding {
    case low
    case medium
    case high

    var level: Int {
        switch self {
        case .low:
            return 1
        case .medium:
            return 3
        case .high:
            return 5
        }
    }
}

enum ReportProblemType: String, CaseIterable, Identifiable {
    case control      // Contrôle — MASQUÉ au lancement, cf. `selectableCases`
    case crowding     // Affluence — info "humaine" que la STIB ne donne pas
    case delay
    case breakdown
    case accident
    case incivility
    case cleanliness
    case aggression

    /// Les types réellement PROPOSÉS à l'utilisateur.
    ///
    /// `control` (« contrôleurs à tel arrêt ») en est retiré pour le lancement.
    /// Signaler la position des contrôleurs se lit trop facilement comme une aide
    /// à la fraude : c'est un angle d'attaque gratuit face à la STIB (dont on
    /// consomme les données ouvertes) et un motif de rejet plausible à l'App Store.
    ///
    /// ⚠️ Le `case` reste dans l'enum : des signalements de ce type existent DÉJÀ
    /// en base et doivent continuer à se décoder et à s'afficher. On masque
    /// l'entrée, on ne casse pas l'historique. Pour le réactiver : remettre
    /// `allCases` ici.
    static var selectableCases: [ReportProblemType] {
        allCases.filter { $0 != .control }
    }

    var id: String { rawValue }

    // ⚠️ `title` est la valeur ENVOYÉE au backend (typeProbleme). Doit matcher
    // EXACTEMENT l'enum Signalement.js : "Contrôle", "Affluence", …
    // L'affichage passe par `localizedTitle`.
    var title: String { // i18n:ignore — valeur backend, la traduire casserait l'envoi
        switch self {
        case .control:
            return "Contrôle"
        case .crowding:
            return "Affluence"
        case .accident:
            return "Accident"
        case .delay:
            return "Retard"
        case .breakdown:
            return "Panne"
        case .incivility:
            return "Incivilité"
        case .cleanliness:
            return "Propreté"
        case .aggression:
            return "Agression"
        }
    }

    /// Libellé LOCALISÉ pour l'AFFICHAGE (≠ `title`, qui reste la valeur
    /// canonique française envoyée au backend). Réutilise le localizer partagé.
    var localizedTitle: String {
        SignalementDTO.localizedReportType(title)
    }

    /// Sous-titre court LOCALISÉ affiché sous chaque catégorie du picker.
    var localizedShortDescription: String {
        switch self {
        case .control:     return AppLocalizer.string("report.help.control", defaultValue: "Contrôleurs à l’arrêt ou à bord")
        case .crowding:    return AppLocalizer.string("report.help.crowding", defaultValue: "Véhicule bondé")
        case .accident:    return AppLocalizer.string("report.help.accident", defaultValue: "Collision ou chute")
        case .delay:       return AppLocalizer.string("report.help.delay", defaultValue: "Plus de 10 min d’attente?")
        case .breakdown:   return AppLocalizer.string("report.help.breakdown", defaultValue: "Véhicule bloqué")
        case .incivility:  return AppLocalizer.string("report.help.incivility", defaultValue: "Musique ou cris forts")
        case .cleanliness: return AppLocalizer.string("report.help.cleanliness", defaultValue: "Déchets ou odeur forte")
        case .aggression:  return AppLocalizer.string("report.help.aggression", defaultValue: "Comportement violent")
        }
    }

    var backgroundColor: Color {
        switch self {
        case .control:
            return Color(hex: "#D9C9FF")
        case .crowding:
            return Color(hex: "#FFD9B0")
        case .accident:
            return Color(hex: "#FFB4B4")
        case .delay:
            return Color(hex: "#FFB9EE")
        case .breakdown:
            return Color(hex: "#FFED91")
        case .incivility:
            return Color(hex: "#BBDCFF")
        case .cleanliness:
            return Color(hex: "#CBFBE6")
        case .aggression:
            return Color(hex: "#FFCFA1")
        }
    }

    var accentColor: Color {
        switch self {
        case .control:
            return Color(hex: "#8B5CF6")
        case .crowding:
            return Color(hex: "#F59A3B")
        case .accident:
            return Color(hex: "#FF6B6B")
        case .delay:
            return Color(hex: "#EE63D8")
        case .breakdown:
            return Color(hex: "#FFD34D")
        case .incivility:
            return Color(hex: "#73A9F8")
        case .cleanliness:
            return Color(hex: "#45D29A")
        case .aggression:
            return Color(hex: "#FF922E")
        }
    }


    // S2/S3 — Sévérité structurée, source de vérité UNIQUE pour le tri des
    // alertes. Doit rester alignée avec le backend (CRITICAL_INCIDENT_TYPES =
    // {Accident, Agression} qui bypass les quiet hours → rangs les plus hauts).
    var severityRank: Int {
        switch self {
        case .aggression: return 10
        case .accident:   return 9
        case .breakdown:  return 5
        case .delay:      return 4
        case .control:    return 4  // utile/actionnable mais non critique
        case .crowding:   return 3
        case .incivility: return 3
        case .cleanliness: return 2
        }
    }

    /// Les types "critiques" qui réveillent l'utilisateur (cohérent avec le
    /// backend). Sert aussi à afficher un bandeau de responsabilisation dans
    /// le sheet de signalement.
    var isCritical: Bool {
        self == .aggression || self == .accident
    }

    /// Résout le rang de sévérité depuis le `typeProbleme` brut (String stockée
    /// côté signalement : "Accident", "Retard"…). Tolérant : accent/casse, et
    /// quelques libellés officiels STIB ("Travaux", "Interruption"…).
    static func severityRank(forRawType rawType: String?) -> Int {
        guard let rawType else { return 0 }
        let norm = rawType
            .folding(options: .diacriticInsensitive, locale: AppLocale.current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        if let match = allCases.first(where: {
            $0.title.folding(options: .diacriticInsensitive, locale: AppLocale.current).lowercased() == norm
        }) {
            return match.severityRank
        }
        // Libellés officiels hors enum communautaire.
        if norm.contains("interrup") || norm.contains("suspend") { return 9 }
        if norm.contains("travaux") || norm.contains("devi") { return 6 }
        if norm.contains("retard") { return 4 }
        return 1
    }
}
