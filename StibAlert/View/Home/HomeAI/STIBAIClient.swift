import Foundation

enum STIBAIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case server(Int)
    case network(Error)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "URL assistant invalide."
        case .invalidResponse:
            return "Réponse assistant invalide."
        case .server(let status):
            return status == 429
                ? "Trop de demandes vers l'assistant. Réessaie dans un instant."
                : "Assistant temporairement indisponible."
        case .network(let error):
            guard let urlError = error as? URLError else {
                return "Connexion instable. Réessaie dans quelques secondes."
            }
            switch urlError.code {
            case .notConnectedToInternet:
                return "Aucune connexion internet détectée."
            case .timedOut:
                return "L'assistant met trop de temps à répondre. Réessaie."
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return "Serveur assistant momentanément inaccessible."
            case .networkConnectionLost:
                return "Connexion interrompue pendant la réponse. Réessaie."
            default:
                return "Connexion instable. Réessaie dans quelques secondes."
            }
        }
    }
}

final class STIBAIClient {
    private let session: URLSession
    private let encoder = JSONEncoder()

    init(session: URLSession = .shared) {
        self.session = session
    }

    func stream(
        messages: [STIBAIMessage],
        context: STIBAIContext,
        onDelta: @escaping @MainActor (String) -> Void
    ) async throws {
        guard AppConfig.isBackendEnabled,
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib-ai") else {
            throw STIBAIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("text/event-stream", forHTTPHeaderField: "Accept")
        request.setValue("no-cache", forHTTPHeaderField: "Cache-Control")
        request.setValue(KeychainHelper.anonymousDeviceId(), forHTTPHeaderField: "x-stib-device-id")
        request.timeoutInterval = 45
        request.httpBody = try encoder.encode(STIBAIRequest(messages: messages, context: context))

        let bytes: URLSession.AsyncBytes
        let response: URLResponse
        do {
            (bytes, response) = try await session.bytes(for: request)
        } catch {
            throw STIBAIError.network(error)
        }

        guard let http = response as? HTTPURLResponse else { throw STIBAIError.invalidResponse }
        guard (200..<300).contains(http.statusCode) else { throw STIBAIError.server(http.statusCode) }

        var didReceiveDelta = false
        do {
            for try await rawLine in bytes.lines {
                let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : rawLine
                guard line.hasPrefix("data: ") else { continue }

                let payload = String(line.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines)
                if payload == "[DONE]" { return }
                guard let data = payload.data(using: .utf8),
                      let chunk = try? JSONDecoder().decode(STIBAISSEChunk.self, from: data),
                      let content = chunk.choices.first?.delta.content,
                      !content.isEmpty else { continue }

                didReceiveDelta = true
                await onDelta(content)
            }
        } catch {
            if didReceiveDelta, Self.isRecoverableStreamClose(error) {
                return
            }
            throw STIBAIError.network(error)
        }
    }

    private static func isRecoverableStreamClose(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        return urlError.code == .networkConnectionLost || urlError.code == .cancelled
    }
}

private struct STIBAISSEChunk: Decodable {
    struct Choice: Decodable {
        struct Delta: Decodable {
            let content: String?
        }

        let delta: Delta
    }

    let choices: [Choice]
}
