//
//  ReportCard.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct MeldingenCardView: View {
    let signalement: MeldingenReadModel
    

    private var timeElapsed: TimeInterval {
        Date().timeIntervalSince(signalement.dateSignalement)
    }
    

    var cardOpacity: Double {
        if timeElapsed < (6 * 60 * 60) {
            return 1.0
        } else {
            return 0.4
        }
    }
    

    private var formattedDate: String {
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "dd/MM/yyyy"
        return dateFormatter.string(from: signalement.dateSignalement)
    }
    
    var body: some View {
            VStack(alignment: .leading, spacing: 12) {

          
                HStack(spacing: 12) {
                    Text(signalement.ligne)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.vertical, 6)
                        .padding(.horizontal, 12)
                        .background(LineColors.color(for: signalement.ligne))
                        .cornerRadius(8)

                    Text(signalement.arretId.nom)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)

                    Spacer()
                }


                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.down.left")
                            .font(.caption)
                            .foregroundColor(.black)
                        Text("From: Centraal Station")
                            .font(.caption)
                            .foregroundColor(.black)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right")
                            .font(.caption)
                            .foregroundColor(.black)
                        Text("To: Begrafenis evere")
                            .font(.caption)
                            .foregroundColor(.black)
                    }
                }

 
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
            .opacity(cardOpacity)
        }
    }
