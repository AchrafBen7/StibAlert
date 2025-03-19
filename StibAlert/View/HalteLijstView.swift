//
//  HalteLijstView.swift
//  StibAlert
//
//  Created by studentehb on 17/03/2025.
//

import SwiftUI

struct HalteLijstView: View {
    let lijn: LijnModel
    @StateObject private var viewModel = AlleHaltesViewModel()

    var body: some View {
        List {
            if let error = viewModel.errorMessage {
                Text("Erreur : \(error)")
                    .foregroundColor(.red)
            }
            ForEach(viewModel.arrets) { halte in
                VStack(alignment: .leading) {
                    Text(halte.nom)
                        .font(.headline)
                    Text(halte.stopId)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
        .navigationTitle("Arrêts Ligne \(lijn.lineid)")
        .onAppear {
            viewModel.fetchArrets(lineId: lijn.lineid)
        }
    }
}


