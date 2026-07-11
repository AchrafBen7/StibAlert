import Foundation

struct TransportHomeDecisionData {
    let title: String
    let subtitle: String
    let severityLabel: String
    let confidenceLabel: String
    let nextDepartureSummary: String
}

struct TransportRecentIncidentItem: Identifiable {
    let id: String
    let line: String
    let title: String
    let time: String
    let details: String
}

enum TransportViewAdapters {
    static func homeDecisionData(from overview: TransportOverviewDTO) -> TransportHomeDecisionData {
        let severityLabel = localizedSeverityLabel(
            severity: overview.severity,
            fallback: overview.label?.localized
        )

        let departures = overview.nextDepartures.prefix(2).map {
            "\($0.line) \($0.minutes) min"
        }

        let departureSummary = departures.isEmpty
            ? AppLocalizer.string("home.no_reliable_departure", defaultValue: "Aucun prochain passage fiable pour le moment")
            : departures.joined(separator: " • ")

        let incidentSummary: String
        if let first = overview.activeIncidents.first {
            incidentSummary = first.localizedDescription ?? first.localizedType ?? AppLocalizer.string("home.disruptions_detected", defaultValue: "Perturbations détectées")
        } else {
            incidentSummary = AppLocalizer.string("home.network_ok", defaultValue: "Le réseau autour de toi semble exploitable.")
        }

        return TransportHomeDecisionData(
            title: AppLocalizer.string("home.can_i_leave", defaultValue: "Puis-je partir maintenant ?"),
            subtitle: incidentSummary,
            severityLabel: severityLabel,
            confidenceLabel: confidenceText(from: overview.confidence),
            nextDepartureSummary: departureSummary
        )
    }

    static func recentIncidents(from incidents: [TransportIncidentDTO]) -> [TransportRecentIncidentItem] {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .abbreviated  // .short donne « 1 m. » en FR ; .abbreviated donne « 1 min »

        return incidents.prefix(8).map { incident in
            TransportRecentIncidentItem(
                id: incident.id,
                line: incident.line ?? "?",
                title: incident.localizedType ?? localizedSeverityLabel(severity: incident.severity, fallback: nil),
                time: incident.date.map { formatter.localizedString(for: $0, relativeTo: .now) } ?? AppLocalizer.string("time.just_now", defaultValue: "à l’instant"),
                details: incident.localizedDescription ?? AppLocalizer.string("no_details", defaultValue: "Aucun détail disponible.")
            )
        }
    }

    static func routeNote(from recommendation: TransportRecommendationDTO) -> String? {
        if let fallback = recommendation.fallback {
            return fallback.message
        }

        guard let best = recommendation.recommendedAlternatives.first else {
            return nil
        }

        return best.explanation
    }

    static func reliabilityText(from recommendation: TransportRecommendationDTO) -> String {
        let percent = Int((recommendation.confidence * 100).rounded())
        return AppLocalizer.format("confidence.pct_reliable", defaultValue: "%lld%% fiable", percent)
    }

    static func confidenceText(from confidence: Double) -> String {
        RouteConfidence.percentLabel(confidence)
    }

    static func localizedSeverityLabel(severity: String?, fallback: String?) -> String {
        switch severity {
        case "critical":
            return AppLocalizer.string("Bloqué")
        case "major":
            return AppLocalizer.string("Perturbé")
        case "minor":
            return AppLocalizer.string("Sous surveillance")
        case "normal":
            return AppLocalizer.string("Normal")
        default:
            return fallback ?? AppLocalizer.string("Normal")
        }
    }

    private static func incidents(
        for alternative: TransportAlternativeDTO,
        from incidents: [TransportIncidentDTO]
    ) -> [TransportIncidentDTO] {
        incidents.filter { incident in
            guard let line = incident.line else { return false }
            return alternative.lines.contains(line)
        }
    }

    private static func sourceSummary(
        for alternative: TransportAlternativeDTO,
        recommendation: TransportRecommendationDTO,
        matchingIncidents: [TransportIncidentDTO]
    ) -> String {
        var sources: [String] = []

        if !recommendation.nextDepartures.isEmpty {
            // Était "waiting times STIB" : de l'anglais affiché dans une app FR/NL.
            sources.append(AppLocalizer.string("sources.waiting_times", defaultValue: "temps d'attente STIB"))
        }

        if matchingIncidents.contains(where: { $0.source?.localizedCaseInsensitiveContains("official") == true }) {
            sources.append(AppLocalizer.string("sources.official", defaultValue: "source officielle"))
        }

        if matchingIncidents.contains(where: { $0.community?.confirmations ?? 0 > 0 }) {
            sources.append(AppLocalizer.string("sources.field", defaultValue: "terrain"))
        }

        if sources.isEmpty {
            sources.append(AppLocalizer.string("sources.realtime_network", defaultValue: "réseau en temps réel"))
        }

        return AppLocalizer.format("sources.based_on", defaultValue: "Basé sur %@",
                                   sources.uniqued().joined(separator: " • "))
    }

    private static func lineSummary(for alternative: TransportAlternativeDTO) -> String {
        if !alternative.lines.isEmpty {
            return alternative.lines.joined(separator: " • ")
        }

        let modes = Set((alternative.steps ?? []).map { $0.mode.lowercased() })
        if modes.contains("bike") {   // "bike"/"walk" = valeurs backend, non traduites
            return AppLocalizer.string("trip.by_bike", defaultValue: "Trajet à vélo")
        }
        if modes.contains("walk") {
            return AppLocalizer.string("trip.on_foot", defaultValue: "Trajet à pied")
        }

        return "Alternative terrain"
    }

    private static func communitySummary(from incidents: [TransportIncidentDTO]) -> String? {
        let confirmations = incidents.reduce(0) { partialResult, incident in
            partialResult + (incident.community?.confirmations ?? 0)
        }
        let stillBlocked = incidents.reduce(0) { partialResult, incident in
            partialResult + (incident.community?.stillBlocked ?? 0)
        }
        let resolved = incidents.reduce(0) { partialResult, incident in
            partialResult + (incident.community?.resolved ?? 0)
        }

        if confirmations > 0 || stillBlocked > 0 {
            return AppLocalizer.format("community.recent_confirmations",
                                       defaultValue: "%lld confirmations terrain récentes",
                                       confirmations + stillBlocked)
        }

        if resolved > 0 {
            return AppLocalizer.format("community.improvement_reports",
                                       defaultValue: "%lld retours indiquent une amélioration", resolved)
        }

        return nil
    }

    private static func trustLabel(for confidence: Double) -> String {
        RouteConfidence.level(confidence).label
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        Array(Set(self)).sorted { String(describing: $0) < String(describing: $1) }
    }
}
