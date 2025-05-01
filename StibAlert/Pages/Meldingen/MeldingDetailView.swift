//
//  MeldingDetailView.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.
import SwiftUI

struct MeldingDetailView: View {
    let arretId: String
    let signalementId: String
    @Environment(\.dismiss) var dismiss
    @StateObject private var viewModel = MeldingDetailViewModel()
    
    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                if viewModel.isLoading {
                    Spacer()
                    ProgressView("Chargement...")
                        .progressViewStyle(CircularProgressViewStyle(tint: Color(hex: "#4557A1")))
                        .scaleEffect(1.5)
                    Spacer()
                } else if let errorMessage = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.red)
                        
                        Text("Erreur")
                            .font(.title3)
                            .fontWeight(.bold)
                        
                        Text(errorMessage)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                        
                        Button("Réessayer") {
                            viewModel.fetchSignalement(arretId: arretId, signalementId: signalementId)
                        }
                        .padding(.horizontal)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(8)
                    }
                    .padding()
                } else if let signalement = viewModel.signalement {
                    VStack(spacing: 20) {
                        // 🔷 Ligne + Arrêt + Type
                        HStack {
                            HStack(spacing: 8) {
                                Text(signalement.ligne)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(LineColors.color(for: signalement.ligne))
                                    .cornerRadius(10)
                                
                                Text(viewModel.halteNom ?? "Arrêt inconnu")
                                    .font(.system(size: 16, weight: .semibold))
                                    .foregroundColor(.black)
                            }
                            
                            Spacer()
                            
                            HStack(spacing: 6) {
                                Image(systemName: ProbleemType(rawValue: signalement.typeProbleme)?.icon ?? "exclamationmark.triangle.fill")
                                    .font(.system(size: 16, weight: .medium))
                                
                                Text(signalement.typeProbleme.capitalized)
                                    .font(.system(size: 15, weight: .semibold))
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 12)
                            .background(ProblemColors.color(for: signalement.typeProbleme))
                            .foregroundColor(.white)
                            .cornerRadius(18)
                        }
                        
                        // 📝 Description
                        VStack(spacing: 8) {
                            Text("Description")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundColor(.black)
                            
                            Text(signalement.description)
                                .font(.system(size: 15))
                                .foregroundColor(.black)
                                .multilineTextAlignment(.center)
                                .frame(maxWidth: .infinity)
                                .frame(height: 70)
                                .contentShape(Rectangle())
                        }
                        .padding()
                        .frame(minHeight: 90)
                        .background(Color.white)
                        .cornerRadius(18)
                        
                        // 🖼️ Image
                        if let photo = signalement.photo, let url = URL(string: photo) {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("Photo du signalement")
                                    .font(.subheadline)
                                    .foregroundColor(.gray)
                                
                                AsyncImage(url: url) { image in
                                    image
                                        .resizable()
                                        .aspectRatio(contentMode: .fill)
                                        .frame(maxWidth: .infinity)
                                        .frame(height: 220)
                                        .clipped()
                                        .cornerRadius(12)
                                        .shadow(radius: 5)
                                } placeholder: {
                                    Rectangle()
                                        .fill(Color.gray.opacity(0.2))
                                        .frame(height: 220)
                                        .cornerRadius(12)
                                }
                                
                                Text("Do you like or not?")
                                    .font(.footnote)
                                    .foregroundColor(.black)
                                
                                HStack(spacing: 16) {
                                    voteSquareButton(icon: "heart") {
                                        viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: true)
                                    }
                                    
                                    voteSquareButton(icon: "eye.slash") {
                                        viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: false)
                                    }
                                }
                            }
                            .padding()
                            .background(Color(hex: "#F2F2F2"))
                            .cornerRadius(24)
                            .padding(.horizontal)
                        }
                    }
                    .padding(.horizontal)
                } else {
                    Text("Aucun contenu à afficher.")
                        .foregroundColor(.gray)
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
                        .font(.system(size: 18))
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
            print("👀 [DEBUG] Vue MeldingDetailView apparaît")
            viewModel.fetchSignalement(arretId: arretId, signalementId: signalementId)
        }
    }
    
    
    // 🧩 Cette fonction est maintenant bien en dehors du body
    private func voteSquareButton(icon: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .padding(16)
                .background(Color(hex: "#F18F5D"))
                .foregroundColor(.white)
                .cornerRadius(10)
        }
    }
}
