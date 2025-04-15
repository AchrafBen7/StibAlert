//
//  ReportCard.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct MeldingenCardView: View {
    let signalement: MeldingenReadModel

    // Calcul de l'opacité : si plus de 24h se sont écoulées depuis la date du signalement,
    // on applique une opacité plus faible.
    var cardOpacity: Double {
        let twentyFourHours: TimeInterval = 24 * 60 * 60
        return Date().timeIntervalSince(signalement.dateSignalement) > twentyFourHours ? 0.4 : 1.0
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            
            // -------------------------
            // Carré arrondi « style STIB »
            // -------------------------
            ZStack {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(LineColors.color(for: signalement.ligne))
                
                Text(signalement.ligne)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
            }
            // Dimensions pour un rendu carré : ajustez selon vos préférences
            .frame(width: 36, height: 36)
            
            // Nom de l'arrêt
            Text(signalement.arretId.nom)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .lineLimit(1)

            // Type de problème signalé
            Text(signalement.typeProbleme)
                .font(.caption2)
                .foregroundColor(.gray)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer() // Pousse le contenu vers le haut
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#ECECEC"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
        .opacity(cardOpacity)
    }
}
