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
        // B7 — helper coldStartRetry partagé. Voir ColdStartRetry.swift.
        return try await coldStartRetry {
            try await APIClient.shared.request(path)
        }
    }

    /// `events` est aussi appelée tôt au launch (Reports tab) → mêmes
    /// conditions de cold start, donc même retry policy.
    static func eventsWithColdStartRetry(activeOnly: Bool = false, limit: Int = 60) async throws -> TransportEventsResponseDTO {
        try await coldStartRetry {
            try await events(activeOnly: activeOnly, limit: limit)
        }
    }

    static func stop(id: String) async throws -> TransportStopDTO {
        try await APIClient.shared.request("/api/transport/stop/\(id)")
    }

    static func line(id: String) async throws -> TransportLineDTO {
        try await APIClient.shared.request("/api/transport/line/\(id)")
    }

    /// Formatte en ISO-8601 (sans fraction de seconde — suffisant pour que
    /// `new Date(string)` côté backend parse correctement).
    private static let departureTimeFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    static func recommendRoute(
        depart: String,
        destination: String,
        lignesBloquees: [String] = [],
        preferredOperator: String? = nil,
        departureTime: Date? = nil,
        transitModes: [String]? = nil
    ) async throws -> TransportRecommendationDTO {
        let result: TransportRecommendationDTO = try await APIClient.shared.request(
            "/api/transport/route/recommend",
            method: .POST,
            body: TransportRecommendationRequest(
                depart: depart,
                destination: destination,
                lignesBloquees: lignesBloquees,
                preferredOperator: preferredOperator,
                departureTime: departureTime.map(departureTimeFormatter.string(from:)),
                transitModes: (transitModes?.isEmpty ?? true) ? nil : transitModes
            )
        )
        Analytics.track(.routeCalculated)
        return result
    }
}
