import Foundation

enum InsightsService {
    static func mine(daysBack: Int = 30) async throws -> InsightsDTO {
        try await APIClient.shared.request(
            "/api/utilisateurs/me/insights?daysBack=\(daysBack)",
            requiresAuth: true
        )
    }
}

struct InsightsDTO: Decodable {
    let period: InsightsPeriod
    let hasFavorites: Bool?
    let accountAgeDays: Int?
    let estimatedMinutesSaved: Int
    let isMinutesSavedEstimate: Bool?
    let peopleHelped: Int
    let disruptionsAvoided: Int
    let contributionsCount: Int
    let topAffectedLine: InsightsTopLine?
    let narrative: InsightsNarrative
    let disclaimer: String?
}

struct InsightsPeriod: Decodable, Hashable {
    let daysBack: Int
    let since: Date?
    let until: Date?
}

struct InsightsTopLine: Decodable, Hashable {
    let line: String
    let disruptions: Int
}

struct InsightsNarrative: Decodable, Hashable {
    let headline: String
    let body: String
    let tone: String
}
