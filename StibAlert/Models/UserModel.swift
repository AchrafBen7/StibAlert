//
//  UserModel.swift
//  StibAlert
//
//  Created by studentehb on 11/03/2025.
//

import Foundation

struct UserModel: Identifiable, Codable {
    let _id: String
    let nom: String             // Volledige naam van de gebruiker
    let email: String           // E-mailadres van de gebruiker
    let motDePasse: String      // Wachtwoord (meestal versleuteld)
    let photoProfil: String?    // URL van de profielfoto (optioneel)
    let tokenFCM: String?
    let favoris: [String]?      // Lijst met IDs van favoriete haltes
    let langue: String          // Voorkeurs-taal ("FR", "NL", "EN")
    let notifications: Bool     // Geeft aan of de gebruiker notificaties wil ontvangen
    let role: String            // Rol van de gebruiker ("Utilisateur" of "Admin") (user of admin) 
    let votes: [String]?        // Lijst met IDs van de meldingen waarop de gebruiker heeft gestemd
    let isActivated: Bool?      // Nouveau flag indiquant si le compte est activé
    // Om te voldoen aan het Identifiable-protocol gebruiken we _id als de unieke identifier.
    var id: String { _id }
}



