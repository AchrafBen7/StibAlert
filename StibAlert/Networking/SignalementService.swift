import Foundation
import UIKit

enum SignalementService {
    static func liste() async throws -> [SignalementDTO] {
        let response: SignalementsListResponse = try await APIClient.shared.request("/api/signalements")
        return response.signalements
    }

    static func liste(page: Int, limit: Int = 25, source: String? = nil) async throws -> SignalementsListResponse {
        var path = "/api/signalements?page=\(page)&limit=\(limit)"
        if let source, !source.isEmpty {
            path += "&source=\(source.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? source)"
        }
        return try await APIClient.shared.request(path)
    }

    static func arretsParLigne(_ ligne: String) async throws -> [ArretDTO] {
        try await APIClient.shared.request("/api/signalements/ligne/\(ligne.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ligne)")
    }

    static func parLigneEtArret(ligne: String, arretId: String, page: Int = 1, limit: Int = 20) async throws -> SignalementsListResponse {
        try await APIClient.shared.request(
            "/api/signalements/ligne/\(ligne.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? ligne)/arret/\(arretId)?page=\(page)&limit=\(limit)"
        )
    }

    static func parArret(arretId: String) async throws -> SignalementsParArretResponse {
        try await APIClient.shared.request("/api/signalements/arret/\(arretId)")
    }

    static func ajouter(
        nomArret: String,
        ligne: String,
        typeProbleme: String,
        description: String,
        latitude: Double?,
        longitude: Double?,
        transportOperator: String? = nil,
        photo: UIImage?
    ) async throws -> AjoutSignalementResponse {
        var fields: [String: String] = [
            "nomArret": nomArret,
            "ligne": ligne,
            "typeProbleme": typeProbleme,
            "description": description
        ]
        if let latitude { fields["latitude"] = String(latitude) }
        if let longitude { fields["longitude"] = String(longitude) }
        if let transportOperator, !transportOperator.isEmpty {
            fields["transportOperator"] = transportOperator
        }

        let imageData = photo?.jpegData(compressionQuality: 0.8)
        return try await APIClient.shared.upload(
            "/api/signalements/",
            fields: fields,
            imageData: imageData
        )
    }

    static func voter(signalementId: String, vote: String) async throws -> SignalementVoteResponse {
        try await APIClient.shared.request(
            "/api/signalements/\(signalementId)/vote",
            method: .POST,
            body: VoteRequest(vote: vote),
            requiresAuth: true
        )
    }

    static func signalerFaux(signalementId: String) async throws {
        // #4 — requiresAuth attache le JWT s'il existe (route backend en
        // protect.optional) → flag identifié + pondéré pour les comptes
        // connectés, anonyme accepté pour les invités.
        let _: MessageResponse = try await APIClient.shared.request(
            "/api/signalements/\(signalementId)/signalement-faux",
            method: .POST,
            requiresAuth: true
        )
    }

    static func confirmer(signalementId: String) async throws -> SignalementCommunityActionResponse {
        try await APIClient.shared.request(
            "/api/signalements/\(signalementId)/confirm",
            method: .POST
        )
    }

    static func toujoursBloque(signalementId: String) async throws -> SignalementCommunityActionResponse {
        try await APIClient.shared.request(
            "/api/signalements/\(signalementId)/still-blocked",
            method: .POST
        )
    }

    static func resoudre(signalementId: String) async throws -> SignalementCommunityActionResponse {
        try await APIClient.shared.request(
            "/api/signalements/\(signalementId)/resolved",
            method: .POST
        )
    }
}

struct VoteRequest: Encodable { let vote: String }

struct SignalementVoteResponse: Decodable {
    let message: String
    let signalement: SignalementDTO?
}

struct SignalementsListResponse: Decodable {
    let signalements: [SignalementDTO]
    let pagination: SignalementsPagination?
}

struct SignalementsPagination: Decodable {
    let page: Int
    let limit: Int
    let total: Int
    let totalPages: Int
}

struct AjoutSignalementResponse: Decodable {
    let message: String
    let signalement: SignalementDTO
}

struct SignalementCommunityActionResponse: Decodable {
    let message: String
    let status: String?
    let confidence: Double?
    let community: SignalementCommunityDTO?
}

struct SignalementsParArretResponse: Decodable {
    let resume: String?
    let signalements: [SignalementSummary]
}

struct SignalementSummary: Decodable, Identifiable {
    let id: String
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String?
    let date: Date?
    let arret: String?
}
