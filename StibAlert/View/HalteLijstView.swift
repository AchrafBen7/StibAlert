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
        List(viewModel.arrets, id: \.id) { halte in
            NavigationLink(destination: HalteDetailView(halte: halte)) {
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

