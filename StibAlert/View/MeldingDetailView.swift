//
//  MeldingDetailView.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.
//

import SwiftUI

struct MeldingDetailView: View {
    let arretId: String
    let signalementId: String
    @StateObject private var viewModel = MeldingDetailViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            if let signalement = viewModel.signalement {
                Text("Ligne: \(signalement.ligne)").bold()
                Text("Type: \(signalement.typeProbleme)")
                Text("Description: \(signalement.description)")
                if let photo = signalement.photo {
                    Text("Photo URL: \(photo)")
                }
                Text("Date: \(signalement.dateSignalement.formatted())")
                Text("Confiance: \(signalement.confiance)")
                Text("Votes + : \(signalement.votesPositifs)")
                Text("Votes - : \(signalement.votesNegatifs)")

                HStack {
                    Button("👍 Vote positif") {
                        viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: true)
                    }
                    .buttonStyle(.borderedProminent)

                    Button("👎 Vote négatif") {
                        viewModel.voteSignalement(arretId: arretId, signalementId: signalementId, isUp: false)
                    }
                    .buttonStyle(.bordered)
                }
                .padding(.top)
            } else if let errorMessage = viewModel.errorMessage {
                Text("Erreur : \(errorMessage)")
                    .foregroundColor(.red)
            } else {
                ProgressView("Chargement du signalement...")
            }
        }
        .padding()
        .navigationTitle("Détail Signalement")
        .onAppear {
            viewModel.fetchSignalement(arretId: arretId, signalementId: signalementId)
        }
    }
}
