//
//  LigneDetailView.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

import SwiftUI

struct LigneDetailView: View {
    let lineid: String

    var body: some View {
        VStack {
            Text("Détails de la ligne \(lineid)")
                .font(.largeTitle)
                .padding()

            // Tu peux ici afficher les arrêts, les perturbations, etc.
            // via un nouveau ViewModel avec `/api/lignes/:id/perturbations`
        }
        .navigationTitle("Ligne \(lineid)")
    }
}
