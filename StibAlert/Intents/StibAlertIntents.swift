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
                return .result(dialog: "Erreur lors de la création du signalement. Réessayez.")
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
        "Consulte l'heure du prochain passage d'une ligne STIB à un arrêt précis.",
        categoryName: "Transport"
    )
    static let openAppWhenRun = false

    @Parameter(title: "Numéro de ligne", default: "")
    var lineNumber: String

    @Parameter(title: "Arrêt", description: "Nom de l'arrêt, ex: Buissonets", default: "")
    var stopName: String

    static var parameterSummary: some ParameterSummary {
        Summary("Prochain passage ligne \(\.$lineNumber) à \(\.$stopName)")
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = normalizedLine(lineNumber)
        guard !line.isEmpty else {
            return .result(dialog: "Précisez un numéro de ligne, par exemple 92.")
        }

        let stopQuery = stopName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !stopQuery.isEmpty else {
            return .result(dialog: "Précisez aussi l'arrêt, par exemple Buissonets.")
        }

        do {
            let stops: [ArretDTO] = try await APIClient.shared.request("/api/arrets")
            guard let matchedStop = bestStopMatch(for: stopQuery, line: line, in: stops) else {
                return .result(dialog: "Je n'ai pas trouvé l'arrêt \(stopQuery). Essayez avec le nom exact de l'arrêt.")
            }

            let stopDetail = try await TransportService.stop(id: matchedStop.id)
            let departures = stopDetail.nextDepartures
                .filter { normalizedLine($0.line) == line }
                .sorted { $0.minutes < $1.minutes }

            guard let first = departures.first else {
                let servedLines = stopLines(from: matchedStop, stopDetail: stopDetail)
                if !servedLines.contains(line) {
                    let shownLines = servedLines.prefix(5).joined(separator: ", ")
                    let suffix = shownLines.isEmpty ? "" : " Lignes connues à cet arrêt: \(shownLines)."
                    return .result(dialog: "La ligne \(line) ne semble pas desservir \(matchedStop.nom).\(suffix)")
                }
                return .result(dialog: "Aucun passage fiable pour la ligne \(line) à \(matchedStop.nom) pour le moment.")
            }

            let dest = first.destination.map { " vers \($0)" } ?? ""
            let source = first.source == "scheduled" ? " selon l'horaire prévu" : ""
            if first.minutes == 0 {
                return .result(dialog: "Le \(line)\(dest) est à \(matchedStop.nom) maintenant\(source).")
            }
            return .result(dialog: "Le \(line)\(dest) arrive à \(matchedStop.nom) dans \(first.minutes) minute\(first.minutes > 1 ? "s" : "")\(source).")
        } catch {
            return .result(dialog: "Impossible de récupérer les passages STIB pour la ligne \(line) à \(stopQuery).")
        }
    }

    private func bestStopMatch(for query: String, line: String, in stops: [ArretDTO]) -> ArretDTO? {
        let normalizedQuery = normalizedStopName(query)
        guard !normalizedQuery.isEmpty else { return nil }

        let scored = stops.compactMap { stop -> (stop: ArretDTO, score: Int)? in
            let name = normalizedStopName(stop.nom)
            guard !name.isEmpty else { return nil }

            var score = 0
            if name == normalizedQuery {
                score += 100
            } else if name.hasPrefix(normalizedQuery) {
                score += 70
            } else if name.contains(normalizedQuery) || normalizedQuery.contains(name) {
                score += 45
            } else {
                return nil
            }

            let lines = (stop.lignesDesservies ?? []).map(normalizedLine)
            if lines.contains(line) {
                score += 35
            }

            return (stop, score)
        }

        return scored.sorted { lhs, rhs in
            if lhs.score == rhs.score {
                return lhs.stop.nom.count < rhs.stop.nom.count
            }
            return lhs.score > rhs.score
        }.first?.stop
    }

    private func stopLines(from stop: ArretDTO, stopDetail: TransportStopDTO) -> [String] {
        let lines = (stop.lignesDesservies ?? []) + stopDetail.stop.lines + stopDetail.nextDepartures.map(\.line)
        return Array(Set(lines.map(normalizedLine).filter { !$0.isEmpty })).sorted()
    }

    private func normalizedLine(_ value: String) -> String {
        value
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "LIGNE", with: "")
            .replacingOccurrences(of: "TRAM", with: "")
            .replacingOccurrences(of: "BUS", with: "")
            .replacingOccurrences(of: "METRO", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func normalizedStopName(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "fr_BE"))
            .lowercased()
            .replacingOccurrences(of: "-", with: " ")
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")
            .split(separator: " ")
            .joined(separator: " ")
    }
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
