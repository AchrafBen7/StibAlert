import AppIntents
import Foundation

// MARK: - Type de problème (AppEnum pour que Siri propose les choix)

enum TypeProblemeIntentEnum: String, AppEnum {
    case retard = "Retard"
    case accident = "Accident"
    case panne = "Panne"
    case proprete = "Propreté"
    case agression = "Agression"
    case incivilite = "Incivilité"
    case autre = "Autre"

    static var typeDisplayRepresentation: TypeDisplayRepresentation {
        TypeDisplayRepresentation(name: "Type de problème")
    }

    static var caseDisplayRepresentations: [TypeProblemeIntentEnum: DisplayRepresentation] {
        [
            .retard:     DisplayRepresentation(title: "Retard",      image: .init(systemName: "clock.badge.exclamationmark")),
            .accident:   DisplayRepresentation(title: "Accident",    image: .init(systemName: "exclamationmark.triangle")),
            .panne:      DisplayRepresentation(title: "Panne",       image: .init(systemName: "wrench.and.screwdriver")),
            .proprete:   DisplayRepresentation(title: "Propreté",    image: .init(systemName: "trash")),
            .agression:  DisplayRepresentation(title: "Agression",   image: .init(systemName: "person.fill.xmark")),
            .incivilite: DisplayRepresentation(title: "Incivilité",  image: .init(systemName: "exclamationmark.bubble")),
            .autre:      DisplayRepresentation(title: "Autre",       image: .init(systemName: "ellipsis.circle")),
        ]
    }
}

// MARK: - Signaler un arrêt via Siri (sans ouvrir l'app)

struct SignalerArretIntent: AppIntent {
    static let title: LocalizedStringResource = "Signaler un problème STIB"
    static let description = IntentDescription(
        "Créez un signalement directement via Siri. L'app n'a pas besoin d'être ouverte.",
        categoryName: "Transport"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Arrêt", description: "Nom de l'arrêt concerné, ex: Heembeek")
    var nomArret: String

    @Parameter(title: "Type de problème", default: .retard)
    var typeProbleme: TypeProblemeIntentEnum

    @Parameter(title: "Description", description: "Détails supplémentaires (optionnel)", default: "Signalé via Siri")
    var details: String

    static var parameterSummary: some ParameterSummary {
        Summary("Signaler \(\.$typeProbleme) à \(\.$nomArret)") {
            \.$details
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let token = KeychainHelper.readToken() else {
            return .result(dialog: IntentDialog(
                "Vous devez être connecté à StibAlert pour signaler. Ouvrez l'app et connectez-vous."
            ))
        }

        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/signalements/siri") else {
            return .result(dialog: "Erreur de configuration.")
        }

        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        req.httpBody = try JSONSerialization.data(withJSONObject: [
            "nomArret": nomArret,
            "typeProbleme": typeProbleme.rawValue,
            "description": details.isEmpty ? "Signalé via Siri" : details,
        ])

        do {
            let (data, response) = try await URLSession.shared.data(for: req)
            guard let http = response as? HTTPURLResponse else {
                return .result(dialog: "Impossible de contacter le serveur.")
            }

            struct SiriResponse: Decodable {
                let message: String?
                let ligne: String?
                let nomArret: String?
            }

            let body = (try? JSONDecoder().decode(SiriResponse.self, from: data))

            switch http.statusCode {
            case 201:
                let arret = body?.nomArret ?? nomArret
                let ligne = body?.ligne.map { ", ligne \($0)" } ?? ""
                return .result(dialog: IntentDialog(
                    "Signalement \(typeProbleme.rawValue.lowercased()) créé pour \(arret)\(ligne). Merci !"
                ))
            case 401:
                return .result(dialog: "Session expirée. Ouvrez StibAlert pour vous reconnecter.")
            case 404:
                return .result(dialog: "L'arrêt \(nomArret) est introuvable. Vérifiez l'orthographe.")
            default:
                return .result(dialog: body?.message ?? "Erreur lors de la création du signalement.")
            }
        } catch {
            return .result(dialog: "Problème de connexion. Vérifiez votre réseau.")
        }
    }
}

// MARK: - Prochain passage d'une ligne

struct NextPassageIntent: AppIntent {
    static let title: LocalizedStringResource = "Prochain passage STIB"
    static let description = IntentDescription(
        "Consulte l'heure du prochain passage d'une ligne STIB.",
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
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/transport/line/\(encoded)") else {
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

// MARK: - Ouvrir la carte live

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
            intent: SignalerArretIntent(),
            phrases: [
                "Signaler un problème \(.applicationName)",
                "Signaler un incident \(.applicationName)",
                "Il y a un problème \(.applicationName)",
                "Faire un signalement \(.applicationName)",
            ],
            shortTitle: "Signaler un problème",
            systemImageName: "exclamationmark.triangle.fill"
        )
        AppShortcut(
            intent: NextPassageIntent(),
            phrases: [
                "Prochain passage \(.applicationName)",
                "Mon tram arrive quand \(.applicationName)",
                "Quand arrive ma ligne \(.applicationName)",
            ],
            shortTitle: "Prochain passage",
            systemImageName: "tram.fill"
        )
        AppShortcut(
            intent: OpenLiveMapIntent(),
            phrases: [
                "Carte live \(.applicationName)",
                "Ouvrir la carte \(.applicationName)",
            ],
            shortTitle: "Carte live",
            systemImageName: "map.fill"
        )
    }
}
