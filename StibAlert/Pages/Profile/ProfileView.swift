//
//  ProfileView.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//
//
//  ProfilView.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//

import SwiftUI

struct ProfilView: View {
    @ObservedObject var authViewModel: AuthViewModel
    
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                // En-tête du profil
                if let user = authViewModel.user {
                    VStack(spacing: 12) {
                        if let photoURLString = user.photoProfil,
                           let photoURL = URL(string: photoURLString) {
                            AsyncImage(url: photoURL) { phase in
                                switch phase {
                                case .empty:
                                    ProgressView()
                                        .frame(width: 120, height: 120)
                                case .success(let image):
                                    image
                                        .resizable()
                                        .scaledToFill()
                                        .frame(width: 120, height: 120)
                                        .clipShape(Circle())
                                        .overlay(
                                            Circle()
                                                .stroke(Color(hex: "#ECECEC"), lineWidth: 2)
                                        )
                                case .failure:
                                    Image(systemName: "person.fill")
                                        .resizable()
                                        .scaledToFit()
                                        .frame(width: 120, height: 120)
                                        .foregroundColor(.gray)
                                        .clipShape(Circle())
                                @unknown default:
                                    EmptyView()
                                }
                            }
                        } else {
                            // Si pas de photo, affichage de l'initiale
                            Text(String(user.nom.prefix(1)))
                                .font(.system(size: 50, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 120, height: 120)
                                .background(Color.blue)
                                .clipShape(Circle())
                        }
                        
                        // Nom et Email
                        Text(user.nom)
                            .font(.title)
                            .fontWeight(.bold)
                        Text(user.email)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                    }
                    .padding(.top, 20)
                } else {
                    Text("Utilisateur non connecté")
                        .font(.title3)
                        .foregroundColor(.red)
                }
                
                Divider()
                
                // Détails utilisateur dans une carte
                if let user = authViewModel.user {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Langue:")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(user.langue)
                        }
                        HStack {
                            Text("Notifications:")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(user.notifications ? "Activées" : "Désactivées")
                        }
                        HStack {
                            Text("Rôle:")
                                .fontWeight(.semibold)
                            Spacer()
                            Text(user.role)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(12)
                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                }
                
                Divider()
                
                // Section votes
                VStack(alignment: .leading, spacing: 10) {
                    Text("🗳️ Signalements votés")
                        .font(.headline)
                    
                    if authViewModel.votes.isEmpty {
                        Text("Aucun vote pour l’instant.")
                            .foregroundColor(.gray)
                    } else {
                        ForEach(authViewModel.votes, id: \.self) { voteId in
                            Text("• \(voteId)")
                                .font(.subheadline)
                        }
                    }
                }
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                
                Spacer()
            }
            .padding()
        }
        .background(Color(hex: "#FAFAFD"))
        .navigationTitle("Mon Profil")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                Button("Déconnexion") {
                    authViewModel.deconnexion()
                    // Optionnel : vous pouvez ajouter ici une logique pour
                    // fermer la vue de profil ou rafraîchir l'interface
                }
            }
        }
        .onAppear {
            authViewModel.fetchVotesUtilisateur()
        }
    }
}

struct ProfilView_Previews: PreviewProvider {
    static var previews: some View {
        ProfilView(authViewModel: AuthViewModel())
    }
}
