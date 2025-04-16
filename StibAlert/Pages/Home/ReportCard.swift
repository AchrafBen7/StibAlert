//
//  ReportCard.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct MeldingenCardView: View {
    let signalement: MeldingenReadModel
    
    // Temps écoulé depuis le signalement
    private var timeElapsed: TimeInterval {
        Date().timeIntervalSince(signalement.dateSignalement)
    }
    
    // Si le signalement date de moins de 6h, opacité = 1.0,
    // sinon (entre 6h et 24h) opacité = 0.4.
    var cardOpacity: Double {
        if timeElapsed < (6 * 60 * 60) {
            return 1.0
        } else {
            return 0.4
        }
    }
    
    // Formatage de la date (ex: "14/04/2025")
    private var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        return dateFormatter.string(from: signalement.dateSignalement)
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            
            // ---------
            // Ligne + nom de l'arrêt sur une même ligne
            // ---------
            HStack(alignment: .center, spacing: 8) {
                ZStack {
                    RoundedRectangle(cornerRadius: 6, style: .continuous)
                        .fill(LineColors.color(for: signalement.ligne))
                    
                    Text(signalement.ligne)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                }
                .frame(width: 36, height: 36)
                
                Text(signalement.arretId.nom)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.black)
                    .lineLimit(1)
                    .truncationMode(.tail)
                
                Spacer()
            }
            
            // Badge pour le type de problème et la date
            HStack {
                Text(signalement.typeProbleme)
                    .font(.caption)
                    .foregroundColor(.white)
                    .padding(.vertical, 4)
                    .padding(.horizontal, 10)
                    .background(ProblemColors.color(for: signalement.typeProbleme))
                    .cornerRadius(14)
                
                Spacer()
                
                Text(formattedDate)
                    .font(.caption2)
                    .foregroundColor(.gray)
            }
            
            // Votes (flèches haut/bas) ou autre contenu
            HStack(spacing: 8) {
                HStack(spacing: 2) {
                    Image(systemName: "chevron.up")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text("\(signalement.votesPositifs)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
                
                HStack(spacing: 2) {
                    Image(systemName: "chevron.down")
                        .font(.caption2)
                        .foregroundColor(.gray)
                    Text("\(signalement.votesNegatifs)")
                        .font(.caption2)
                        .foregroundColor(.gray)
                }
                .padding(4)
                .background(Color.gray.opacity(0.1))
                .cornerRadius(4)
            }
            
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
