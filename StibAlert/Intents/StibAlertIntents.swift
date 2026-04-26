import AppIntents
import Foundation

// MARK: - "Mon tram arrive quand" intent

struct NextPassageIntent: AppIntent {
    static let title: LocalizedStringResource = "Prochain passage STIB"
    static let description = IntentDescription(
        "Consulte l'heure du prochain passage de votre ligne favorite.",
        categoryName: "Transport"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Numéro de ligne", default: "")
    var lineNumber: String

    static var parameterSummary: some ParameterSummary {
        Summary("Prochain passage ligne \(\.$lineNumber)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = lineNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty else {
            return .result(dialog: "Précisez un numéro de ligne, par exemple 92.")
        }

        guard let encoded = line.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "https://stib-alert-backend.onrender.com/api/stib/\(encoded)") else {
            return .result(dialog: "Ligne \(line) introuvable.")
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(NextPassageResponse.self, from: data)
            if let first = response.nextDepartures?.first {
                let dest = first.destination.map { " vers \($0)" } ?? ""
                let mins = first.minutes
                if mins == 0 {
                    return .result(dialog: "Le \(line)\(dest) est à l'arrêt maintenant.")
                }
                return .result(dialog: "Le \(line)\(dest) arrive dans \(mins) minute\(mins > 1 ? "s" : "").")
            }
            return .result(dialog: "Aucun passage imminent pour la ligne \(line).")
        } catch {
            return .result(dialog: "Impossible de récupérer les données STIB pour la ligne \(line).")
        }
    }
}

private struct NextPassageResponse: Decodable {
    let nextDepartures: [NextDeparture]?
}

private struct NextDeparture: Decodable {
    let line: String
    let destination: String?
    let minutes: Int
}

// MARK: - "Signaler un problème" shortcut intent

struct ReportProblemIntent: AppIntent {
    static let title: LocalizedStringResource = "Signaler un problème STIB"
    static let description = IntentDescription(
        "Ouvre StibAlert sur l'écran de signalement.",
        categoryName: "Transport"
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - "Voir la carte live" shortcut intent

struct OpenLiveMapIntent: AppIntent {
    static let title: LocalizedStringResource = "Voir la carte live STIB"
    static let description = IntentDescription(
        "Ouvre la carte en temps réel de StibAlert.",
        categoryName: "Transport"
    )
    static let openAppWhenRun = true

    func perform() async throws -> some IntentResult {
        return .result()
    }
}

// MARK: - Shortcut Provider

struct StibAlertShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: NextPassageIntent(),
            phrases: [
                "Mon tram arrive quand avec \(.applicationName)",
                "Prochain passage \(.applicationName)",
                "Quand arrive ma ligne avec \(.applicationName)"
            ],
            shortTitle: "Prochain passage",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: ReportProblemIntent(),
            phrases: [
                "Signaler un problème \(.applicationName)",
                "Faire un signalement \(.applicationName)"
            ],
            shortTitle: "Signaler",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: OpenLiveMapIntent(),
            phrases: [
                "Carte live \(.applicationName)",
                "Ouvrir la carte \(.applicationName)"
            ],
            shortTitle: "Carte live",
            systemImageName: "map.fill"
        )
    }
}
