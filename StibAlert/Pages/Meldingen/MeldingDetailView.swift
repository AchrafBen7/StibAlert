//
//  MeldingDetailView.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.

import SwiftUI

struct MeldingDetailView: View {
    let arretId: String
    let signalementId: String
    @StateObject private var viewModel = MeldingDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let signalement = viewModel.signalement {
                    
                    // --- LIGNE + ARRÊT ---
                    HStack(alignment: .center, spacing: 12) {
                        Circle()
                            .fill(LineColors.color(for: signalement.ligne))
                            .frame(width: 44, height: 44)
                            .overlay(
                                Text(signalement.ligne)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            )
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.halteNom ?? "Arrêt inconnu")
                                .font(.headline)
                                .foregroundColor(.black)
                            Text(signalement.dateSignalement, style: .time)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }
                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)

                    // --- TYPE DE PROBLÈME ---
                    HStack(spacing: 12) {
                        Image(systemName: ProbleemType(rawValue: signalement.typeProbleme)?.icon ?? "exclamationmark.triangle.fill")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 26, height: 26)
                            .foregroundColor(.white)
                            .padding(10)
                            .background(ProblemColors.color(for: signalement.typeProbleme))
                            .clipShape(Circle())

                        Text(signalement.typeProbleme)
                            .font(.headline)
                            .foregroundColor(.black)
                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)

                    // --- DESCRIPTION ---
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Text(signalement.description)
                            .font(.body)
                            .foregroundColor(.black)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(16)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                    .padding(.horizontal)

                    // --- CONFIANCE ---
                    Text("Confiance : \(signalement.confiance.capitalized)")
                        .font(.footnote)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .foregroundColor(.blue)
                        .cornerRadius(12)

                    // --- VOTES ---
                    HStack(spacing: 16) {
                        voteButton(icon: "hand.thumbsup.fill", count: signalement.votesPositifs, color: .green) {
                            viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: true)
                        }
                        voteButton(icon: "hand.thumbsdown.fill", count: signalement.votesNegatifs, color: .red) {
                            viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: false)
                        }
                    }
                    .padding(.horizontal)
                } else if let errorMessage = viewModel.errorMessage {
                    Text("Erreur : \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else {
                    ProgressView("Chargement du signalement…")
                        .padding()
                }
            }
            .padding(.vertical, 24)
        }
        .background(Color(hex: "#FAFAFD").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                if let signalement = viewModel.signalement {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(LineColors.color(for: signalement.ligne))
                            .frame(width: 24, height: 24)
                            .overlay(
                                Text(signalement.ligne)
                                    .font(.caption)
                                    .foregroundColor(.white)
                            )
                        Text(viewModel.halteNom ?? "Arrêt inconnu")
                            .font(.subheadline)
                            .fontWeight(.medium)
                    }
                } else {
                    Text("Chargement…")
                        .font(.subheadline)
                }
            }
        }
        .onAppear {
            viewModel.fetchSignalement(arretId: arretId, signalementId: signalementId)
        }
    }

    private func voteButton(icon: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                Text("\(count)")
                    .fontWeight(.semibold)
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.9))
            .foregroundColor(.white)
            .cornerRadius(14)
        }
    }
}
