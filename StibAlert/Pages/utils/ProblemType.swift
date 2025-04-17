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
        ProblemColors.color(for: self.rawValue)
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
