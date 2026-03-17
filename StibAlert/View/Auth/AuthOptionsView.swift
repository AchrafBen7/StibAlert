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
    @State private var selectedOption = 0

    var body: some View {
        NavigationStack {
            VStack {
                Picker(L10n.Auth.optionsPickerLabel, selection: $selectedOption) {
                    Text(L10n.Auth.loginSegment).tag(0)
                    Text(L10n.Auth.registerSegment).tag(1)
                }
                .pickerStyle(.segmented)
                .padding()

                if selectedOption == 0 {
                    ConnexionView(authVM: authVM)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.Common.cancel) {
                                    dismiss()
                                }
                            }
                        }
                } else {
                    RegistatieView(authVM: authVM)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button(L10n.Common.cancel) {
                                    dismiss()
                                }
                            }
                        }
                }
                Spacer()
            }
            .navigationTitle(L10n.Common.authenticationTitle)
            .onChange(of: authVM.isAuthenticated) { isAuth in
                if isAuth {
                    dismiss()
                }
            }
        }
    }
}
