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
            Text("Voer uw 4-cijferige code in")

            TextField("Code OTP", text: $code)
                .keyboardType(.numberPad)
                .multilineTextAlignment(.center)
                .font(.title)
                .padding()

            Button("Activeer je account") {
                authVM.activer(code: code)
               
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                  
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

           
            NavigationLink(destination: ConnexionView(authVM: authVM),
                           isActive: $navigateToConnexion,
                           label: { EmptyView() })
        }
        .padding()
        .navigationTitle("Activatie")
        .alert("Activatie verzonden !", isPresented: $showAlert) {
            Button("OK", role: .cancel) {
                
                navigateToConnexion = true
            }
        }
    }
}

