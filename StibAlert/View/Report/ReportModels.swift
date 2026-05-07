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
    case accident
    case delay
    case breakdown
    case incivility
    case cleanliness
    case aggression

    var id: String { rawValue }

    var title: String {
        switch self {
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
        case .accident:
            return ["Collision ou chute", "Police ou pompiers sur place"]
        case .delay:
            return ["Plus de 10 min d’attente?", "Transport non arrivé?"]
        case .breakdown:
            return ["Véhicule bloqué", "Portes ou moteur en panne"]
        case .incivility:
            return ["Musique ou cris forts", "Portes ou moteur en panne"]
        case .cleanliness:
            return ["Déchets ou odeur forte", "Sol ou siège très sale"]
        case .aggression:
            return ["Comportement violent", "Harcèlement observé"]
        }
    }

    var backgroundColor: Color {
        switch self {
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
}
