import Foundation

enum AuthService {
    static func inscription(nom: String, email: String, motDePasse: String) async throws -> InscriptionResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/inscription",
            method: .POST,
            body: InscriptionRequest(nom: nom, email: email, motDePasse: motDePasse)
        )
    }

    static func activation(activationToken: String, code: String) async throws -> AuthResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/activation",
            method: .POST,
            body: ActivationRequest(activationToken: activationToken, activationCode: code)
        )
    }

    static func connexion(email: String, motDePasse: String) async throws -> AuthResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/connexion",
            method: .POST,
            body: ConnexionRequest(email: email, motDePasse: motDePasse)
        )
    }

    static func me() async throws -> UtilisateurDTO {
        try await APIClient.shared.request("/api/utilisateurs/me", requiresAuth: true)
    }

    static func renvoyerCode(activationToken: String) async throws -> InscriptionResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/renvoyer-code",
            method: .POST,
            body: RenvoyerCodeRequest(activationToken: activationToken)
        )
    }

    static func deconnexion() async throws {
        let _: MessageResponse = try await APIClient.shared.request(
            "/api/utilisateurs/deconnexion",
            method: .POST,
            requiresAuth: true
        )
    }

    static func refreshToken(_ refreshToken: String) async throws -> RefreshTokenResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/refresh",
            method: .POST,
            body: RefreshTokenRequest(refreshToken: refreshToken)
        )
    }

    static func supprimerCompte(userId: String) async throws {
        let _: MessageResponse = try await APIClient.shared.request(
            "/api/utilisateurs/\(userId)",
            method: .DELETE,
            requiresAuth: true
        )
    }
}

private struct RenvoyerCodeRequest: Encodable {
    let activationToken: String
}
