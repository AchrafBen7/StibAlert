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
            HStack {
                Button(action: {
                    dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(AppTheme.Colors.primarySoft)
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
                    .frame(width: 160, height: 160)
                    .padding(.bottom, 4)

                TextField(L10n.Auth.fullNamePlaceholder, text: $nom)
                    .authFieldStyle()

                TextField(L10n.Auth.emailPlaceholder, text: $email)
                    .keyboardType(.emailAddress)
                    .authFieldStyle()

                SecureField(L10n.Auth.passwordPlaceholder, text: $motDePasse)
                    .authFieldStyle()

                Button(L10n.Common.register) {
                    authVM.inscrire(nom: nom, email: email, motDePasse: motDePasse)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        if authVM.activationToken != nil {
                            showAlert = true
                        }
                    }
                }
                .buttonStyle(PrimaryButtonStyle())

                Button(action: {
                    
                }) {
                    Text(L10n.Auth.forgotPassword)
                        .font(.footnote)
                        .foregroundColor(AppTheme.Colors.primarySoft)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)

                NavigationLink(destination: ConnexionView(authVM: authVM)) {
                    Text(L10n.Auth.alreadyAccount)
                        .font(.footnote)
                        .foregroundColor(AppTheme.Colors.primarySoft)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)

              
                NavigationLink(
                    destination: ActivationView(authVM: authVM),
                    isActive: $navigateToActivation,
                    label: { EmptyView() }
                )
            }
            .padding()
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.Radius.md)
            .padding(.horizontal)

            Spacer()
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .alert(L10n.Auth.codeSentTitle, isPresented: $showAlert) {
            Button(L10n.Common.ok) {
                navigateToActivation = true
            }
        } message: {
            Text(L10n.Auth.activationSentMessage(email))
        }
    }
}
