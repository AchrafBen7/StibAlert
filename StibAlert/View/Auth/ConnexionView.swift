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
                        .foregroundColor(.blue)
                }
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top, 12)
            
            Spacer()
            
            VStack(spacing: 16) {
                // Titre
                Image("logo")
                    .resizable()
                        .scaledToFit()
                        .frame(width: 160, height: 160)
                        .padding(.bottom, 4)
                
                // Email
                TextField("Email", text: $email)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                
                // Password
                SecureField("Password", text: $motDePasse)
                    .padding()
                    .background(Color.white)
                    .cornerRadius(10)
                
                // Bouton login
                Button(action: {
                    authVM.connexion(email: email, motDePasse: motDePasse)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
                        if authVM.isAuthenticated {
                            showAlert = true
                        }
                    }
                }) {
                    Text("Login")
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(Color(hex: "#2D2C6F"))
                        .cornerRadius(10)
                }
                
              
                Button(action: {
                  
                }) {
                    Text("Forgot password?")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
             
                NavigationLink(destination: RegistatieView(authVM: authVM)) {
                    Text("Heb je nog geen account? Maak een account aan")
                        .font(.footnote)
                        .foregroundColor(.blue)
                        .underline()
                }
                .frame(maxWidth: .infinity, alignment: .center)
                
            }
            .padding()
            .background(Color(hex: "#F0F0F0"))
            .cornerRadius(16)
            .padding(.horizontal)
            
            Spacer()
        }
        .background(Color(hex: "#FAFAFD").ignoresSafeArea())
        .navigationBarHidden(true)
        .alert("✅ Succesvolle verbinding!", isPresented: $showAlert) {
            Button("OK", role: .cancel) { dismiss() }
        }
        .onChange(of: authVM.isAuthenticated) { isAuth in
            if isAuth {
                dismiss() 
            }
        }
        
    }
    
}


