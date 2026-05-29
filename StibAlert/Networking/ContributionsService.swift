import Foundation

enum ContributionsService {
    static func mine() async throws -> ContributionsResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/me/contributions",
            requiresAuth: true
        )
    }
}

struct ContributionsResponse: Decodable {
    let summary: ContributionsSummary
    let recent: [ContributionItem]
}

struct ContributionsSummary: Decodable {
    let totalContributions: Int
    let publishedClusters: Int
    let peopleHelpedTotal: Int
    let firstReporterCount: Int
}

struct ContributionItem: Decodable, Identifiable {
    let ligne: String?
    let typeProbleme: String?
    let role: String
    let helpedPublishCluster: Bool
    let peopleHelped: Int?
    let createdAt: Date?
    let clusterIndex: Int?
    // #2 — Statut vivant du cluster lié (joint côté backend).
    let liveStatus: String?       // active | unpublished | resolved | archived
    let confidenceStatus: String? // confirmed | likely | unverified
    let reportCount: Int?

    var id: String {
        "\(clusterIndex ?? -1)-\(createdAt?.timeIntervalSince1970 ?? 0)"
    }

    var roleLabel: String {
        switch role {
        case "first_reporter": return "1er à signaler"
        case "confirmer": return "Confirmation"
        case "resolver": return "Résolu"
        case "still_blocked_voter": return "Toujours bloqué"
        default: return role
        }
    }

    /// Libellé + couleur du statut vivant pour le badge "Tes signalements".
    var statusBadge: (label: String, systemColor: String)? {
        if liveStatus == "resolved" { return ("Résolu", "ok") }
        if liveStatus == "archived" { return ("Terminé", "mute") }
        switch confidenceStatus {
        case "confirmed": return ("Confirmé\(reportCount.map { " (\($0))" } ?? "")", "primary")
        case "likely": return ("Probable", "warning")
        case "unverified": return ("À vérifier", "mute")
        default:
            if liveStatus == "active" { return ("Actif", "primary") }
            if liveStatus == "unpublished" { return ("En attente", "mute") }
            return nil
        }
    }
}
