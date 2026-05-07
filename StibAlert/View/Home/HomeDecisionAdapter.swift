import Foundation

struct HomeDashboardData {
    let decision: TransportHomeDecisionData?
    let recommendedAlternative: HomeRecommendedAlternativeItem?
    let recommendedAlternativeDetail: TransportAlternativeDTO?
    let monitoredLines: [HomeMonitoredLineItem]
    let nearbyAlerts: [HomeNearbyAlertItem]
    let favoriteLines: [HomeFavoriteLineItem]
}

struct HomeMonitoredLineItem: Identifiable {
    let id: String
    let line: String
    let statusText: String
    let departureText: String
}

struct HomeNearbyAlertItem: Identifiable {
    let id: String
    let line: String
    let title: String
    let detail: String
    let confirmationText: String
}

struct HomeRecommendedAlternativeItem: Identifiable {
    let id: String
    let title: String
    let etaText: String
    let reliabilityText: String
    let reason: String
}

struct HomeFavoriteLineItem: Identifiable {
    let id: String
    let line: String
    let statusText: String
}

enum HomeDecisionAdapter {
    static func makeDashboardData(
        transportOverview: TransportOverviewDTO?,
        remoteSignalements: [SignalementDTO]
    ) -> HomeDashboardData {
        let monitoredLines = monitoredLines(from: transportOverview)
        let nearbyAlerts = nearbyAlerts(from: remoteSignalements)
        let recommendedAlternative = recommendedAlternative(from: transportOverview)

        return HomeDashboardData(
            decision: transportOverview.map(TransportViewAdapters.homeDecisionData(from:)),
            recommendedAlternative: recommendedAlternative,
            recommendedAlternativeDetail: transportOverview?.recommendedAlternatives.first,
            monitoredLines: monitoredLines,
            nearbyAlerts: nearbyAlerts,
            favoriteLines: favoriteLines(from: transportOverview)
        )
    }

    private static func monitoredLines(
        from overview: TransportOverviewDTO?
    ) -> [HomeMonitoredLineItem] {
        guard let overview else { return [] }

        let departureMap = Dictionary(grouping: overview.nextDepartures, by: \.line)
        let incidentMap = Dictionary(grouping: overview.activeIncidents, by: { $0.line ?? "" })
        let candidateLines = Array(NSOrderedSet(array: overview.nextDepartures.map(\.line))) as? [String] ?? []

        return candidateLines.prefix(4).map { line in
            let nextDeparture = departureMap[line]?.min(by: { $0.minutes < $1.minutes })
            let incidents = incidentMap[line] ?? []
            let statusText = incidents.first?.severity.flatMap {
                TransportViewAdapters.localizedSeverityLabel(severity: $0, fallback: nil)
            } ?? "Fiable"

            return HomeMonitoredLineItem(
                id: line,
                line: line,
                statusText: statusText,
                departureText: nextDeparture.map { "Prochain passage dans \($0.minutes) min" } ?? "Aucun passage fiable"
            )
        }
    }

    private static func nearbyAlerts(from signalements: [SignalementDTO]) -> [HomeNearbyAlertItem] {
        signalements
            .sorted { lhs, rhs in
                let left = lhs.community?.confirmations ?? 0
                let right = rhs.community?.confirmations ?? 0
                if left == right {
                    return (lhs.dateSignalement ?? .distantPast) > (rhs.dateSignalement ?? .distantPast)
                }
                return left > right
            }
            .prefix(3)
            .map { signalement in
                HomeNearbyAlertItem(
                    id: signalement.id,
                    line: signalement.ligne,
                    title: signalement.displayTypeProbleme,
                    detail: signalement.description,
                    confirmationText: {
                        let count = signalement.community?.confirmations ?? 0
                        return count > 0 ? "\(count) confirmations" : "À surveiller"
                    }()
                )
            }
    }

    private static func recommendedAlternative(from overview: TransportOverviewDTO?) -> HomeRecommendedAlternativeItem? {
        guard let best = overview?.recommendedAlternatives.first else { return nil }
        return HomeRecommendedAlternativeItem(
            id: best.id,
            title: best.label,
            etaText: "\(best.totalDurationMinutes) min",
            reliabilityText: TransportViewAdapters.confidenceText(from: best.confidence),
            reason: best.explanationDetails?.summary ?? best.explanation
        )
    }

    private static func favoriteLines(
        from overview: TransportOverviewDTO?
    ) -> [HomeFavoriteLineItem] {
        return []
    }
}
