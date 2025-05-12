//
//  LigneStatus.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//
import Foundation
struct LigneEtat: Identifiable, Decodable {
    var id: String { lineid }
    let lineid: String
    let nom: String
    let incidents: Int
    let statut: String
}


