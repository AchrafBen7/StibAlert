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
        "Retard": "#F09E1B",  
        "Accident": "#E74C3C",
        "Panne": "#9B59B6",
        "Propreté": "#16A085",
        "Agression": "#FF3B30",
        "Incivilité": "#3498DB",
        "Autre": "#95A5A6"
    ]
    
    static func color(for problemType: String) -> Color {
        if let hex = colors[problemType] {
            return Color(hex: hex)
        }
     
        return Color(hex: "#95A5A6")
    }
}
