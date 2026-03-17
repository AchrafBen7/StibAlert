//
//  AlternativeModel.swift
//  StibAlert
//
//  Created by studentehb on 28/03/2025.
//

struct AlternativeResponse: Decodable {
    let arret: String
    let ligneAffectee: String
    let alternatives: [String]
    let suggestion: String
}
