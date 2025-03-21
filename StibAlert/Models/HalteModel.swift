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
    let signalementsRecents: [String]?

    // SwiftUI utilisera _id comme identifiant unique
    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id            // On décode l'ObjectID
        case stopId = "stop_id"
        case nom, latitude, longitude, typeTransport, lignesDesservies, etat, signalementsRecents
    }
}


