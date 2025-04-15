//
//  AuthOptionsView.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//
import SwiftUI

struct AuthOptionsView: View {
    @ObservedObject var authVM: AuthViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedOption = 0  // 0 : Connexion, 1 : Inscription

    var body: some View {
        NavigationView {
            VStack {
                Picker("Option", selection: $selectedOption) {
                    Text("Connexion").tag(0)
                    Text("Inscription").tag(1)
                }
                .pickerStyle(SegmentedPickerStyle())
                .padding()

                if selectedOption == 0 {
                    ConnexionView(authVM: authVM)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Annuler") {
                                    dismiss()
                                }
                            }
                        }
                } else {
                    RegistatieView(authVM: authVM)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Annuler") {
                                    dismiss()
                                }
                            }
                        }
                }
                Spacer()
            }
            .navigationTitle("Authentification")
            .onChange(of: authVM.isAuthenticated) { isAuth in
                if isAuth {
                    // When the user becomes authenticated, dismiss the entire sheet.
                    dismiss()
                }
            }
        }
    }
}
