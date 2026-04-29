import Foundation

enum TransportService {
    static func events(
        line: String? = nil,
        query: String? = nil,
        activeOnly: Bool = false,
        limit: Int = 60
    ) async throws -> TransportEventsResponseDTO {
        var items: [String] = ["activeOnly=\(activeOnly ? "true" : "false")", "limit=\(limit)"]
        if let line, !line.isEmpty {
            items.append("line=\(line.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? line)")
        }
        if let query, !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            let safe = query.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? query
            items.append("q=\(safe)")
        }
        return try await APIClient.shared.request("/api/transport/events?\(items.joined(separator: "&"))")
    }

    static func overview(lat: Double? = nil, lng: Double? = nil) async throws -> TransportOverviewDTO {
        var path = "/api/transport/overview"
        var query: [String] = []
        if let lat { query.append("lat=\(lat)") }
        if let lng { query.append("lng=\(lng)") }
        if !query.isEmpty {
            path += "?" + query.joined(separator: "&")
        }
        return try await APIClient.shared.request(path)
    }

    static func stop(id: String) async throws -> TransportStopDTO {
        try await APIClient.shared.request("/api/transport/stop/\(id)")
    }

    static func line(id: String) async throws -> TransportLineDTO {
        try await APIClient.shared.request("/api/transport/line/\(id)")
    }

    static func recommendRoute(
        depart: String,
        destination: String,
        lignesBloquees: [String] = []
    ) async throws -> TransportRecommendationDTO {
        try await APIClient.shared.request(
            "/api/transport/route/recommend",
            method: .POST,
            body: TransportRecommendationRequest(
                depart: depart,
                destination: destination,
                lignesBloquees: lignesBloquees
            )
        )
    }
}
