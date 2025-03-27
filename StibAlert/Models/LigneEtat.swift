//
//  LigneStatus.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

struct LigneEtat: Identifiable, Decodable {
    var id: String { lineid }
    let lineid: String
    let nom: String
    let incidents: Int
    let statut: String
}


