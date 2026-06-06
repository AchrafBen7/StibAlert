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

    var label: String {
        switch self {
        case .low:
            return "faible"
        case .medium:
            return "moyenne"
        case .high:
            return "élevée"
        }
    }

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
    case control      // Contrôle — différenciateur #1 vs app officielle
    case crowding     // Affluence — info "humaine" que la STIB ne donne pas
    case delay
    case breakdown
    case accident
    case incivility
    case cleanliness
    case aggression

    var id: String { rawValue }

    // ⚠️ `title` est la valeur ENVOYÉE au backend (typeProbleme). Doit matcher
    // EXACTEMENT l'enum Signalement.js : "Contrôle", "Affluence", …
    var title: String {
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

    var descriptionLines: [String] {
        switch self {
        case .control:
            return ["Contrôleurs à l’arrêt ou à bord", "Vérification des titres en cours"]
        case .crowding:
            return ["Véhicule bondé", "Impossible de monter"]
        case .accident:
            return ["Collision ou chute", "Police ou pompiers sur place"]
        case .delay:
            return ["Plus de 10 min d’attente?", "Transport non arrivé?"]
        case .breakdown:
            return ["Véhicule bloqué", "Portes ou moteur en panne"]
        case .incivility:
            return ["Musique ou cris forts", "Comportement gênant répété"]
        case .cleanliness:
            return ["Déchets ou odeur forte", "Sol ou siège très sale"]
        case .aggression:
            return ["Comportement violent", "Harcèlement observé"]
        }
    }

    /// Libellé LOCALISÉ pour l'AFFICHAGE (≠ `title`, qui reste la valeur
    /// canonique française envoyée au backend). Réutilise le localizer partagé.
    var localizedTitle: String {
        SignalementDTO.localizedReportType(title)
    }

    /// Sous-titre court LOCALISÉ (1ʳᵉ ligne de `descriptionLines`) pour le picker.
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

    var helpDescription: String {
        switch self {
        case .control:
            return "Contrôleurs présents à l’arrêt ou dans le véhicule."
        case .crowding:
            return "Véhicule plein, impossible ou difficile de monter."
        case .accident:
            return "Collision, chute, blessé ou véhicule endommagé."
        case .delay:
            return "Plus de 10 min d’attente, transport qui n’arrive pas."
        case .breakdown:
            return "Véhicule bloqué ou portes qui ne s’ouvrent pas."
        case .incivility:
            return "Cris, musique forte, comportements dérangeants."
        case .cleanliness:
            return "Mauvaises odeurs, saleté au sol ou sur les sièges."
        case .aggression:
            return "Personne violente ou harcèlement observé."
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
