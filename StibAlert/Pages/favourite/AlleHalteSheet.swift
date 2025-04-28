//
//  AlleHalteSheet.swift
//  StibAlert
//
//  Created by studentehb on 28/04/2025.
//

import SwiftUI
struct AjouterFavoriSheet: View {
    @Binding var showSheet: Bool
    @ObservedObject var authViewModel: AuthViewModel
    var onUpdateFavoris: () -> Void // ✅ AJOUT ICI
    @StateObject private var viewModel = LijnenViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.lijnen, id: \.id) { ligne in
                        NavigationLink(
                            destination: HaltesParLigneView(
                                lineId: ligne.lineid,
                                authViewModel: authViewModel,
                                onUpdateFavoris: onUpdateFavoris,
                                onClose: { showSheet = false } // ✅ pour fermer la sheet
                            )
                        ) {
                            HStack(spacing: 12) {
                                // Badge avec le numéro
                                Text(ligne.lineid)
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(LineColors.color(for: ligne.lineid))
                                    .cornerRadius(10)
                                
                                // Infos ligne
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(ligne.nomComplet)
                                        .foregroundColor(.black)
                                        .font(.subheadline)
                                    if let retour = ligne.nomCompletRetour {
                                        Text(retour)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                            .padding(.horizontal)
                        }
                    }
                }
                .padding(.top, 12)
            }
            
            .navigationTitle("Choisir une ligne")
            .navigationBarItems(trailing: Button("Fermer") {
                showSheet = false
            })
            .onAppear {
                viewModel.fetchLijnen()
            }
        }
    }
}
