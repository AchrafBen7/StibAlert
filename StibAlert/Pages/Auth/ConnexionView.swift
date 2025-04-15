//
//  ConnexionView.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//

import SwiftUI

struct ConnexionView: View {
    @ObservedObject var authVM: AuthViewModel
    @State private var email = ""
    @State private var motDePasse = ""
    @State private var showAlert = false
    @Environment(\.dismiss) var dismiss   // Add dismiss environment value

    var body: some View {
        Form {
            TextField("Email", text: $email)
                .keyboardType(.emailAddress)
            SecureField("Mot de passe", text: $motDePasse)

            Button("Se connecter") {
                authVM.connexion(email: email, motDePasse: motDePasse)
                DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                    if authVM.isAuthenticated {
                        showAlert = true
                    }
                }
            }

            if let msg = authVM.errorMessage {
                Text(msg).foregroundColor(.red)
            }
        }
        .navigationTitle("Connexion")
        .alert("✅ Connexion réussie !", isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                dismiss()  // This dismisses the modal and returns to Home
            }
        }
    }
}

