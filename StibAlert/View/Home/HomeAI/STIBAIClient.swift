import Foundation

enum STIBAIError: Error, LocalizedError {
    case invalidURL
    case invalidResponse
    case server(Int)
    case network(Error)

    var errorDescription: String? {
        // Messages localisés (avant : FR codé en dur → "Connexion interrompue…"
        // s'affichait en français dans une app en NL).
        switch self {
        case .invalidURL:
            return AppLocalizer.string("stibai.error.invalid_url", defaultValue: "URL assistant invalide.")
        case .invalidResponse:
            return AppLocalizer.string("stibai.error.invalid_response", defaultValue: "Réponse assistant invalide.")
        case .server(let status):
            return status == 429
                ? AppLocalizer.string("stibai.error.too_many", defaultValue: "Trop de demandes vers l'assistant. Réessaie dans un instant.")
                : AppLocalizer.string("stibai.error.unavailable", defaultValue: "Assistant temporairement indisponible.")
        case .network(let error):
            guard let urlError = error as? URLError else {
                return AppLocalizer.string("stibai.error.unstable", defaultValue: "Connexion instable. Réessaie dans quelques secondes.")
            }
            switch urlError.code {
            case .notConnectedToInternet:
                return AppLocalizer.string("stibai.error.no_internet", defaultValue: "Aucune connexion internet détectée.")
            case .timedOut:
                return AppLocalizer.string("stibai.error.timeout", defaultValue: "L'assistant met trop de temps à répondre. Réessaie.")
            case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed:
                return AppLocalizer.string("stibai.error.server_unreachable", defaultValue: "Serveur assistant momentanément inaccessible.")
            case .networkConnectionLost:
                return AppLocalizer.string("stibai.error.connection_lost", defaultValue: "Connexion interrompue pendant la réponse. Réessaie.")
            default:
                return AppLocalizer.string("stibai.error.unstable", defaultValue: "Connexion instable. Réessaie dans quelques secondes.")
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
        // Cold start Render (plan gratuit) : la 1ʳᵉ requête réveille le serveur
        // (~30-60 s) → timeout / 502-503-504. On laisse le temps + on retente.
        request.timeoutInterval = 60
        request.httpBody = try encoder.encode(STIBAIRequest(messages: messages, context: context))

        // Connexion avec retry SUR LE COLD START uniquement (avant le moindre
        // delta : on ne rejoue jamais un flux déjà commencé). C'est ce qui fait
        // que « le 1er message » passe enfin au lieu d'afficher "indisponible".
        var connectedBytes: URLSession.AsyncBytes?
        var attempt = 0
        while connectedBytes == nil {
            attempt += 1
            do {
                let (bytes, response) = try await session.bytes(for: request)
                guard let http = response as? HTTPURLResponse else { throw STIBAIError.invalidResponse }
                if (200..<300).contains(http.statusCode) {
                    connectedBytes = bytes
                } else if [502, 503, 504].contains(http.statusCode), attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_500_000_000)
                } else {
                    throw STIBAIError.server(http.statusCode)
                }
            } catch let error as STIBAIError {
                throw error
            } catch {
                if Self.isColdStartError(error), attempt < 3 {
                    try? await Task.sleep(nanoseconds: UInt64(attempt) * 2_500_000_000)
                } else {
                    throw STIBAIError.network(error)
                }
            }
        }
        let bytes = connectedBytes!

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

    /// Erreurs typiques d'un serveur Render endormi qui se réveille.
    private static func isColdStartError(_ error: Error) -> Bool {
        guard let urlError = error as? URLError else { return false }
        switch urlError.code {
        case .timedOut, .cannotConnectToHost, .cannotFindHost,
             .networkConnectionLost, .dnsLookupFailed:
            return true
        default:
            return false
        }
    }

    /// Réveille le backend Render dès l'ouverture du chat (fire-and-forget),
    /// pour que le serveur soit déjà chaud quand l'utilisateur envoie son
    /// 1er message — au lieu de le faire attendre le cold start.
    static func warmUp() {
        guard AppConfig.isBackendEnabled,
              let url = URL(string: AppConfig.backendBaseURL) else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.timeoutInterval = 10
        Task.detached { _ = try? await URLSession.shared.data(for: request) }
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
