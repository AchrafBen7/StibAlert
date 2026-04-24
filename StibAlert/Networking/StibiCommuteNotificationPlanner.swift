import Foundation
import UserNotifications

enum StibiCommuteNotificationPlanner {
    private static let identifiers = [
        "stibi-commute-20",
        "stibi-commute-10",
        "stibi-commute-now",
    ]

    static func sync(
        brief: AssistantBriefDTO?,
        context: AssistantContextDTO?
    ) async {
        guard let context, context.habits.hasFavorites else {
            await clear()
            return
        }

        guard let departureTime = context.habits.departureTime,
              let target = parseClock(departureTime) else {
            await clear()
            return
        }

        let center = UNUserNotificationCenter.current()
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .authorized || settings.authorizationStatus == .provisional else {
            return
        }

        center.removePendingNotificationRequests(withIdentifiers: identifiers)

        let checkpoints: [(String, Int, String)] = [
            ("stibi-commute-20", 20, "Prépare ton départ"),
            ("stibi-commute-10", 10, "Briefing commute"),
            ("stibi-commute-now", 0, "Décision de départ"),
        ]

        for (identifier, offset, fallbackTitle) in checkpoints {
            let minutes = target - offset
            guard minutes >= 0 else { continue }

            let content = UNMutableNotificationContent()
            content.title = title(for: brief, fallback: fallbackTitle, offset: offset)
            content.body = body(for: brief, context: context, offset: offset)
            content.sound = .default

            var components = DateComponents()
            components.hour = minutes / 60
            components.minute = minutes % 60

            let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: true)
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try? await center.add(request)
        }
    }

    static func clear() async {
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: identifiers)
    }

    private static func title(for brief: AssistantBriefDTO?, fallback: String, offset: Int) -> String {
        guard let brief else { return fallback }
        if offset == 0 { return brief.title }
        if let decision = brief.supporting?.commuteDecision {
            switch decision {
            case "detour": return "Détour conseillé"
            case "leave_now": return "Pars bientôt"
            case "prepare": return "Prépare ton départ"
            case "wait": return "Attends encore"
            default: return fallback
            }
        }
        return fallback
    }

    private static func body(for brief: AssistantBriefDTO?, context: AssistantContextDTO, offset: Int) -> String {
        if let brief {
            if offset == 20 {
                return "Stibi surveille \(context.habits.home?.label ?? "ton trajet") pour toi. Ouvre l’app pour le brief du matin."
            }
            return brief.message
        }

        if offset == 0 {
            return "Stibi est prêt à te dire s’il faut partir, attendre ou prendre un détour."
        }

        return "Ton trajet quotidien approche. J’actualiserai le corridor avant le départ."
    }

    private static func parseClock(_ value: String) -> Int? {
        let parts = value.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              (0...23).contains(hours),
              (0...59).contains(minutes) else {
            return nil
        }
        return hours * 60 + minutes
    }
}
