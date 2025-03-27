//
//  EtatsLignesView.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

import SwiftUI


struct EtatLignesView: View {
    @StateObject private var viewModel = LignesStatutViewModel()

    var body: some View {
        NavigationView {
            List {
                if viewModel.isLoading {
                    ProgressView("Chargement...")
                } else if let error = viewModel.errorMessage {
                    Text("Erreur: \(error)")
                        .foregroundColor(.red)
                } else {
                    ForEach(viewModel.statuts) { ligne in
                        NavigationLink(destination: LigneDetailView(lineid: ligne.lineid)) {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text("Ligne \(ligne.lineid)")
                                        .font(.headline)
                                    Text(ligne.nom)
                                        .font(.subheadline)
                                }
                                Spacer()
                                Text(ligne.statut)
                                    .foregroundColor(couleurPourStatut(ligne.statut))
                                    .bold()
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
            .navigationTitle("État des lignes")
            .onAppear {
                viewModel.fetchEtatLignes()
            }
        }
    }

    func couleurPourStatut(_ statut: String) -> Color {
        switch statut {
        case "Bloqué": return .red
        case "Perturbé": return .orange
        default: return .green
        }
    }
}

