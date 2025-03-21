//
//  MeldingenReadModel.swift
//  StibAlert
//
//  Created by studentehb on 21/03/2025.
//

// SignalementReadModel.swift

import Foundation

struct MeldingenReadModel: Identifiable, Codable {
    let _id: String
    let utilisateurId: String?
    let arretId: HalteModel       // <-- objet complet
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String?
    let dateSignalement: Date
    let validationIA: Bool
    let resumeIA: String?
    let votesPositifs: Int
    let votesNegatifs: Int
    let signalements: Int
    let latitude: Double?
    let longitude: Double?
    let confiance: String

    var id: String { _id }
}
