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
                showAlert = true
            }

            if let msg = authVM.errorMessage {
                Text(msg).foregroundColor(.red)
            }

            Spacer()
        }
        .padding()
        .navigationTitle("Activation")
        .alert("Activation envoyée !", isPresented: $showAlert) {
            Button("OK", role: .cancel) { }
        }
    }
}
