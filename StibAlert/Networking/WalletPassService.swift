import Foundation

enum WalletPassError: LocalizedError {
    case notConfigured
    case authMissing
    case downloadFailed(String)
    case invalidResponse

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "Apple Wallet n'est pas encore activé. Réessayez plus tard."
        case .authMissing:
            return "Connecte-toi pour ajouter ta carte à Wallet."
        case .downloadFailed(let detail):
            return "Téléchargement du pass impossible : \(detail)"
        case .invalidResponse:
            return "Réponse serveur invalide pour le pass Wallet."
        }
    }
}

/// Fetches a signed `.pkpass` binary from the backend and returns it as
/// `Data` so the caller can hand it to `PKAddPassesViewController`.
enum WalletPassService {
    struct PassRequest: Encodable {
        let holderName: String?
        let cardNumber: String?
        let subscriptionLabel: String?
        let expiryDate: Date?
    }

    static func fetchMobibPass(from pass: TransitPass) async throws -> Data {
        guard let token = KeychainHelper.readToken() else {
            throw WalletPassError.authMissing
        }

        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/wallet/mobib-pass") else {
            throw WalletPassError.invalidResponse
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/vnd.apple.pkpass", forHTTPHeaderField: "Accept")
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.timeoutInterval = 30

        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let body = PassRequest(
            holderName: nonEmpty(pass.holderName),
            cardNumber: nonEmpty(pass.cardNumber),
            subscriptionLabel: nonEmpty(pass.subscriptionLabel),
            expiryDate: pass.expiryDate
        )
        request.httpBody = try encoder.encode(body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw WalletPassError.invalidResponse
        }

        switch http.statusCode {
        case 200:
            return data
        case 503:
            throw WalletPassError.notConfigured
        case 401:
            throw WalletPassError.authMissing
        default:
            let message = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
            let detail = (message?["message"] as? String) ?? "HTTP \(http.statusCode)"
            throw WalletPassError.downloadFailed(detail)
        }
    }

    private static func nonEmpty(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
