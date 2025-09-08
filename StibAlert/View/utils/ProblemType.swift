//
//  ProblemType.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
//
import SwiftUI

enum ProbleemType: String, CaseIterable, Identifiable {
    case Retard, Accident, Panne, Propreté, Agression, Incivilité, Autre
    
    var id: String { self.rawValue }
    
    var color: Color {
        switch self {
        case .Retard: return Color(hex: "#F4B400")
        case .Accident: return Color(hex: "#DB4437")
        case .Panne: return Color(hex: "#AB47BC")
        case .Propreté: return Color(hex: "#5C9DF5")
        case .Agression: return Color(hex: "#FF7043")
        case .Incivilité: return Color(hex: "#C0CA33")
        case .Autre: return Color.gray                  
        }
    }
    
    var icon: String {
        switch self {
        case .Retard: return "clock"
        case .Accident: return "car.fill"
        case .Panne: return "wrench.fill"
        case .Propreté: return "leaf.fill"
        case .Agression: return "exclamationmark.triangle.fill"
        case .Incivilité: return "person.crop.circle.badge.exclamationmark"
        case .Autre: return "questionmark"
        }
    }
}

