//
//  PerturbationLigneView.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

import SwiftUI


struct PerturbationLigneView: View {
    let lineID: String
    @StateObject private var viewModel = PerturbationLigneViewModel()

    var body: some View {
        VStack {
            if viewModel.isLoading {
                ProgressView("Chargement...")
            } else if let error = viewModel.error {
                Text("❌ \(error)").foregroundColor(.red)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Résumé")
                            .font(.title2)
                            .bold()
                        Text(viewModel.resume)

                        Divider()

                        ForEach(viewModel.signalements) { signalement in
                            SignalementCardView(signalement: signalement)
                                .padding()
                                .background(Color(.systemGray6))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
            }
        }
        .navigationTitle("Perturbations Ligne \(lineID)")
        .onAppear {
            viewModel.fetchPerturbations(for: lineID)
        }
    }
}

