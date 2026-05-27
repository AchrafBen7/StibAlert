import Foundation

/// One-shot voice reply from `/api/stib-ai/voice`. `destination` (when set)
/// triggers the existing trip-building pipeline on the iOS side.
struct STIBAIVoiceReply: Decodable {
    let spokenReply: String
    let destination: String?
}

enum STIBAIVoiceClient {
    enum Error: Swift.Error, LocalizedError {
        case invalidURL
        case http(Int, String)
        case decode(String)
        var errorDescription: String? {
            switch self {
            case .invalidURL: return "URL assistant vocal invalide."
            case .http(_, let msg): return msg
            case .decode(let msg): return "Réponse invalide: \(msg)"
            }
        }
    }

    private struct Request: Encodable {
        let text: String
        let context: STIBAIContext?
    }

    private struct ErrorBody: Decodable { let message: String? }

    static func ask(text: String, context: STIBAIContext?) async throws -> STIBAIVoiceReply {
        guard AppConfig.isBackendEnabled,
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib-ai/voice") else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        req.timeoutInterval = 25
        req.httpBody = try JSONEncoder().encode(Request(text: text, context: context))

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(0, "Réponse invalide")
        }
        guard (200..<300).contains(http.statusCode) else {
            // The backend returns {"message": "..."} on errors. Surface that
            // text (e.g. "L'assistant est saturé…") instead of the raw HTTP
            // status, so the overlay shows something readable.
            let backendMessage = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
            throw Error.http(http.statusCode, backendMessage ?? "Service indisponible.")
        }
        do {
            return try JSONDecoder().decode(STIBAIVoiceReply.self, from: data)
        } catch {
            throw Error.decode(error.localizedDescription)
        }
    }
}
