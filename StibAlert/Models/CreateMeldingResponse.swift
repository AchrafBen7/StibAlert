//
//  CreateMeldingResponse.swift
//  StibAlert
//
//  Created by studentehb on 17/03/2025.
//
import Foundation


struct CreateMeldingResponse: Codable {
    let message: String
    let signalement: MeldingCreated
}


struct MeldingCreated: Identifiable, Codable,Equatable {
    let _id: String
    let arretId: String
    let ligne: String
    let typeProbleme: String
    let description: String
    let validationIA: Bool
    let votesPositifs: Int
    let votesNegatifs: Int
    let signalements: Int
    let confiance: String
    let dateSignalement: Date
    let __v: Int?          

    // Conformité à Identifiable
    var id: String { _id }
}
