//
//  halteModel.swift
//  StibAlert
//
//  Created by studentehb on 07/03/2025.
// hier werd alles door mij gocodeerd geen ai werd gebruikt

import Foundation
// Identifiable protocol : elke object moet een unieke id hebben hier is het stop_id
struct HalteModel: Identifiable, Codable {// codable voor een eenvouding convertie tot json[
    
    let stopId: String // unieke identifier voor een halte
    let nom: String // (naam) naam van het halte
    let latitude: Double //(breedtegraad) positie van het halte
    let longitude: Double // (lengtegraad) positie van het halte
    let typeTransport: String // het typeTransport "tram", "Bus" of "metro"
    let lignesDesservies: [String] // bediende lijnen
    let etat: String // "groen" "oranje" of "rood"
    let signalementsRecents: [String]? // lijst van id's van recente meldingen
    
    var id: String {stopId} // de id wordt opgenomen in mijn stop_id
    
    // CodingKeys zal ervoor zorgen dat mijn propertynaam met de sleutel in mijn json
      enum CodingKeys: String, CodingKey {
          case stopId = "stop_id" // stop_id kom vanuit mijn backend
          case nom, latitude, longitude, typeTransport, lignesDesservies, etat, signalementsRecents
         
         
      }
    
}
