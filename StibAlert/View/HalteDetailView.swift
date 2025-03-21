//
//  MeldingHalteView.swift
//  StibAlert
//
//  Created by studentehb on 21/03/2025.
//import SwiftUI
import SwiftUI

struct HalteDetailView: View {
    let halte: HalteModel
    @StateObject private var viewModel = MeldingHalteViewModel()

    var body: some View {
        VStack {
            // Infos de l’arrêt
            VStack(alignment: .leading, spacing: 8) {
                Text(halte.nom).font(.title).bold()
                Text("Stop ID: \(halte.stopId)")
                // etc.
            }
            .padding()

            // Affichage du résumé
            if !viewModel.resume.isEmpty {
                Text("Résumé : \(viewModel.resume)")
                    .font(.subheadline)
                    .padding(.vertical, 8)
                    .foregroundColor(.purple)
            }

            // Liste des signalements
            List(viewModel.signalements) { signalement in
                VStack(alignment: .leading) {
                    Text("Ligne: \(signalement.ligne)")
                    Text("Type: \(signalement.typeProbleme)")
                    Text("Description: \(signalement.description)")
                    if let photo = signalement.photo {
                        Text("Photo: \(photo)")
                    }
                    Text("Date: \(signalement.date)")
                    Text("Arrêt: \(signalement.arret)")
                }
            }
        }
        .navigationTitle(halte.nom)
        .onAppear {
            // Utiliser l'_id ou tout identifiant correct
            viewModel.fetchMeldingen(voor: halte._id)
        }
    }
}
