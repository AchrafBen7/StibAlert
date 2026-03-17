//
//  SignalementLigne.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

import Foundation

struct PerturbationResponse: Decodable {
    let resume: String
    let signalements: [Signalement]
}

struct Signalement: Identifiable, Decodable {
    var id: String { _id }
    let _id: String
    let arretId: String // ✅ string maintenant
    let arretNom: String?
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String
    let validationIA: Bool
    let votes: Int?
    let confiance: String
    let votesPositifs: Int
    let votesNegatifs: Int
    let dateSignalement: String
}


