//
//  halteModel.swift
//  StibAlert
//
//  Created by studentehb on 07/03/2025.
// hier werd alles door mij gocodeerd geen ai werd gebruikt
import Foundation


struct HalteModel: Identifiable, Codable {
    let _id: String          // L'ObjectID Mongo, ex. "67a3fb95bf28034a6ee27928"
    let stopId: String       // L'ID STIB, ex. "0631"
    let nom: String
    let latitude: Double
    let longitude: Double
    let typeTransport: [String]
    let lignesDesservies: [String]
    let etat: String
    let signalementsRecents: [MeldingenModel]?
    let orderRaw: [String: SafeInt]?
    var order: [String: Int]? {
        orderRaw?.mapValues { $0.value }
    }

    var distanceToUser: Double?
    
    // SwiftUI utilisera _id comme identifiant unique
    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id
        case stopId = "stop_id"
        case nom, latitude, longitude
        case typeTransport, lignesDesservies, etat, signalementsRecents
        case orderRaw = "order"
    }

}

struct SafeInt: Codable {
    let value: Int

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let stringWrapped = try? container.decode([String: String].self),
                  let number = stringWrapped["$numberInt"],
                  let int = Int(number) {
            self.value = int
        } else if let string = try? container.decode(String.self),
                  let int = Int(string) {
            self.value = int
        } else {
            print("[SAFEINT] ⚠️ Impossible de décoder : \(String(describing: try? container.decode(String.self)))")
            self.value = 0 // ou throw une erreur si tu préfères forcer l'échec
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(value)
    }
}





