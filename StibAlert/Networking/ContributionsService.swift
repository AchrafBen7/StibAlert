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
        // Les `case` sont des valeurs backend : on compare, on ne traduit pas.
        case "first_reporter": return AppLocalizer.string("role.first_reporter", defaultValue: "1er à signaler")
        case "confirmer": return AppLocalizer.string("role.confirmer", defaultValue: "Confirmation")
        case "resolver": return AppLocalizer.string("role.resolver", defaultValue: "Résolu")
        case "still_blocked_voter": return AppLocalizer.string("vote.still_blocked", defaultValue: "Toujours bloqué")
        default: return role
        }
    }

    /// Libellé + couleur du statut vivant pour le badge "Tes signalements".
    /// Libellés LOCALISÉS : ils étaient codés en dur en français et
    /// s'affichaient tels quels dans l'app néerlandaise (« Terminé » au milieu
    /// d'un écran NL, vu dans Profiel → Recente activiteit).
    var statusBadge: (label: String, systemColor: String)? {
        if liveStatus == "resolved" {
            return (AppLocalizer.string("status.resolved", defaultValue: "Résolu"), "ok")
        }
        if liveStatus == "archived" {
            return (AppLocalizer.string("status.archived", defaultValue: "Terminé"), "mute")
        }
        switch confidenceStatus {
        case "confirmed":
            let base = AppLocalizer.string("status.confirmed", defaultValue: "Confirmé")
            return (base + (reportCount.map { " (\($0))" } ?? ""), "primary")
        case "likely":
            return (AppLocalizer.string("status.likely", defaultValue: "Probable"), "warning")
        case "unverified":
            return (AppLocalizer.string("status.unverified", defaultValue: "À vérifier"), "mute")
        default:
            if liveStatus == "active" {
                return (AppLocalizer.string("status.active", defaultValue: "Actif"), "primary")
            }
            if liveStatus == "unpublished" {
                return (AppLocalizer.string("status.pending", defaultValue: "En attente"), "mute")
            }
            return nil
        }
    }
}
