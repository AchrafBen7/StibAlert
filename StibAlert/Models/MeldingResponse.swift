//
//  MeldingResponse.swift
//  StibAlert
//
//  Created by studentehb on 21/03/2025.
//

import Foundation

struct ArretSignalementsResponse: Codable {
    let resume: String
    let signalements: [ArretSignalementItem]
}

struct ArretSignalementItem: Identifiable, Codable {
    let id: String
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String?
    let date: String
    let arret: String
}


