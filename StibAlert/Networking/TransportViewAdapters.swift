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
            fallback: overview.label?.fr
        )

        let departures = overview.nextDepartures.prefix(2).map {
            "\($0.line) \($0.minutes) min"
        }

        let departureSummary = departures.isEmpty
            ? "Aucun prochain passage fiable pour le moment"
            : departures.joined(separator: " • ")

        let incidentSummary: String
        if let first = overview.activeIncidents.first {
            incidentSummary = first.description ?? first.type ?? "Perturbations détectées"
        } else {
            incidentSummary = "Le réseau autour de vous semble exploitable."
        }

        return TransportHomeDecisionData(
            title: "Puis-je partir maintenant ?",
            subtitle: incidentSummary,
            severityLabel: severityLabel,
            confidenceLabel: confidenceText(from: overview.confidence),
            nextDepartureSummary: departureSummary
        )
    }

    static func recentIncidents(from incidents: [TransportIncidentDTO]) -> [TransportRecentIncidentItem] {
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short

        return incidents.prefix(8).map { incident in
            TransportRecentIncidentItem(
                id: incident.id,
                line: incident.line ?? "?",
                title: incident.type ?? localizedSeverityLabel(severity: incident.severity, fallback: nil),
                time: incident.date.map { formatter.localizedString(for: $0, relativeTo: .now) } ?? "À l'instant",
                details: incident.description ?? "Aucun détail disponible."
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

    static func routeAlternatives(from recommendation: TransportRecommendationDTO) -> [SearchRouteAlternative] {
        recommendation.recommendedAlternatives.prefix(4).map { alternative in
            let matchingIncidents = incidents(
                for: alternative,
                from: recommendation.activeIncidents
            )
            let confidenceText = "\(Int((alternative.confidence * 100).rounded()))% fiable"
            let trustLabel = trustLabel(for: alternative.confidence)
            let reason = alternative.explanationDetails?.summary ?? alternative.reasons?.first ?? alternative.explanation
            let categoryTitles = alternative.explanationDetails?.categories.map(\.title) ?? []
            let sourceSummary = sourceSummary(
                for: alternative,
                recommendation: recommendation,
                matchingIncidents: matchingIncidents
            )
            let communitySummary = communitySummary(from: matchingIncidents)
            return SearchRouteAlternative(
                title: alternative.label,
                eta: alternative.totalDurationMinutes,
                lineSummary: lineSummary(for: alternative),
                reason: reason,
                confidenceText: confidenceText,
                trustLabel: trustLabel,
                severityLabel: localizedSeverityLabel(severity: alternative.severity, fallback: nil),
                sourceSummary: sourceSummary,
                communitySummary: communitySummary,
                categoryTitles: Array(categoryTitles.prefix(2)),
                steps: alternative.steps ?? []
            )
        }
    }

    static func reliabilityText(from recommendation: TransportRecommendationDTO) -> String {
        let percent = Int((recommendation.confidence * 100).rounded())
        return "\(percent)% fiable"
    }

    static func confidenceText(from confidence: Double) -> String {
        let percent = Int((confidence * 100).rounded())
        switch confidence {
        case 0.9...:
            return "\(percent)% • très sûr"
        case 0.75...:
            return "\(percent)% • assez sûr"
        default:
            return "\(percent)% • faible confirmation"
        }
    }

    static func localizedSeverityLabel(severity: String?, fallback: String?) -> String {
        switch severity {
        case "critical":
            return String(localized: "Bloqué")
        case "major":
            return String(localized: "Perturbé")
        case "minor":
            return String(localized: "Sous surveillance")
        case "normal":
            return String(localized: "Normal")
        default:
            return fallback ?? String(localized: "Normal")
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
            sources.append("waiting times STIB")
        }

        if matchingIncidents.contains(where: { $0.source?.localizedCaseInsensitiveContains("official") == true }) {
            sources.append("source officielle")
        }

        if matchingIncidents.contains(where: { $0.community?.confirmations ?? 0 > 0 }) {
            sources.append("terrain")
        }

        if sources.isEmpty {
            sources.append("réseau en temps réel")
        }

        return "Basé sur " + sources.uniqued().joined(separator: " • ")
    }

    private static func lineSummary(for alternative: TransportAlternativeDTO) -> String {
        if !alternative.lines.isEmpty {
            return alternative.lines.joined(separator: " • ")
        }

        let modes = Set((alternative.steps ?? []).map { $0.mode.lowercased() })
        if modes.contains("bike") {
            return "Trajet à vélo"
        }
        if modes.contains("walk") {
            return "Trajet à pied"
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
            return "\(confirmations + stillBlocked) confirmation(s) terrain récentes"
        }

        if resolved > 0 {
            return "\(resolved) retour(s) indiquent une amélioration"
        }

        return nil
    }

    private static func trustLabel(for confidence: Double) -> String {
        switch confidence {
        case 0.9...:
            return "Très sûr"
        case 0.75...:
            return "Assez sûr"
        default:
            return "Faible confirmation"
        }
    }
}

private extension Array where Element: Hashable {
    func uniqued() -> [Element] {
        Array(Set(self)).sorted { String(describing: $0) < String(describing: $1) }
    }
}
