import Foundation
import CoreLocation

enum ClusterService {
    static func active(
        bbox: BoundingBox? = nil,
        ligne: String? = nil,
        limit: Int = 100
    ) async throws -> ClusterListResponse {
        var path = "/api/clusters/active?limit=\(limit)"
        if let bbox {
            path += "&bbox=\(bbox.minLat),\(bbox.minLng),\(bbox.maxLat),\(bbox.maxLng)"
        }
        if let ligne, !ligne.isEmpty {
            let encoded = ligne.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? ligne
            path += "&ligne=\(encoded)"
        }
        return try await APIClient.shared.request(path)
    }

    static func detail(_ clusterIndex: Int) async throws -> ClusterDetailDTO {
        try await APIClient.shared.request("/api/clusters/\(clusterIndex)")
    }

    static func confirmStillBlocked(_ clusterIndex: Int) async throws -> ClusterConfirmResponse {
        try await APIClient.shared.request(
            "/api/clusters/\(clusterIndex)/still-blocked",
            method: .POST
        )
    }

    static func confirmResolved(_ clusterIndex: Int) async throws -> ClusterConfirmResponse {
        try await APIClient.shared.request(
            "/api/clusters/\(clusterIndex)/resolve",
            method: .POST
        )
    }

    static func flagSignalement(
        _ signalementId: String,
        reason: FlagReason,
        note: String? = nil
    ) async throws -> FlagResponse {
        struct Body: Encodable {
            let reason: String
            let note: String?
        }
        return try await APIClient.shared.request(
            "/api/signalements/\(signalementId)/flag",
            method: .POST,
            body: Body(reason: reason.rawValue, note: note)
        )
    }
}

struct BoundingBox {
    let minLat: Double
    let minLng: Double
    let maxLat: Double
    let maxLng: Double

    init(minLat: Double, minLng: Double, maxLat: Double, maxLng: Double) {
        self.minLat = minLat
        self.minLng = minLng
        self.maxLat = maxLat
        self.maxLng = maxLng
    }

    init(center: CLLocationCoordinate2D, radiusMeters: Double) {
        let deltaLat = radiusMeters / 111_000.0
        let deltaLng = radiusMeters / (111_000.0 * cos(center.latitude * .pi / 180))
        self.minLat = center.latitude - deltaLat
        self.maxLat = center.latitude + deltaLat
        self.minLng = center.longitude - deltaLng
        self.maxLng = center.longitude + deltaLng
    }
}

enum FlagReason: String, Codable {
    case spam
    case offensive
    case duplicate
    case misinformation
}

enum ClusterConfidence: String, Codable {
    case low
    case medium
    case high

    var displayLabel: String {
        switch self {
        case .high: return "Élevée"
        case .medium: return "Moyenne"
        case .low: return "Basse"
        }
    }
}

struct ClusterListResponse: Decodable {
    let clusters: [ClusterDTO]
    let count: Int
    let fetchedAt: Date?
}

struct ClusterDTO: Decodable, Identifiable, Hashable {
    let clusterIndex: Int
    let ligne: String
    let arretId: String
    let typeProbleme: String
    let reportCount: Int
    let aggregateTrust: Double
    let confidence: ClusterConfidence
    let stillBlockedConfirmationCount: Int
    let resolveConfirmationCount: Int
    let resolved: Bool
    let status: String
    let firstReportedAt: Date?
    let lastReportedAt: Date?
    let expiresAt: Date?
    let isOfficial: Bool
    let position: ClusterPosition?

    var id: Int { clusterIndex }

    var latitude: Double? { position?.lat }
    var longitude: Double? { position?.lng }

    var minutesUntilExpiry: Int? {
        guard let expiresAt else { return nil }
        let seconds = expiresAt.timeIntervalSinceNow
        return seconds > 0 ? Int(seconds / 60) : 0
    }
}

struct ClusterPosition: Decodable, Hashable {
    let lat: Double
    let lng: Double
}

struct ClusterDetailDTO: Decodable {
    let clusterIndex: Int
    let ligne: String
    let arretId: String
    let typeProbleme: String
    let reportCount: Int
    let aggregateTrust: Double
    let confidence: ClusterConfidence
    let stillBlockedConfirmationCount: Int
    let resolveConfirmationCount: Int
    let resolved: Bool
    let status: String
    let firstReportedAt: Date?
    let lastReportedAt: Date?
    let expiresAt: Date?
    let isOfficial: Bool
    let position: ClusterPosition?
    let signalements: [ClusterReportDTO]
}

struct ClusterReportDTO: Decodable, Identifiable, Hashable {
    let description: String
    let trust: Double
    let timestamp: Date?
    let source: String

    var id: String { "\(timestamp?.timeIntervalSince1970 ?? 0)-\(description.hashValue)" }
}

struct ClusterConfirmResponse: Decodable {
    let clusterIndex: Int
    let confirmationCount: Int?
    let expiresAt: Date?
    let resolved: Bool?
    let message: String
}

struct FlagResponse: Decodable {
    let flagId: String?
    let queued: Bool?
    let message: String
}
