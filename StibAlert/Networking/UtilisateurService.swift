import Foundation

enum UtilisateurService {
    static func me() async throws -> UtilisateurDTO {
        try await APIClient.shared.request("/api/utilisateurs/me", requiresAuth: true)
    }

    static func mettreAJourProfil(
        userId: String,
        nom: String? = nil,
        langue: String? = nil,
        notifications: Bool? = nil,
        weeklyDigestEnabled: Bool? = nil,
        preTripPushEnabled: Bool? = nil,
        communityClusterPushEnabled: Bool? = nil,
        mercisPushEnabled: Bool? = nil,
        quietHoursEnabled: Bool? = nil,
        quietHoursStartHour: Int? = nil,
        quietHoursEndHour: Int? = nil,
        favoriteLines: [String]? = nil,
        operatorFavorites: [OperatorFavoriteDTO]? = nil,
        notificationFrequency: String? = nil,
        notificationRules: [NotificationRuleDTO]? = nil,
        routine: CommuteRoutineDTO? = nil
    ) async throws -> UtilisateurDTO {
        try await APIClient.shared.request(
            "/api/utilisateurs/\(userId)",
            method: .PATCH,
            body: ProfilUpdateRequest(
                nom: nom,
                langue: langue,
                notifications: notifications,
                weeklyDigestEnabled: weeklyDigestEnabled,
                preTripPushEnabled: preTripPushEnabled,
                communityClusterPushEnabled: communityClusterPushEnabled,
                mercisPushEnabled: mercisPushEnabled,
                quietHoursEnabled: quietHoursEnabled,
                quietHoursStartHour: quietHoursStartHour,
                quietHoursEndHour: quietHoursEndHour,
                favoriteLines: favoriteLines,
                operatorFavorites: operatorFavorites,
                notificationFrequency: notificationFrequency,
                notificationRules: notificationRules,
                routine: routine
            ),
            requiresAuth: true
        )
    }

    static func modifierLangue(userId: String, langue: String) async throws -> UtilisateurDTO {
        let response: UtilisateurLangueUpdateResponse = try await APIClient.shared.request(
            "/api/utilisateurs/\(userId)/langue",
            method: .PATCH,
            body: LangueUpdateRequest(langue: langue),
            requiresAuth: true
        )
        return response.utilisateur
    }

    static func toggleFavori(userId: String, arretId: String) async throws -> FavorisUpdateResponse {
        try await APIClient.shared.request(
            "/api/utilisateurs/\(userId)/favoris/\(arretId)",
            method: .PATCH,
            requiresAuth: true
        )
    }

    static func enregistrerTokenPush(_ token: String? = nil, oneSignalPlayerId: String? = nil) async throws {
        let _: MessageResponse = try await APIClient.shared.request(
            "/api/utilisateurs/enregistrer-token",
            method: .POST,
            body: PushTokenRequest(tokenPush: token, oneSignalPlayerId: oneSignalPlayerId),
            requiresAuth: true
        )
    }
}

private struct ProfilUpdateRequest: Encodable {
    let nom: String?
    let langue: String?
    let notifications: Bool?
    let weeklyDigestEnabled: Bool?
    let preTripPushEnabled: Bool?
    let communityClusterPushEnabled: Bool?
    let mercisPushEnabled: Bool?
    let quietHoursEnabled: Bool?
    let quietHoursStartHour: Int?
    let quietHoursEndHour: Int?
    let favoriteLines: [String]?
    let operatorFavorites: [OperatorFavoriteDTO]?
    let notificationFrequency: String?
    let notificationRules: [NotificationRuleDTO]?
    let routine: CommuteRoutineDTO?
}

private struct LangueUpdateRequest: Encodable {
    let langue: String
}

private struct PushTokenRequest: Encodable {
    let tokenPush: String?
    let oneSignalPlayerId: String?
}

private struct UtilisateurLangueUpdateResponse: Decodable {
    let message: String
    let utilisateur: UtilisateurDTO
}

struct FavorisUpdateResponse: Decodable {
    let message: String
    let favoris: [String]?
    let favorisDetails: [FavoriDetailDTO]?
}
