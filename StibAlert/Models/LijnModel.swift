//
//  LijnModel.swift
//  StibAlert
//
//  Created by studentehb on 07/03/2025.
//

import Foundation

struct LijnModel: Identifiable, Codable {
    let lineid: String
    let nomComplet: String
    let typeTransport: String
    let couleur: String
    let destinationFR: String
    let destinationNL: String
    let direction: String
    
    
    var id: String {lineid}
    
   
}
