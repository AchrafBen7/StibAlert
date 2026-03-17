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
    @State private var navigateToConnexion = false

    var body: some View {
        VStack(spacing: 16) {
            Text(L10n.Auth.otpPrompt)

            TextField(L10n.Auth.otpPlaceholder, text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title)
                .padding()

            Button(L10n.Auth.activateAccount) {
                authVM.activer(code: code)
               
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                  
                    if authVM.errorMessage == nil {
                        showAlert = true
                    }
                }
            }
            .buttonStyle(PrimaryButtonStyle())

            if let msg = authVM.errorMessage {
                Text(msg)
                    .foregroundColor(AppTheme.Colors.danger)
            }

            Spacer()

           
            NavigationLink(destination: ConnexionView(authVM: authVM),
                           isActive: $navigateToConnexion,
                           label: { EmptyView() })
        }
        .padding()
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationTitle(L10n.Auth.activationTitle)
        .alert(L10n.Auth.activationSentTitle, isPresented: $showAlert) {
            Button(L10n.Common.ok, role: .cancel) {
                
                navigateToConnexion = true
            }
        }
    }
}
