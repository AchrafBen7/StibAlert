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
                
                TextField(L10n.Auth.emailPlaceholder, text: $email)
                    .keyboardType(.emailAddress)
                    .authFieldStyle()
                
                SecureField(L10n.Auth.passwordPlaceholder, text: $motDePasse)
                    .authFieldStyle()
                
                Button(action: {
                    authVM.connexion(email: email, motDePasse: motDePasse)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if authVM.isAuthenticated {
                            showAlert = true
                        }
                    }
                }) {
                    Text(L10n.Common.login)
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
                
                NavigationLink(destination: RegistatieView(authVM: authVM)) {
                    Text(L10n.Auth.noAccount)
                        .font(.footnote)
                        .foregroundColor(AppTheme.Colors.primarySoft)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
            }
            .padding()
            .background(AppTheme.Colors.surface)
            .cornerRadius(AppTheme.Radius.md)
            .padding(.horizontal)
            
            Spacer()
        }
        .background(AppTheme.Colors.background.ignoresSafeArea())
        .navigationBarHidden(true)
        .alert(L10n.Auth.loginSuccessTitle, isPresented: $showAlert) {
            Button(L10n.Common.ok, role: .cancel) { dismiss() }
        }
        .onChange(of: authVM.isAuthenticated) { isAuth in
            if isAuth {
                dismiss() 
            }
        }
        
    }
    
}

