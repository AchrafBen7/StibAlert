//
//  MeldingDetailView.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.

import SwiftUI


import SwiftUI

struct MeldingDetailView: View {
    let arretId: String
    let signalementId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = MeldingDetailViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                if let signalement = viewModel.signalement {
                    
                    // --- Bloc principal arrondi gris ---
                    VStack(alignment: .leading, spacing: 16) {
                        
                        // Ligne + Arrêt + Type problème
                        HStack {
                            HStack(spacing: 8) {
                                Text(signalement.ligne)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 4)
                                    .background(LineColors.color(for: signalement.ligne))
                                    .cornerRadius(8)
                                
                                Text(viewModel.halteNom ?? "Arrêt inconnu")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Image(systemName: ProbleemType(rawValue: signalement.typeProbleme)?.icon ?? "exclamationmark.triangle.fill")
                                    .font(.system(size: 14, weight: .medium))
                                Text(signalement.typeProbleme.capitalized)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(ProblemColors.color(for: signalement.typeProbleme))
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        
                        // Description (dans petit rectangle blanc)
                        VStack(spacing: 8) {
                            Text("Description")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundColor(.black)
                            
                            Text(signalement.description)
                                .font(.system(size: 14))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(16)
                        
                        // 2 Frames d’images
                        HStack(spacing: 12) {
                            if let photo = signalement.photo, let url = URL(string: photo) {
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .scaledToFill()
                                } placeholder: {
                                    Color.gray.opacity(0.3)
                                }
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(12)
                            }
                            
                            // Placeholder si pas de 2e image
                            Color.gray.opacity(0.15)
                                .frame(height: 110)
                                .frame(maxWidth: .infinity)
                                .cornerRadius(12)
                        }
                        
                    }
                    .padding()
                    .background(Color(hex: "#F2F2F2"))
                    .cornerRadius(20)
                    .padding(.horizontal)
                    
                    // --- Like / Dislike ---
                    Text("Do you like or not?")
                        .font(.footnote)
                        .padding(.top, 4)
                    
                    HStack(spacing: 24) {
                        Button {
                            viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: true)
                        } label: {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                        
                        Button {
                            viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: false)
                        } label: {
                            Image(systemName: "eye.slash.fill")
                                .foregroundColor(.white)
                                .padding()
                                .background(Color.orange)
                                .clipShape(Circle())
                        }
                    }
                    .padding(.vertical, 24)
                    
                } else if let errorMessage = viewModel.errorMessage {
                    Text("Erreur : \(errorMessage)")
                        .foregroundColor(.red)
                        .padding()
                } else {
                    ProgressView("Chargement du signalement…")
                        .padding()
                }
            }
            .padding(.vertical)
        }
        .background(Color(hex: "#FAFAFD").ignoresSafeArea())
        .navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(true)
        .toolbar {
            ToolbarItem(placement: .navigationBarLeading) {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .regular))
                        .foregroundColor(Color(hex: "#4557A1"))
                }
            }
            ToolbarItem(placement: .principal) {
                Text("Informations")
                    .font(.subheadline)
                    .fontWeight(.medium)
            }
        }
        .onAppear {
            viewModel.fetchSignalement(arretId: arretId, signalementId: signalementId)
        }
    }
}


// ✅ Fonction bien placée ici, en-dehors du body
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


