import Foundation

struct LigneEtatDTO: Decodable, Identifiable {
    var id: String { lineid }
    let lineid: String
    let nom: String?
    let nomRetour: String?
    let typeTransport: String?
    let couleur: String?
    let direction: String?
    let destination: LigneDestinationDTO?
    let incidents: Int
    let statut: String

    enum CodingKeys: String, CodingKey {
        case lineid, nom, nomRetour, typeTransport, couleur, direction, destination, incidents, statut
    }
}

struct LigneDestinationDTO: Decodable, Equatable {
    let fr: String?
    let nl: String?
}

enum LigneService {
    static func etatLignes() async throws -> [LigneEtatDTO] {
        try await APIClient.shared.request("/api/lignes/etat-lignes")
    }
}
