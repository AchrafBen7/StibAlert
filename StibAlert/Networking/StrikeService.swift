import Foundation

/// État « mode grève » servi par le backend (`GET /api/strike`). Quand une
/// grève est active, l'app l'affiche (bandeau Home + section Verkeersinfo) et
/// le calcul d'itinéraire évite déjà les lignes concernées côté serveur.
struct StrikeState: Decodable, Equatable {
    let active: Bool
    let operators: [String]
    let affectedLines: [String]
    let message: String
    let messageNl: String

    static let inactive = StrikeState(
        active: false, operators: [], affectedLines: [], message: "", messageNl: ""
    )

    init(active: Bool, operators: [String], affectedLines: [String], message: String, messageNl: String) {
        self.active = active
        self.operators = operators
        self.affectedLines = affectedLines
        self.message = message
        self.messageNl = messageNl
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        active = (try? c.decode(Bool.self, forKey: .active)) ?? false
        operators = (try? c.decode([String].self, forKey: .operators)) ?? []
        affectedLines = (try? c.decode([String].self, forKey: .affectedLines)) ?? []
        message = (try? c.decode(String.self, forKey: .message)) ?? ""
        messageNl = (try? c.decode(String.self, forKey: .messageNl)) ?? ""
    }

    private enum CodingKeys: String, CodingKey {
        case active, operators, affectedLines, message, messageNl
    }

    /// Message adapté à la langue de l'app (NL si dispo, sinon FR).
    var localizedMessage: String {
        let nl = messageNl.trimmingCharacters(in: .whitespacesAndNewlines)
        if AppLocale.languageCode == "nl", !nl.isEmpty { return nl }
        return message
    }
}

enum StrikeService {
    /// Lit l'état de grève courant. Renvoie `.inactive` sur toute erreur — la
    /// grève n'est jamais une source de crash, juste une info superposée.
    static func current() async -> StrikeState {
        guard AppConfig.isBackendEnabled,
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/strike") else {
            return .inactive
        }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(StrikeState.self, from: data)
        } catch {
            return .inactive
        }
    }
}
