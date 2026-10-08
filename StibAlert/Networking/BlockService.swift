import Foundation

/// Blocage d'un auteur.
///
/// Apple l'exige de toute app à contenu généré par les utilisateurs
/// (App Review Guideline 1.2, « the ability to block abusive users »). Mais
/// l'intérêt n'est pas la case à cocher : sans blocage, une personne harcelée
/// par une autre n'a aucun recours dans l'app, et sa seule issue est de
/// désinstaller.
///
/// À ne pas confondre avec `ClusterService.flagSignalement` :
///   • SIGNALER agit sur un CONTENU, pour tout le monde, via la modération.
///     L'auteur peut être anonyme.
///   • BLOQUER agit sur un AUTEUR, pour moi seul, tout de suite. Il exige un
///     compte des deux côtés : on ne bloque pas un anonyme.
///
/// Le filtrage est fait par le serveur, pas ici : les signalements des auteurs
/// bloqués ne sont plus renvoyés par `/api/signalements` dès lors que le jeton
/// accompagne la requête — ce que `APIClient` fait déjà partout.
enum BlockService {

    /// Les auteurs que j'ai bloqués. Alimente l'écran de déblocage.
    static func list() async throws -> BlockedUsersResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/me/blocks",
            requiresAuth: true
        )
    }

    /// Bloque un auteur. Idempotent côté serveur : rebloquer n'est pas une erreur.
    @discardableResult
    static func block(userId: String) async throws -> BlockActionResponse {
        struct Body: Encodable { let userId: String }
        return try await APIClient.shared.request(
            "/api/utilisateurs/me/blocks",
            method: .POST,
            body: Body(userId: userId),
            requiresAuth: true
        )
    }

    /// Débloque un auteur. Sans ce geste, le blocage serait un piège sans sortie.
    @discardableResult
    static func unblock(userId: String) async throws -> BlockActionResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/me/blocks/\(userId)",
            method: .DELETE,
            requiresAuth: true
        )
    }
}

struct BlockedUsersResponse: Decodable {
    let blocks: [BlockedUser]
}

struct BlockedUser: Decodable, Identifiable {
    let userId: String
    /// `nil` si le compte a été supprimé depuis le blocage.
    let nom: String?
    let createdAt: Date?

    var id: String { userId }
}

struct BlockActionResponse: Decodable {
    let message: String?
    let userId: String?
}
