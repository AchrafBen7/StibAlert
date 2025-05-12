//
//  MeldingCardSimpleView.swift
//  StibAlert
//
//  Created by studentehb on 12/05/2025.
//

import SwiftUI

struct ArretSignalementCardView: View {
    let signalement: ArretSignalementItem

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {

            // Ligne + nom arrêt
            HStack(spacing: 12) {
                Text(signalement.ligne)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(LineColors.color(for: signalement.ligne))
                    .cornerRadius(8)

                Text(signalement.arret)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.black)

                Spacer()
            }

            // From / To — valeurs fictives ou vides
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.down.left")
                        .font(.caption)
                        .foregroundColor(.black)
                    Text("From: ???")
                        .font(.caption)
                        .foregroundColor(.black)
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.up.right")
                        .font(.caption)
                        .foregroundColor(.black)
                    Text("To: ???")
                        .font(.caption)
                        .foregroundColor(.black)
                }
            }

            // Type de problème
            if !signalement.typeProbleme.isEmpty {
                Text(signalement.typeProbleme)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 14)
                    .background(ProblemColors.color(for: signalement.typeProbleme))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
        }
        .padding(16)
        .background(ProblemColors.color(for: signalement.typeProbleme).opacity(0.07))
        .cornerRadius(20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color(hex: "#ECECEC"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
    }
}
