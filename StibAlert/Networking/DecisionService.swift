import Foundation
import CoreLocation

enum DecisionService {
    static func current(
        coordinate: CLLocationCoordinate2D? = nil,
        line: String? = nil
    ) async throws -> DecisionDTO {
        var path = "/api/decision"
        var params: [String] = []
        if let coordinate {
            params.append("lat=\(coordinate.latitude)")
            params.append("lng=\(coordinate.longitude)")
        }
        if let line, !line.isEmpty {
            params.append("ligne=\(line.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? line)")
        }
        if !params.isEmpty {
            path += "?" + params.joined(separator: "&")
        }
        return try await APIClient.shared.request(path)
    }

    static func trip(
        origin: CLLocationCoordinate2D,
        destination: CLLocationCoordinate2D,
        destinationLabel: String? = nil
    ) async throws -> DecisionDTO {
        var path = "/api/decision?lat=\(origin.latitude)&lng=\(origin.longitude)"
        path += "&destLat=\(destination.latitude)&destLng=\(destination.longitude)"
        if let destinationLabel, !destinationLabel.isEmpty {
            let encoded = destinationLabel.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? destinationLabel
            path += "&destLabel=\(encoded)"
        }
        return try await APIClient.shared.request(path)
    }
}

enum DecisionVerdict: String, Codable {
    case allClear = "ALL_CLEAR"
    case watch = "WATCH"
    case caution = "CAUTION"
    case avoid = "AVOID"

    var emoji: String {
        switch self {
        case .allClear: return "✅"
        case .watch: return "👀"
        case .caution: return "⚠️"
        case .avoid: return "🚫"
        }
    }

    var ribbonColor: String {
        switch self {
        case .allClear: return "#10B981"
        case .watch: return "#6B7280"
        case .caution: return "#F59E0B"
        case .avoid: return "#E94E1B"
        }
    }

    var shortLabel: String {
        switch self {
        case .allClear: return "FLUIDE"
        case .watch: return "VEILLE"
        case .caution: return "PRUDENCE"
        case .avoid: return "ÉVITE"
        }
    }
}

enum DecisionSeverity: String, Codable {
    case none, weak, minor, major, critical, resolved
}

struct DecisionDTO: Decodable {
    let verdict: DecisionVerdict
    let headline: String
    let subhead: String?
    let severity: DecisionSeverity?
    let generatedAt: Date?
    let isInRoutineWindow: Bool?
    let affectedCluster: DecisionClusterRef?
    let recommendation: DecisionRecommendation?

    // Trip-specific fields (populated when /api/decision is called with destLat/destLng)
    let tripMode: Bool?
    let destinationLabel: String?
    let bestRoute: DecisionTripRoute?
    let defaultRoute: DecisionTripRoute?
    let alternatives: [DecisionTripRoute]?
    let disruptedLinesInArea: [String]?
}

struct DecisionTripRoute: Decodable, Hashable {
    let durationMinutes: Int
    let summary: String?
    let lines: [String]?
    let walkingMinutes: Int?
    let transferCount: Int?
    let disruptedLines: [String]?
}

struct DecisionClusterRef: Decodable {
    let clusterIndex: Int
    let ligne: String
    let arretId: String?
    let arretNom: String?
    let typeProbleme: String
    let reportCount: Int
    let confidence: String
    let ageMinutes: Int
    let latitude: Double?
    let longitude: Double?
}

struct DecisionRecommendation: Decodable {
    let type: String
    let action: String
    let reasoning: String?
    let walkToStop: DecisionWalkStop?
    let alternativeLines: [String]?
    let viaRoute: DecisionRoute?
}

struct DecisionWalkStop: Decodable {
    let name: String
    let stopId: String?
    let distanceMeters: Int
    let walkMinutes: Int
    let latitude: Double
    let longitude: Double
}

struct DecisionRoute: Decodable {
    let etaMinutes: Int?
    let summary: String?
}
