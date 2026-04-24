import Foundation

enum AssistantService {
    static func context(lat: Double? = nil, lng: Double? = nil) async throws -> AssistantContextDTO {
        var path = "/api/assistant/context"
        var query: [String] = []
        if let lat { query.append("lat=\(lat)") }
        if let lng { query.append("lng=\(lng)") }
        if !query.isEmpty {
            path += "?" + query.joined(separator: "&")
        }
        return try await APIClient.shared.request(path, requiresAuth: true)
    }

    static func homeBrief(lat: Double? = nil, lng: Double? = nil) async throws -> AssistantBriefDTO {
        var path = "/api/assistant/home-brief"
        var query: [String] = []
        if let lat { query.append("lat=\(lat)") }
        if let lng { query.append("lng=\(lng)") }
        if !query.isEmpty {
            path += "?" + query.joined(separator: "&")
        }
        return try await APIClient.shared.request(path, requiresAuth: true)
    }

    static func routeBrief(
        depart: String,
        destination: String,
        lignesBloquees: [String] = []
    ) async throws -> AssistantBriefDTO {
        try await APIClient.shared.request(
            "/api/assistant/route-brief",
            method: .POST,
            body: AssistantRouteBriefRequest(
                depart: depart,
                destination: destination,
                lignesBloquees: lignesBloquees
            ),
            requiresAuth: true
        )
    }

    static func reportHelp(
        step: String,
        stopName: String? = nil,
        line: String? = nil,
        problemType: String? = nil,
        details: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) async throws -> AssistantBriefDTO {
        try await APIClient.shared.request(
            "/api/assistant/report-help",
            method: .POST,
            body: AssistantReportHelpRequest(
                step: step,
                stopName: stopName,
                line: line,
                problemType: problemType,
                details: details,
                lat: lat,
                lng: lng
            ),
            requiresAuth: true
        )
    }

    static func command(
        message: String? = nil,
        screen: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil,
        memory: AssistantCommandMemoryDTO? = nil
    ) async throws -> AssistantBriefDTO {
        try await APIClient.shared.request(
            "/api/assistant/command",
            method: .POST,
            body: AssistantCommandRequest(
                message: message,
                screen: screen,
                lat: lat,
                lng: lng,
                memory: memory
            ),
            requiresAuth: true
        )
    }

    static func commuteBrief(
        preferredStopId: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) async throws -> AssistantBriefDTO {
        try await APIClient.shared.request(
            "/api/assistant/commute-brief",
            method: .POST,
            body: AssistantCommuteBriefRequest(
                preferredStopId: preferredStopId,
                lat: lat,
                lng: lng
            ),
            requiresAuth: true
        )
    }

    static func commuteEmail(
        preferredStopId: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) async throws -> MessageResponse {
        try await APIClient.shared.request(
            "/api/assistant/commute-email",
            method: .POST,
            body: AssistantCommuteBriefRequest(
                preferredStopId: preferredStopId,
                lat: lat,
                lng: lng
            ),
            requiresAuth: true
        )
    }

    static func commutePush(
        preferredStopId: String? = nil,
        lat: Double? = nil,
        lng: Double? = nil
    ) async throws -> MessageResponse {
        try await APIClient.shared.request(
            "/api/assistant/commute-push",
            method: .POST,
            body: AssistantCommuteBriefRequest(
                preferredStopId: preferredStopId,
                lat: lat,
                lng: lng
            ),
            requiresAuth: true
        )
    }
}
