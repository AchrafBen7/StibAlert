import Foundation
import SwiftUI

struct StibiConversationEntry: Identifiable, Equatable {
    enum Role: Equatable {
        case user
        case assistant
    }

    let id = UUID()
    let role: Role
    let text: String
    let timestamp: Date
}

@MainActor
final class StibiCenter: ObservableObject {
    @Published private(set) var brief: AssistantBriefDTO?
    @Published private(set) var context: AssistantContextDTO?
    @Published private(set) var history: [StibiConversationEntry] = []
    @Published private(set) var currentScreen = "home"
    @Published private(set) var lastIntent: String?
    @Published private(set) var lastActionId: String?
    @Published var isExpanded = false
    @Published var isConversationPresented = false
    @Published var isSendingCommand = false

    private var lastProgressiveCommuteRefresh: Date?
    private var lastBriefingStage: String?
    private var lastCommuteDecision: String?

    func consume(
        _ brief: AssistantBriefDTO?,
        appendToHistory: Bool = false,
        inferredIntent: String? = nil,
        triggeredActionId: String? = nil
    ) {
        self.brief = brief
        if let assistantContext = brief?.assistantContext {
            context = assistantContext
        }
        if let inferredIntent {
            lastIntent = inferredIntent
        }
        if let triggeredActionId {
            lastActionId = triggeredActionId
        }
        if let brief {
            lastBriefingStage = brief.supporting?.briefingStage ?? lastBriefingStage
            lastCommuteDecision = brief.supporting?.commuteDecision ?? lastCommuteDecision
            Task {
                await StibiCommuteNotificationPlanner.sync(brief: brief, context: brief.assistantContext ?? context)
            }
        }
        if appendToHistory, let message = brief?.message {
            history.append(
                StibiConversationEntry(
                    role: .assistant,
                    text: message,
                    timestamp: Date()
                )
            )
        }
    }

    func setCurrentScreen(_ screen: String) {
        currentScreen = screen
    }

    func openConversation() {
        if history.isEmpty, let brief {
            history.append(
                StibiConversationEntry(
                    role: .assistant,
                    text: brief.message,
                    timestamp: Date()
                )
            )
        }
        isExpanded = true
        isConversationPresented = true
    }

    func closeConversation() {
        isConversationPresented = false
    }

    func dismiss() {
        isExpanded = false
        isConversationPresented = false
    }

    func toggleExpanded() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            isExpanded.toggle()
        }
    }

    func clear() {
        brief = nil
        isExpanded = false
        isConversationPresented = false
    }

    func pushContextInsight(for screen: String, context: AssistantContextDTO) {
        self.context = context
        currentScreen = screen
        consume(
            AssistantViewAdapters.screenInsight(for: screen, context: context),
            inferredIntent: "context_insight"
        )
    }

    func handleAction(id: String) -> String? {
        lastActionId = id
        switch id {
        case "ask_leave_now":
            return "Puis-je partir maintenant ?"
        case "explain_risk":
            return "Explique le risque actuel"
        case "request_alternative":
            return "Trouve-moi une alternative plus fiable"
        case "guide_me":
            return "Guide-moi étape par étape"
        case "check_primary_stop":
            return "Comment va mon arrêt principal ?"
        case "check_favorites_health":
            return "Que surveilles-tu sur mes favoris ?"
        case "confirm_report_details":
            return "Vérifie mon résumé avant envoi"
        default:
            return nil
        }
    }

    func commandMemory() -> AssistantCommandMemoryDTO {
        AssistantCommandMemoryDTO(
            recentMessages: Array(history.suffix(4)).map(\.text),
            lastIntent: lastIntent,
            lastActionId: lastActionId,
            lastAssistantTitle: brief?.title
        )
    }

    func sendCommand(_ text: String) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }

        history.append(
            StibiConversationEntry(
                role: .user,
                text: trimmed,
                timestamp: Date()
            )
        )

        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let reply = try await AssistantService.command(
                message: trimmed,
                screen: currentScreen,
                memory: commandMemory()
            )
            consume(reply, appendToHistory: true, inferredIntent: inferredIntent(from: trimmed))
        } catch {
            let fallback = AssistantViewAdapters.errorBrief(
                message: "Je ne peux pas traiter cette commande pour le moment. Garde un message court et réessaie."
            )
            consume(fallback, appendToHistory: true, inferredIntent: "error")
        }
    }

    func performTargetedAction(id: String) async -> Bool {
        guard AppConfig.isBackendEnabled else { return false }

        switch id {
        case "open_commute_brief":
            await loadCommuteBrief()
            return true

        case "explain_risk":
            return await refreshRiskOverview()

        case "check_primary_stop":
            return await inspectPrimaryStop()

        case "check_favorites_health":
            return await inspectFavoritesHealth()

        case "request_alternative", "guide_me":
            return await loadRoutineRecommendation(mode: id)

        case "email_commute_brief":
            return await emailCommuteBrief()

        case "push_commute_brief":
            return await pushCommuteBrief()

        default:
            return false
        }
    }

    func loadCommuteBrief() async {
        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let reply = try await AssistantService.commuteBrief(
                preferredStopId: context?.habits.home?.stopId ?? context?.habits.home?.id ?? context?.favorites.stops.first?.stopId ?? context?.favorites.stops.first?.id
            )
            lastProgressiveCommuteRefresh = Date()
            let shouldAppend = shouldAppendCommuteBrief(reply)
            consume(reply, appendToHistory: shouldAppend, inferredIntent: "commute_brief", triggeredActionId: "open_commute_brief")
        } catch {
            let fallback = AssistantViewAdapters.errorBrief(
                message: "Je n’arrive pas à lire ton trajet quotidien pour le moment."
            )
            consume(fallback, appendToHistory: true, inferredIntent: "commute_brief_error")
        }
    }

    func refreshProgressiveCommuteIfNeeded() async {
        guard !isSendingCommand else { return }
        guard let departureTime = context?.habits.departureTime else { return }
        guard shouldRefreshCommuteBrief(now: Date(), departureTime: departureTime) else { return }
        await loadCommuteBrief()
    }

    private func refreshRiskOverview() async -> Bool {
        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let overview = try await TransportService.overview()
            let brief = AssistantViewAdapters.overviewRiskBrief(from: overview, context: context)
            consume(brief, appendToHistory: true, inferredIntent: "risk_refresh", triggeredActionId: "explain_risk")
            return true
        } catch {
            return false
        }
    }

    private func inspectPrimaryStop() async -> Bool {
        guard let stopId = context?.habits.home?.id ?? context?.favorites.stops.first?.id else {
            return false
        }

        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let stop = try await TransportService.stop(id: stopId)
            let brief = AssistantViewAdapters.primaryStopBrief(
                from: stop,
                label: context?.habits.home?.label ?? context?.habits.primaryStopName,
                context: context
            )
            consume(brief, appendToHistory: true, inferredIntent: "primary_stop", triggeredActionId: "check_primary_stop")
            return true
        } catch {
            return false
        }
    }

    private func inspectFavoritesHealth() async -> Bool {
        let favoriteIds = Array((context?.favorites.stops ?? []).prefix(3).map(\.id))
        guard !favoriteIds.isEmpty else { return false }

        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            var stops: [TransportStopDTO] = []
            for stopId in favoriteIds {
                stops.append(try await TransportService.stop(id: stopId))
            }
            let brief = AssistantViewAdapters.favoritesHealthBrief(from: stops, context: context)
            consume(brief, appendToHistory: true, inferredIntent: "favorites_health", triggeredActionId: "check_favorites_health")
            return true
        } catch {
            return false
        }
    }

    private func loadRoutineRecommendation(mode: String) async -> Bool {
        let depart = context?.habits.home?.name ?? context?.habits.primaryStopName
        let destination = context?.habits.work?.name
        guard let depart, let destination else { return false }

        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let recommendation = try await TransportService.recommendRoute(
                depart: depart,
                destination: destination
            )
            let brief = AssistantViewAdapters.routeOperationBrief(
                from: recommendation,
                mode: mode,
                context: context
            )
            consume(brief, appendToHistory: true, inferredIntent: mode == "guide_me" ? "guide_route" : "route_alternative", triggeredActionId: mode)
            return true
        } catch {
            return false
        }
    }

    private func emailCommuteBrief() async -> Bool {
        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let response = try await AssistantService.commuteEmail(
                preferredStopId: context?.habits.home?.stopId ?? context?.habits.home?.id ?? context?.favorites.stops.first?.stopId ?? context?.favorites.stops.first?.id
            )
            let confirmation = AssistantViewAdapters.confirmationBrief(
                title: "Brief envoyé",
                message: response.message,
                context: context
            )
            consume(confirmation, appendToHistory: true, inferredIntent: "commute_email", triggeredActionId: "email_commute_brief")
            return true
        } catch {
            return false
        }
    }

    private func pushCommuteBrief() async -> Bool {
        isSendingCommand = true
        defer { isSendingCommand = false }

        do {
            let response = try await AssistantService.commutePush(
                preferredStopId: context?.habits.home?.stopId ?? context?.habits.home?.id ?? context?.favorites.stops.first?.stopId ?? context?.favorites.stops.first?.id
            )
            let confirmation = AssistantViewAdapters.confirmationBrief(
                title: "Push envoyé",
                message: response.message,
                context: context
            )
            consume(confirmation, appendToHistory: true, inferredIntent: "commute_push", triggeredActionId: "push_commute_brief")
            return true
        } catch {
            return false
        }
    }

    private func inferredIntent(from text: String) -> String {
        let normalized = text.lowercased()
        if normalized.contains("partir") { return "leave_now" }
        if normalized.contains("favori") { return "favorites_health" }
        if normalized.contains("signal") || normalized.contains("report") { return "report_help" }
        if normalized.contains("trajet") || normalized.contains("alternative") || normalized.contains("route") { return "route_help" }
        if normalized.contains("profil") || normalized.contains("notification") { return "profile_help" }
        return "general_help"
    }

    private func shouldRefreshCommuteBrief(now: Date, departureTime: String) -> Bool {
        guard let targetMinutes = parseClock(departureTime) else { return false }
        let currentMinutes = Calendar.current.component(.hour, from: now) * 60 + Calendar.current.component(.minute, from: now)
        let delta = targetMinutes - currentMinutes

        guard delta <= 60 && delta >= -20 else { return false }

        if let lastProgressiveCommuteRefresh {
            return now.timeIntervalSince(lastProgressiveCommuteRefresh) >= 300
        }
        return true
    }

    private func parseClock(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2, let hours = Int(parts[0]), let minutes = Int(parts[1]) else {
            return nil
        }
        return hours * 60 + minutes
    }

    private func shouldAppendCommuteBrief(_ brief: AssistantBriefDTO) -> Bool {
        guard brief.type == "commute_brief" else { return true }
        let nextStage = brief.supporting?.briefingStage
        let nextDecision = brief.supporting?.commuteDecision
        if history.isEmpty { return true }
        return nextStage != lastBriefingStage || nextDecision != lastCommuteDecision
    }
}
