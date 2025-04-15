//
//  ProblemColors.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//

import SwiftUI

struct ProblemColors {
    // Associe chaque type de problème à un code couleur (hex)
    static let colors: [String: String] = [
        "Retard": "#F09E1B",    // Orange
        "Accident": "#E74C3C",  // Rouge
        "Panne": "#9B59B6",     // Violet
        "Propreté": "#16A085",  // Vert
        "Agression": "#FF3B30", // Rouge vif
        "Incivilité": "#3498DB",// Bleu
        "Autre": "#95A5A6"      // Gris
    ]
    
    static func color(for problemType: String) -> Color {
        if let hex = colors[problemType] {
            return Color(hex: hex)
        }
        // Couleur par défaut si on ne trouve pas de correspondance
        return Color(hex: "#95A5A6")
    }
}
