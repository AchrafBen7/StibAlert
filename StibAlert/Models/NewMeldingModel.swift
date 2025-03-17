//
//  NewMeldingModel.swift
//  StibAlert
//
//  Created by studentehb on 17/03/2025.
//
 
import Foundation
 
 
struct NewMeldingRequest: Codable {
    let nomArret: String
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String?
    
}
