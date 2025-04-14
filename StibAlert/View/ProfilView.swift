//
//  ProfilView.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//

import SwiftUI

struct ProfilView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("👤 Profil de l'utilisateur").font(.title2).bold()

            if let utilisateur = authViewModel.user {
                Text("Nom : \(utilisateur.nom)")
                Text("Email : \(utilisateur.email)")
                Text("Langue : \(utilisateur.langue)")
                Text("Notifications : \(utilisateur.notifications ? "Activées" : "Désactivées")")
                Text("Rôle : \(utilisateur.role)")

                Divider()

                Text("🗳️ Signalements votés").font(.headline)
                if authViewModel.votes.isEmpty {
                    Text("Aucun vote pour l’instant.")
                } else {
                    ForEach(authViewModel.votes, id: \.self) { voteId in
                        Text("• \(voteId)")
                    }
                }
            } else {
                Text("Utilisateur non connecté.")
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Mon Profil")
        .onAppear {
            authViewModel.fetchVotesUtilisateur()
        }
    }
}
