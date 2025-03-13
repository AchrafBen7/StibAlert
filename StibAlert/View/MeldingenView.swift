//
//  MeldingenView.swift
//  StibAlert
//
//  Created by studentehb on 12/03/2025.
//

import SwiftUI

struct MeldingenView: View {
    @ObservedObject var viewModel = MeldingenViewModel()
    
    var body: some View {
        NavigationView {
            List {
                if let error = viewModel.errorMessage {
                    Text("Error : \(error)")
                        .foregroundColor(.red)
                } else {
                    ForEach(viewModel.meldingen) { melding in
                        VStack(alignment: .leading) {
                            Text("Arrêt : \(melding.arretId.nom)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                            Text("Lijn: \(melding.ligne)")
                                .font(.headline)
                            Text("Type: \(melding.typeProbleme)")
                                .font(.subheadline)
                            Text("Description: \(melding.description)")
                        
                                .font(.body)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
            .navigationTitle("Alle Meldingen")
            .onAppear {
                viewModel.fetchMeldingen()
            }
        }
    }
}

struct MeldingenView_Previews: PreviewProvider {
    static var previews: some View {
        MeldingenView()
    }
}
