import SwiftUI

struct StibiPresentationData {
    let name: String
    let visualState: String
    let title: String
    let message: String
    let confidenceLabel: String
    let severityLabel: String
}

enum AssistantViewAdapters {
    static func presentationData(from brief: AssistantBriefDTO) -> StibiPresentationData {
        StibiPresentationData(
            name: brief.assistant.name,
            visualState: brief.assistant.visualState,
            title: brief.title,
            message: brief.message,
            confidenceLabel: "\(Int((brief.confidence * 100).rounded()))% de confiance",
            severityLabel: TransportViewAdapters.localizedSeverityLabel(
                severity: brief.severity,
                fallback: nil
            )
        )
    }

    static func routeNote(from brief: AssistantBriefDTO) -> String {
        guard
            let alternative = brief.supporting?.recommendedAlternatives?.first
        else {
            return brief.message
        }

        let communityReason = alternative.reasons?.first { reason in
            let lowered = reason.lowercased()
            return lowered.contains("confirm") || lowered.contains("terrain") || lowered.contains("signal")
        }

        if let communityReason, !brief.message.localizedCaseInsensitiveContains(communityReason) {
            return "\(brief.message) \(communityReason)"
        }

        if let highlight = alternative.explanationDetails?.highlights.first,
           !brief.message.localizedCaseInsensitiveContains(highlight) {
            return "\(brief.message) \(highlight)"
        }

        return brief.message
    }

    static func glowColor(for visualState: String) -> Color {
        switch visualState {
        case "alert":
            return Color(hex: "#FFB36C")
        case "guiding":
            return Color(hex: "#B5CFF8")
        case "speaking":
            return Color(hex: "#73F0D2")
        case "watching":
            return Color(hex: "#95A8FF")
        default:
            return Color(hex: "#7E90FF")
        }
    }

    static func screenInsight(for screen: String, context: AssistantContextDTO) -> AssistantBriefDTO {
        let favoriteCount = context.favorites.count
        let favoriteLines = context.favorites.lines
        let incidents = context.transport.activeIncidentsCount
        let primaryStop = context.habits.primaryStopName
        let profileName = context.profile?.name ?? "vous"

        switch screen {
        case "favorites":
            return localBrief(
                context: screen,
                type: favoriteCount > 0 ? "commute_brief" : "confidence_note",
                severity: context.transport.severity,
                confidence: context.transport.confidence,
                title: favoriteCount > 0 ? "Veille active sur tes favoris" : "Aucun repère favori pour l’instant",
                message: favoriteCount > 0
                    ? primaryStop != nil
                        ? "\(favoriteCount) arrêt(s) restent sous surveillance. \(primaryStop!) demeure ton point d’ancrage principal.\(favoriteLinesMessage(favoriteLines))"
                        : "\(favoriteCount) arrêt(s) sont suivis en continu. Je signalerai toute baisse nette de fiabilité.\(favoriteLinesMessage(favoriteLines))"
                    : "Ajoute quelques arrêts ou lignes repères. Le briefing deviendra plus utile et plus personnel.",
                actions: [
                    AssistantActionDTO(id: "check_favorites_health", label: "Lire l’état de mes favoris"),
                    AssistantActionDTO(id: "open_commute_brief", label: "Voir le brief trajet"),
                ],
                visualState: favoriteCount > 0 ? "watching" : "idle",
                assistantContext: context
            )

        case "signalements":
            return localBrief(
                context: screen,
                type: incidents > 0 ? "warning" : "status",
                severity: context.transport.severity,
                confidence: context.transport.confidence,
                title: incidents > 0 ? "Lecture en cours des lignes fragiles" : "Le réseau reste lisible",
                message: incidents > 0
                    ? "\(incidents) incident(s) actifs influencent encore les lignes affichées. Commence par les plus confirmés."
                    : "Je ne vois pas de concentration majeure de problèmes sur les lignes actuellement affichées.",
                actions: [
                    AssistantActionDTO(id: "explain_risk", label: "Lire le point de vigilance"),
                    AssistantActionDTO(id: "open_lines", label: "Ouvrir les lignes"),
                    AssistantActionDTO(id: "open_report", label: "Faire un signalement"),
                ],
                visualState: incidents > 0 ? "alert" : "watching",
                assistantContext: context
            )

        case "profile", "profile_main":
            return localBrief(
                context: screen,
                type: "status",
                severity: favoriteCount > 0 ? "normal" : "minor",
                confidence: max(0.78, context.transport.confidence),
                title: "Profil et habitudes pris en compte",
                message: context.profile?.notificationsEnabled == true
                    ? "Notifications actives pour \(profileName). Tes favoris, \(favoriteLinesLabel(favoriteLines)) et habitudes nourrissent déjà mes briefs."
                    : "Si tu actives les notifications, je pourrai prévenir \(profileName) avant qu’un trajet se dégrade vraiment.",
                actions: [
                    AssistantActionDTO(id: "open_commute_brief", label: "Voir le brief trajet"),
                    AssistantActionDTO(id: "open_profile", label: "Ouvrir le profil"),
                    AssistantActionDTO(id: "open_favorites", label: "Relire mes favoris"),
                ],
                visualState: "idle",
                assistantContext: context
            )

        default:
            return localBrief(
                context: screen,
                type: "status",
                severity: context.transport.severity,
                confidence: context.transport.confidence,
                title: "Contexte réseau maintenu à jour",
                message: "Je surveille tes favoris, \(favoriteLinesLabel(favoriteLines)) et l’état du réseau pour ajuster le briefing en temps réel.",
                actions: [],
                visualState: "watching",
                assistantContext: context
            )
        }
    }

    static func suggestedPrompts(for screen: String, context: AssistantContextDTO?) -> [String] {
        switch screen {
        case "favorites":
            return [
                "Quel est l’état de mes favoris ce matin ?",
                "Vois-tu un point faible sur mes arrêts ?",
                "Puis-je compter sur mes lignes habituelles ?",
            ]
        case "signalements":
            return [
                "Quelles lignes demandent le plus de prudence ?",
                "Que faut-il retenir de cette alerte ?",
                "Aide-moi à formuler un bon signalement",
            ]
        case "profile", "profile_main":
            return [
                "Que prends-tu en compte dans mon profil ?",
                "Pourquoi activer les notifications maintenant ?",
                "Qu’anticipes-tu à partir de mes habitudes ?",
            ]
        default:
            if let primaryStop = context?.habits.primaryStopName {
                return [
                    "Puis-je partir maintenant sans surprise ?",
                    "Quel est l’état de \(primaryStop) ?",
                    "Quelle alternative est la plus fiable ?",
                ]
            }
            return [
                "Puis-je partir maintenant sans surprise ?",
                "Quelle alternative te paraît la plus fiable ?",
                "Aide-moi à signaler un problème clairement",
            ]
        }
    }

    static func errorBrief(message: String) -> AssistantBriefDTO {
        localBrief(
            context: "assistant",
            type: "confidence_note",
            severity: "minor",
            confidence: 0.62,
            title: "Lecture prudente du réseau",
            message: message,
            actions: [],
            visualState: "speaking",
            assistantContext: nil
        )
    }

    static func confirmationBrief(title: String, message: String, context: AssistantContextDTO?) -> AssistantBriefDTO {
        localBrief(
            context: "assistant_confirmation",
            type: "status",
            severity: "normal",
            confidence: 0.92,
            title: title,
            message: message,
            actions: [],
            visualState: "speaking",
            assistantContext: context
        )
    }

    static func spokenText(for brief: AssistantBriefDTO) -> String {
        if let decision = brief.supporting?.commuteDecision, brief.type == "commute_brief" {
            if let alternative = brief.supporting?.recommendedAlternatives?.first {
                switch decision {
                case "detour":
                    return "Stibi conseille un détour. \(alternative.explanation)"
                case "leave_now":
                    return "Stibi recommande de partir maintenant. \(alternative.explanation)"
                case "prepare":
                    return "Stibi conseille de préparer le départ. \(alternative.explanation)"
                case "wait":
                    return "Stibi conseille d’attendre encore un peu. \(brief.message)"
                default:
                    break
                }
            }
            return brief.message
        }

        if brief.type == "guide", let alternative = brief.supporting?.recommendedAlternatives?.first {
            if let steps = alternative.steps, !steps.isEmpty {
                let sequence = steps.prefix(4).map(\.instruction).joined(separator: " Ensuite, ")
                return "Guidage actif. \(sequence)"
            }
            return "Guidage actif. \(alternative.explanation)"
        }

        return brief.message
    }

    static func overviewRiskBrief(from overview: TransportOverviewDTO, context: AssistantContextDTO?) -> AssistantBriefDTO {
        let message: String
        if let topIncident = overview.activeIncidents.first {
            let base = topIncident.description ?? "Je vois encore une zone fragile sur ton corridor."
            message = appendCommunityEvidence(base, incidents: overview.activeIncidents)
        } else if let nextDeparture = overview.nextDepartures.first {
            message = "Le réseau reste lisible. Prochain passage utile : ligne \(nextDeparture.line) dans \(nextDeparture.minutes) min."
        } else {
            message = "Je ne vois pas d’incident majeur pour l’instant, mais la veille réseau reste active."
        }

        return localBrief(
            context: "transport_overview",
            type: overview.severity == "major" || overview.severity == "critical" ? "warning" : "status",
            severity: overview.severity,
            confidence: overview.confidence,
            title: overview.severity == "major" || overview.severity == "critical" ? "Point de vigilance actuel" : "Le réseau reste exploitable",
            message: context.map { message + favoriteLinesMessage($0.favorites.lines) } ?? message,
            actions: [
                AssistantActionDTO(id: "request_alternative", label: "Chercher une option plus fiable"),
                AssistantActionDTO(id: "check_primary_stop", label: "Relire l’état de mon arrêt"),
            ],
            visualState: overview.severity == "major" || overview.severity == "critical" ? "alert" : "watching",
            assistantContext: context
        )
    }

    static func primaryStopBrief(from stop: TransportStopDTO, label: String?, context: AssistantContextDTO?) -> AssistantBriefDTO {
        let nextDeparture = stop.nextDepartures.first
        let name = label ?? stop.stop.name
        let message: String

        if stop.severity == "major" || stop.severity == "critical" {
            let base = stop.activeIncidents.first?.description
                ?? "\(name) reste fragile en ce moment. Je préfère te proposer une alternative."
            message = appendCommunityEvidence(base, incidents: stop.activeIncidents)
        } else if let nextDeparture {
            message = "\(name) reste exploitable. Prochain passage utile : ligne \(nextDeparture.line) dans \(nextDeparture.minutes) min."
        } else {
            message = "\(name) reste sous contrôle. Je n’ai pas de prochain passage fiable à afficher pour l’instant."
        }

        return localBrief(
            context: "transport_stop",
            type: stop.severity == "major" || stop.severity == "critical" ? "warning" : "status",
            severity: stop.severity,
            confidence: stop.confidence,
            title: "Lecture de \(name)",
            message: message,
            actions: [
                AssistantActionDTO(id: "request_alternative", label: "Chercher une option plus fiable"),
            ],
            visualState: stop.severity == "major" || stop.severity == "critical" ? "alert" : "guiding",
            assistantContext: context
        )
    }

    static func favoritesHealthBrief(from stops: [TransportStopDTO], context: AssistantContextDTO?) -> AssistantBriefDTO {
        let sortedStops = stops.sorted { severityRank($0.severity) > severityRank($1.severity) }
        let worst = sortedStops.first
        let fragileCount = sortedStops.filter { severityRank($0.severity) >= severityRank("major") }.count
        let severity = worst?.severity ?? "minor"
        let confidence = worst?.confidence ?? (context?.transport.confidence ?? 0.78)
        let title = fragileCount > 0 ? "Tes favoris demandent de la prudence" : "Tes favoris restent lisibles"
        let message: String

        if let worst, fragileCount > 0 {
            let base = "\(fragileCount) arrêt(s) favori(s) sont plus fragiles que d’habitude. Le point le plus risqué reste \(worst.stop.name)."
            message = appendCommunityEvidence(base, incidents: worst.activeIncidents)
        } else {
            message = "Je ne vois pas de rupture majeure sur tes favoris principaux pour le moment."
        }

        return localBrief(
            context: "favorites_health",
            type: fragileCount > 0 ? "warning" : "commute_brief",
            severity: severity,
            confidence: confidence,
            title: title,
            message: message,
            actions: [
                AssistantActionDTO(id: "check_primary_stop", label: "Relire l’état de mon arrêt"),
                AssistantActionDTO(id: "request_alternative", label: "Chercher une option plus fiable"),
            ],
            visualState: fragileCount > 0 ? "alert" : "watching",
            assistantContext: context
        )
    }

    static func routeOperationBrief(
        from recommendation: TransportRecommendationDTO,
        mode: String,
        context: AssistantContextDTO?
    ) -> AssistantBriefDTO {
        let best = recommendation.recommendedAlternatives.first
        let severity = recommendation.severity
        let confidence = recommendation.confidence
        let title: String
        let message: String
        let type: String

        if mode == "guide_me" {
            type = "guide"
            title = "Guidage en cours"
            if let best {
                let base = best.explanationDetails?.summary ?? best.explanation
                message = appendCommunityEvidence(base, incidents: routeIncidents(for: best, from: recommendation.activeIncidents))
            } else {
                message = recommendation.fallback?.message ?? "Je n’ai pas trouvé de guidage plus fiable pour le moment."
            }
        } else {
            type = best?.type == "most_reliable" || best?.type == "best_overall" ? "recommendation" : "comparison"
            title = "Option recommandée"
            if let best {
                let base = best.explanationDetails?.summary ?? best.explanation
                message = appendCommunityEvidence(base, incidents: routeIncidents(for: best, from: recommendation.activeIncidents))
            } else {
                message = recommendation.fallback?.message ?? "Je n’ai pas trouvé d’alternative plus fiable pour le moment."
            }
        }

        return localBrief(
            context: "transport_route",
            type: type,
            severity: severity,
            confidence: confidence,
            title: title,
            message: message,
            actions: [
                AssistantActionDTO(id: "view_route", label: "Lire l’itinéraire"),
                AssistantActionDTO(id: "compare_routes", label: "Comparer les options"),
            ],
            visualState: mode == "guide_me" ? "guiding" : (severity == "major" || severity == "critical" ? "alert" : "speaking"),
            assistantContext: context
        )
        .withRecommendedAlternatives(recommendation.recommendedAlternatives)
    }

    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case "critical": return 4
        case "major": return 3
        case "minor": return 2
        default: return 1
        }
    }

    private static func routeIncidents(
        for alternative: TransportAlternativeDTO,
        from incidents: [TransportIncidentDTO]
    ) -> [TransportIncidentDTO] {
        incidents.filter { incident in
            guard let line = incident.line else { return false }
            return alternative.lines.contains(line)
        }
    }

    private static func appendCommunityEvidence(_ base: String, incidents: [TransportIncidentDTO]) -> String {
        guard let evidence = communityEvidence(from: incidents) else { return base }
        guard !base.localizedCaseInsensitiveContains(evidence) else { return base }
        return "\(base) \(evidence)"
    }

    private static func communityEvidence(from incidents: [TransportIncidentDTO]) -> String? {
        let confirmations = incidents.reduce(0) { partialResult, incident in
            partialResult + (incident.community?.confirmations ?? 0)
        }
        let stillBlocked = incidents.reduce(0) { partialResult, incident in
            partialResult + (incident.community?.stillBlocked ?? 0)
        }
        let resolved = incidents.reduce(0) { partialResult, incident in
            partialResult + (incident.community?.resolved ?? 0)
        }

        if stillBlocked > 0 {
            return "\(confirmations + stillBlocked) retours terrain indiquent que le problème tient encore."
        }

        if confirmations > 0 {
            return "\(confirmations) confirmation(s) terrain soutiennent encore cette lecture."
        }

        if resolved > 0 {
            return "\(resolved) retour(s) récents suggèrent une amélioration."
        }

        return nil
    }

    private static func favoriteLinesMessage(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "" }
        return " Lignes favorites suivies : \(lines.prefix(3).joined(separator: ", "))."
    }

    private static func favoriteLinesLabel(_ lines: [String]) -> String {
        guard !lines.isEmpty else { return "tes lignes clés" }
        return "tes lignes \(lines.prefix(3).joined(separator: ", "))"
    }

    private static func localBrief(
        context: String,
        type: String,
        severity: String,
        confidence: Double,
        title: String,
        message: String,
        actions: [AssistantActionDTO],
        visualState: String,
        assistantContext: AssistantContextDTO?
    ) -> AssistantBriefDTO {
        AssistantBriefDTO(
            assistant: AssistantIdentityDTO(name: "Stibi", visualState: visualState),
            context: context,
            type: type,
            priority: severity == "critical" ? "high" : (severity == "major" ? "elevated" : "normal"),
            severity: severity,
            confidence: confidence,
            title: title,
            message: message,
            shortMessage: title,
            actions: actions,
            source: "assistant_context",
            assistantContext: assistantContext,
            supporting: AssistantSupportingDTO(
                realtimeStatus: assistantContext?.transport.realtimeStatus,
                nextDepartures: assistantContext?.transport.nextDepartures,
                activeIncidentsCount: assistantContext?.transport.activeIncidentsCount,
                perturbationSummary: assistantContext?.transport.perturbationSummary,
                recommendedAlternatives: nil,
                commuteDecision: nil,
                briefingStage: nil,
                minutesUntilDeparture: nil,
                departureTime: nil
            )
        )
    }
}

private extension AssistantBriefDTO {
    func withRecommendedAlternatives(_ alternatives: [TransportAlternativeDTO]) -> AssistantBriefDTO {
        AssistantBriefDTO(
            assistant: assistant,
            context: context,
            type: type,
            priority: priority,
            severity: severity,
            confidence: confidence,
            title: title,
            message: message,
            shortMessage: shortMessage,
            actions: actions,
            source: source,
            assistantContext: assistantContext,
            supporting: AssistantSupportingDTO(
                realtimeStatus: supporting?.realtimeStatus,
                nextDepartures: supporting?.nextDepartures,
                activeIncidentsCount: supporting?.activeIncidentsCount,
                perturbationSummary: supporting?.perturbationSummary,
                recommendedAlternatives: alternatives,
                commuteDecision: supporting?.commuteDecision,
                briefingStage: supporting?.briefingStage,
                minutesUntilDeparture: supporting?.minutesUntilDeparture,
                departureTime: supporting?.departureTime
            )
        )
    }
}
