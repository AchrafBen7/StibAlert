//
//  halteModel.swift
//  StibAlert
//
//  Created by studentehb on 07/03/2025.
// hier werd alles door mij gocodeerd geen ai werd gebruikt
import Foundation

struct HalteModel: Identifiable, Codable {
    let _id: String
    let stopId: String
    let nom: String
    let latitude: Double
    let longitude: Double
    let typeTransport: [String]
    let lignesDesservies: [String]
    let etat: String
    let signalementsRecents: [MeldingenModel]?
    let order: [String: Int]?
    var distanceToUser: Double?

    var id: String { _id }

    enum CodingKeys: String, CodingKey {
        case _id
        case stopId = "stop_id"
        case nom, latitude, longitude
        case typeTransport, lignesDesservies, etat, signalementsRecents, order
    }
}








