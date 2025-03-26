//
//  ProfilView.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//

import SwiftUI

struct ProfilView: View {
    let utilisateur: UserModel

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("👤 Profil de l'utilisateur").font(.title2).bold()

            Text("Nom : \(utilisateur.nom)")
            Text("Email : \(utilisateur.email)")
            Text("Langue : \(utilisateur.langue)")
            Text("Notifications : \(utilisateur.notifications ? "Activées" : "Désactivées")")
            Text("Rôle : \(utilisateur.role)")

            Spacer()
        }
        .padding()
        .navigationTitle("Mon Profil")
    }
}


