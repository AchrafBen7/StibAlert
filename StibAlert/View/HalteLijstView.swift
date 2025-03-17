//
//  HalteLijstView.swift
//  StibAlert
//
//  Created by studentehb on 17/03/2025.
//

import SwiftUI

struct HalteLijstView: View {
    let lijn: LijnModel
    
    var body: some View {
        VStack(spacing: 16) {
            Text("Vous avez sélectionné la ligne")
                .font(.headline)
            Text(lijn.nomComplet)
                .font(.title)
                .foregroundColor(.blue)
            Text("Ici, vous afficherez la liste des arrêts de cette ligne.")
                .font(.subheadline)
                .multilineTextAlignment(.center)
        }
        .padding()
        .navigationTitle("Arrêts de \(lijn.lineid)")
    }
}
