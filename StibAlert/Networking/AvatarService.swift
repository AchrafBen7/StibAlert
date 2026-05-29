import Foundation
import UIKit

/// Upload + delete de l'avatar utilisateur. multipart/form-data avec champ
/// "avatar" attendu par le backend (avatarController.uploadMiddleware).
/// Retourne l'UtilisateurDTO mis à jour pour rafraîchir session.currentUser.
enum AvatarService {
    enum Error: Swift.Error, LocalizedError {
        case invalidImage
        case invalidURL
        case http(Int, String)
        case decode

        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Image invalide."
            case .invalidURL:   return "URL backend invalide."
            case .http(_, let m): return m
            case .decode:       return "Réponse serveur inattendue."
            }
        }
    }

    private struct UploadResponse: Decodable {
        let utilisateur: UtilisateurDTO
    }

    private struct ErrorBody: Decodable { let message: String? }

    /// Compresse `image` en JPEG 0.85 (~70-150 ko) et POST en multipart vers
    /// /api/utilisateurs/me/avatar. JWT auto-injecté par APIClient ailleurs ;
    /// ici on est en multipart natif donc on construit l'URLRequest à la main.
    static func upload(_ image: UIImage) async throws -> UtilisateurDTO {
        guard let jpeg = image.jpegData(compressionQuality: 0.85) else {
            throw Error.invalidImage
        }
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/utilisateurs/me/avatar") else {
            throw Error.invalidURL
        }

        let boundary = "Boundary-\(UUID().uuidString)"
        var req = URLRequest(url: url)
        req.httpMethod = "POST"
        req.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        if let token = KeychainHelper.readToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        req.timeoutInterval = 30

        var body = Data()
        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"avatar\"; filename=\"avatar.jpg\"\r\n")
        body.append("Content-Type: image/jpeg\r\n\r\n")
        body.append(jpeg)
        body.append("\r\n--\(boundary)--\r\n")
        req.httpBody = body

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else {
            throw Error.http(0, "Réponse invalide.")
        }
        guard (200..<300).contains(http.statusCode) else {
            let msg = (try? JSONDecoder().decode(ErrorBody.self, from: data))?.message
                ?? "Upload impossible (\(http.statusCode))."
            throw Error.http(http.statusCode, msg)
        }
        guard let parsed = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw Error.decode
        }
        return parsed.utilisateur
    }

    static func remove() async throws -> UtilisateurDTO {
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/utilisateurs/me/avatar") else {
            throw Error.invalidURL
        }
        var req = URLRequest(url: url)
        req.httpMethod = "DELETE"
        if let token = KeychainHelper.readToken() {
            req.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw Error.http((response as? HTTPURLResponse)?.statusCode ?? 0, "Suppression impossible.")
        }
        guard let parsed = try? JSONDecoder().decode(UploadResponse.self, from: data) else {
            throw Error.decode
        }
        return parsed.utilisateur
    }
}

private extension Data {
    mutating func append(_ s: String) {
        if let d = s.data(using: .utf8) { append(d) }
    }
}
