//
//  LijnModel.swift
//  StibAlert
//
//  Created by studentehb on 07/03/2025.
//
import Foundation
struct LijnModel: Identifiable, Codable {
    let _id: String
    let lineid: String
    let nomComplet: String
    let nomCompletRetour: String? 
    let typeTransport: String
    let couleur: String
    let direction: String
    
   

    var id: String { _id }
}





