//
//  AlternativesView.swift
//  StibAlert
//
//  Created by studentehb on 28/03/2025.
//

import SwiftUI

struct AlternativesView: View {
    let ligneID: String
    let arretID: String
    @StateObject private var viewModel = AlternativesViewModel()

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if viewModel.isLoading {
                ProgressView("Chargement...")
            } else if let error = viewModel.error {
                Text("❌ \(error)").foregroundColor(.red)
            } else {
                Text("Ligne affectée : \(viewModel.ligne)")
                    .font(.headline)
                Text("Arrêt : \(viewModel.arret)")
                    .font(.subheadline)

                HStack {
                    ForEach(viewModel.alternatives, id: \.self) { alt in
                        Text("🚋 \(alt)")
                            .padding(8)
                            .background(Color.blue.opacity(0.2))
                            .cornerRadius(8)
                    }
                }

                Divider()

                Text(viewModel.suggestion)
            }
        }
        .padding()
        .navigationTitle("Alternatives")
        .onAppear {
            viewModel.fetchAlternatives(for: ligneID, arretID: arretID)
        }
    }
}
