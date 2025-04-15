//
//  ActivationView.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//

import SwiftUI

struct ActivationView: View {
    @ObservedObject var authVM: AuthViewModel
    @State private var code = ""
    @State private var showAlert = false
    @State private var navigateToConnexion = false // Variable pour déclencher la navigation

    var body: some View {
        VStack(spacing: 16) {
            Text("Entrez votre code à 4 chiffres")

            TextField("Code OTP", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title)
                .padding()

            Button("Activer le compte") {
                authVM.activer(code: code)
                // Simuler un court délai pour vérifier la réussite de l'activation
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    // Vous pouvez vérifier ici si authVM.errorMessage est nil pour confirmer le succès
                    if authVM.errorMessage == nil {
                        showAlert = true
                    }
                }
            }

            if let msg = authVM.errorMessage {
                Text(msg)
                    .foregroundColor(.red)
            }

            Spacer()

            // NavigationLink caché vers la page de connexion
            NavigationLink(destination: ConnexionView(authVM: authVM),
                           isActive: $navigateToConnexion,
                           label: { EmptyView() })
        }
        .padding()
        .navigationTitle("Activation")
        .alert("Activation envoyée !", isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                // Déclenche la navigation vers la ConnexionView
                navigateToConnexion = true
            }
        }
    }
}

