import Foundation

struct UtilisateurDTO: Codable, Identifiable, Equatable {
    let id: String
    let nom: String
    let email: String
    let photoProfil: String?
    let langue: String?
    let notifications: Bool?
    let role: String?
    let favoris: [String]?
    let favorisDetails: [FavoriDetailDTO]?
    let votes: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, email, photoProfil, langue, notifications, role, favoris, favorisDetails, votes
    }
}

struct FavoriDetailDTO: Codable, Identifiable, Equatable {
    let id: String
    let nom: String
    let latitude: Double?
    let longitude: Double?
    let lignesDesservies: [String]?
    let status: String?
    let crowding: String?
    let signalementCount: Int?
    let primaryLine: String?
    let lastProblemType: String?
    let lastConfidence: String?
    let nextPassageMinutes: Int?
    let lastUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, latitude, longitude, lignesDesservies
        case status, crowding, signalementCount, primaryLine
        case lastProblemType, lastConfidence, nextPassageMinutes, lastUpdatedAt
    }
}

struct InscriptionRequest: Encodable {
    let nom: String
    let email: String
    let motDePasse: String
}

struct InscriptionResponse: Decodable {
    let message: String
    let activationToken: String
}

struct ActivationRequest: Encodable {
    let activationToken: String
    let activationCode: String
}

struct AuthResponse: Decodable {
    let message: String
    let utilisateur: UtilisateurDTO
    let token: String
}

struct ConnexionRequest: Encodable {
    let email: String
    let motDePasse: String
}

struct MessageResponse: Decodable {
    let message: String
}

struct SignalementDTO: Codable, Identifiable, Equatable {
    let id: String
    let utilisateurId: String?
    let arretId: ArretRef?
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String?
    let latitude: Double?
    let longitude: Double?
    let confiance: String?
    let votesPositifs: Int?
    let votesNegatifs: Int?
    let dateSignalement: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case utilisateurId, arretId, ligne, typeProbleme, description
        case photo, latitude, longitude, confiance
        case votesPositifs, votesNegatifs, dateSignalement
    }
}

enum ArretRef: Codable, Equatable {
    case id(String)
    case populated(ArretDTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .id(s); return
        }
        let a = try container.decode(ArretDTO.self)
        self = .populated(a)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .id(let s): try container.encode(s)
        case .populated(let a): try container.encode(a)
        }
    }

    var id: String {
        switch self {
        case .id(let s): return s
        case .populated(let a): return a.id
        }
    }
}

struct ArretDTO: Codable, Equatable {
    let id: String
    let nom: String
    let latitude: Double?
    let longitude: Double?
    let lignesDesservies: [String]?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, latitude, longitude, lignesDesservies
    }
}
