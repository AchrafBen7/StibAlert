//
//  RegistratieView.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//

import SwiftUI

struct RegistatieView: View {
    @ObservedObject var authVM: AuthViewModel
    @State private var nom = ""
    @State private var email = ""
    @State private var motDePasse = ""
    @State private var showAlert = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("S'inscrire")
                .font(.largeTitle)
                .bold()

            TextField("Nom", text: $nom)
                .textFieldStyle(.roundedBorder)

            TextField("Email", text: $email)
                .textFieldStyle(.roundedBorder)
                .keyboardType(.emailAddress)
                .autocapitalization(.none)

            SecureField("Mot de passe", text: $motDePasse)
                .textFieldStyle(.roundedBorder)

            Button("S'inscrire") {
                authVM.inscrire(nom: nom, email: email, motDePasse: motDePasse)
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    if authVM.activationToken != nil {
                        showAlert = true
                    }
                }
            }
            .foregroundColor(.blue)
        }
        .padding()
        .alert("✅ Code envoyé", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text("Un code a été envoyé à \(email).")
        }
    }
}

