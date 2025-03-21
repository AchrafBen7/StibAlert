//
//  MeldingenModel.swift
//  StibAlert
//
//  Created by studentehb on 11/03/2025.
//

import Foundation

struct MeldingenModel: Identifiable, Codable {
    let _id: String             // Unieke identifier, gegenereerd door de database
    let utilisateurId: String?  // Identifier van de gekoppelde gebruiker (optioneel als deze niet wordt meegeleverd)
    let arretId: String         // Identifier van de gekoppelde halte
    let ligne: String           // De lijn waarop de melding betrekking heeft
    let typeProbleme: String    // Het type probleem (bijv. Vertraging, Ongeluk, Panne, etc.)
    let description: String     // Gedetailleerde beschrijving van het probleem
    let photo: String?          // URL van de bijgevoegde foto (optioneel)
    let dateSignalement: Date   // Datum en tijdstip van de melding
    let validationIA: Bool      // Geeft aan of de melding door de AI is gevalideerd
    let resumeIA: String?       // Samenvatting gegenereerd door de AI 
    
    // Stemmen en meldingen voor het modereren van de geldigheid van de melding
    let votesPositifs: Int      // Aantal positieve stemmen
    let votesNegatifs: Int      // Aantal negatieve stemmen
    let signalements: Int       // Aantal keren dat de melding betwist is
    
    // GPS-coördinaten
    let latitude: Double?
    let longitude: Double?
    
    let confiance: String       // Vertrouwensniveau (bijv. hoog, gemiddeld, laag)
    
    let arret: String?
    
    // Conform Identifiable: We gebruiken _id als de unieke identifier
    var id: String { _id }
}
