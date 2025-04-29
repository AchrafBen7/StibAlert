//
//  MeldingDetailView.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.
//
import SwiftUI

struct MeldingDetailView: View {
    let arretId: String
    let signalementId: String
    @StateObject private var viewModel = MeldingDetailViewModel()

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let signalement = viewModel.signalement {
                    
                    // ----------- LIGNE ET ARRÊT -----------
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(LineColors.color(for: signalement.ligne))
                                .frame(width: 40, height: 40)
                            Text(signalement.ligne)
                                .foregroundColor(.white)
                                .font(.subheadline.bold())
                        }

                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.halteNom ?? "Arrêt inconnu")

                                .font(.headline)
                            Text(signalement.dateSignalement, style: .time)
                                .font(.caption)
                                .foregroundColor(.gray)
                        }

                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)

                    // ----------- TYPE DE PROBLÈME -----------
                    HStack(spacing: 12) {
                        Image(systemName: ProbleemType(rawValue: signalement.typeProbleme)?.icon ?? "exclamationmark.circle")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.white)
                            .padding(8)
                            .background(ProblemColors.color(for: signalement.typeProbleme))
                            .clipShape(Circle())

                        Text(signalement.typeProbleme)
                            .font(.headline)
                            .foregroundColor(.black)

                        Spacer()
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)

                    // ----------- DESCRIPTION -----------
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Description")
                            .font(.caption)
                            .foregroundColor(.gray)

                        Text(signalement.description)
                            .font(.body)
                            .foregroundColor(.black)
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: .black.opacity(0.05), radius: 5, x: 0, y: 2)
                    .padding(.horizontal)

                    // ----------- CONFIANCE -----------
                    Text("Confiance : \(signalement.confiance.capitalized)")
                        .font(.caption)
                        .foregroundColor(.blue)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(14)
                        .padding(.horizontal)

                    // ----------- VOTES -----------
                    HStack(spacing: 20) {
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
                    ProgressView("Chargement du signalement...")
                        .padding()
                }
            }
            .padding(.vertical)
        }
        .background(Color(hex: "#FAFAFD").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .principal) {
                HStack(spacing: 8) {
                    if let signalement = viewModel.signalement {
                        ZStack {
                            Circle()
                                .fill(LineColors.color(for: signalement.ligne))
                                .frame(width: 24, height: 24)
                            Text(signalement.ligne)
                                .font(.caption)
                                .foregroundColor(.white)
                        }

                        Text(viewModel.halteNom ?? "Arrêt inconnu")

                            .font(.subheadline)
                            .fontWeight(.medium)
                    } else {
                        Text("Chargement...")
                            .font(.subheadline)
                    }
                }
            }
        }
        .onAppear {
            viewModel.fetchSignalement(arretId: arretId, signalementId: signalementId)
        }
    }

    private func voteButton(icon: String, count: Int, color: Color, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack {
                Image(systemName: icon)
                    .font(.body)
                Text("\(count)")
                    .font(.body)
                    .bold()
            }
            .padding()
            .frame(maxWidth: .infinity)
            .background(color.opacity(0.8))
            .foregroundColor(.white)
            .cornerRadius(12)
        }
    }
}
