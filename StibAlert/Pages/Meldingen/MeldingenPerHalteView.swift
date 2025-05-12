//
//  MeldingenPerHalteView.swift
//  StibAlert
//
//  Created by studentehb on 12/05/2025.
//
import SwiftUI

struct MeldingenPerHalteView: View {
    let halte: HalteModel
    @StateObject private var meldingVM = MeldingHalteViewModel()
    
    var body: some View {
        VStack(alignment: .leading) {
            HStack(spacing: 12) {
                Text(halte.lignesDesservies.first ?? "?") // Numéro de ligne
                    .font(.system(size: 14, weight: .bold))
                    .foregroundColor(.white)
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(LineColors.color(for: halte.lignesDesservies.first ?? ""))
                    .cornerRadius(8)
                
                Text(halte.nom)
                    .font(.title2)
                    .fontWeight(.bold)
                    .foregroundColor(.primary)
                
                Spacer()
            }
            .padding(.horizontal)
            .padding(.top)
            
            if meldingVM.signalements.isEmpty {
                Text("Aucun signalement pour cet arrêt.")
                    .foregroundColor(.gray)
                    .padding()
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(meldingVM.signalements) { melding in
                            ArretSignalementCardView(signalement: melding)
                                .frame(height: 150)
                        }
                    }
                    .padding(.horizontal)
                }
            }
            
            Spacer()
        }
      
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            meldingVM.fetchMeldingen(voor: halte._id)
        }
    }
}
