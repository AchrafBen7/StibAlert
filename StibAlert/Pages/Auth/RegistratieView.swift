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
    @State private var navigateToActivation = false
    @Environment(\.dismiss) var dismiss

    var body: some View {
        VStack {
            // 🔙 Bouton retour
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)

            Spacer()

            VStack(spacing: 16) {
                Image("logo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 160, height: 160) // ajuste à ton besoin
                    .padding(.bottom, 4)


                TextField("Nom complet", text: $nom)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)

                TextField("Email", text: $email)
                    .padding()
                    .background(Color.white)
                    .keyboardType(.emailAddress)
                    .autocapitalization(.none)
                    .cornerRadius(10)

                SecureField("Password", text: $motDePasse)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)

                Button("Sign in") {
                    authVM.inscrire(nom: nom, email: email, motDePasse: motDePasse)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if authVM.activationToken != nil {
                            showAlert = true
                        }
                    }
                }
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(hex: "#2D2C6F"))
                .cornerRadius(10)

                Button(action: {
                    // Future implémentation
                }) {
                    Text("Forgot password?")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)

                NavigationLink(destination: ConnexionView(authVM: authVM)) {
                    Text("Déjà un compte ? Se connecter")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)

                // Navigation automatique vers activation
                NavigationLink(
                    destination: ActivationView(authVM: authVM),
                    isActive: $navigateToActivation,
                    label: { EmptyView() }
                )
            }
            .padding()
            .background(Color(hex: "#F0F0F0"))
            .cornerRadius(16)
            .padding(.horizontal)

            Spacer()
        }
        .background(Color(hex: "#FAFAFD").ignoresSafeArea())
        .navigationBarHidden(true)
        .alert("✅ Code envoyé", isPresented: $showAlert) {
            Button("OK") {
                navigateToActivation = true
            }
        } message: {
            Text("Un code a été envoyé à \(email).")
        }
    }
}
