//
//  FavorisView.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
import SwiftUI
 
struct FavorisView: View {
    @ObservedObject var viewModel = FavorisViewModel()
    @ObservedObject var authViewModel: AuthViewModel
    @State private var selectedFilter: TransitFilter = .all
    @State private var showAuthSheet = false
    @State private var showAddStopSheet = false
    
    
    enum TransitFilter: String, CaseIterable {
        case all = "All", bus = "Bus", metro = "Metro", tram = "Tram"
    }
    
    var body: some View {
        VStack(alignment: .leading) {
            // 🔵 Titre
            Text("Favourite stops")
                .font(.title2)
                .fontWeight(.bold)
                .padding(.top, 24)
                .padding(.horizontal, 24)
            
            // 🚫 Si l'utilisateur n'est pas connecté
            if !authViewModel.isAuthenticated {
                Spacer()
                VStack(spacing: 16) {
                    Text("Veuillez vous connecter pour enregistrer vos arrêts favoris.")
                        .font(.body)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                    
                    Button(action: {
                        showAuthSheet = true
                    }) {
                        HStack {
                            Image(systemName: "person.crop.circle.badge.plus")
                            Text("S'inscrire ou se connecter")
                                .fontWeight(.semibold)
                        }
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color(hex: "#4557A1"))
                        .cornerRadius(12)
                        .padding(.horizontal, 24)
                    }
                }
                Spacer()
            } else {
                
                // 🔘 Filtres
                HStack(spacing: 12) {
                    ForEach(TransitFilter.allCases, id: \.self) { filter in
                        let isSelected = filter == selectedFilter
                        Button(action: {
                            selectedFilter = filter
                        }) {
                            VStack(spacing: 6) {
                                Image(systemName: iconName(for: filter))
                                    .font(.system(size: 16, weight: .semibold))
                                Text(filter.rawValue)
                                    .font(.system(size: 14, weight: .semibold))
                            }
                            .foregroundColor(Color(hex: "#4557A1"))
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .frame(minWidth: 72)
                            .background(
                                RoundedRectangle(cornerRadius: 16)
                                    .fill(isSelected ? Color(hex: "#F18F5D").opacity(0.37) : Color(hex: "#FAFAFD"))
                            )
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 8)
                
                
                if viewModel.favoris.isEmpty {
                    Spacer()
                    
                    VStack(spacing: 16) {
                        Text("Vous n'avez pas encore d'arrêt en favori.")
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 32)
                        
                        Button(action: {
                            // 👉 Action à définir (ex: rediriger vers la carte)
                        }) {
                            Button(action: {
                                showAddStopSheet = true
                            }) {
                                HStack(spacing: 8) {
                                    Text("Add new stop")
                                        .fontWeight(.semibold)
                                        .foregroundColor(.black)
                                    Image(systemName: "plus.square")
                                        .font(.title3)
                                        .foregroundColor(Color(hex: "#4557A1"))
                                }
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                            .sheet(isPresented: $showAddStopSheet) {
                                AjouterFavoriSheet(
                                    showSheet: $showAddStopSheet,
                                    authViewModel: authViewModel,
                                    onUpdateFavoris: {
                                        if let userId = authViewModel.user?._id,
                                           let token = authViewModel.token {
                                            viewModel.fetchFavoris(for: userId, token: token)
                                        }
                                    }
                                )
                                
                            }
                            
                            
                            
                            .padding(.vertical, 12)
                            .padding(.horizontal, 20)
                            .background(Color.white)
                            .cornerRadius(12)
                            .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                        }
                    }
                    Spacer()
                } else {
                    ScrollView {
                        VStack(spacing: 16) {
                            ForEach(filteredHaltes) { halte in
                                FavorisHalteRow(halte: halte)
                            }
                            
                            // ✅ Bouton "Add new stop" en bas
                            Button(action: {
                                // 👉 Action à définir (ex: rediriger vers la carte)
                            }) {
                                Button(action: {
                                    showAddStopSheet = true
                                }) {
                                    HStack(spacing: 8) {
                                        Text("Add new stop")
                                            .fontWeight(.semibold)
                                            .foregroundColor(.black)
                                        Image(systemName: "plus.square")
                                            .font(.title3)
                                            .foregroundColor(Color(hex: "#4557A1"))
                                    }
                                    .padding(.vertical, 12)
                                    .padding(.horizontal, 20)
                                    .background(Color.white)
                                    .cornerRadius(12)
                                    .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                                }
                                .sheet(isPresented: $showAddStopSheet) {
                                    AjouterFavoriSheet(
                                        showSheet: $showAddStopSheet,
                                        authViewModel: authViewModel,
                                        onUpdateFavoris: {
                                            if let userId = authViewModel.user?._id,
                                               let token = authViewModel.token {
                                                viewModel.fetchFavoris(for: userId, token: token)
                                            }
                                        }
                                    )
                                }
                                
                                
                                
                                
                                
                                .padding(.vertical, 12)
                                .padding(.horizontal, 20)
                                .background(Color.white)
                                .cornerRadius(12)
                                .shadow(color: Color.black.opacity(0.05), radius: 4, x: 0, y: 2)
                            }
                            .padding(.top, 12)
                        }
                        .padding(.horizontal, 24)
                        .padding(.bottom, 40)
                    }
                }
                
                if viewModel.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity)
                        .padding()
                }
                
                if let error = viewModel.errorMessage {
                    Text("Erreur: \(error)")
                        .foregroundColor(.red)
                        .padding()
                }
            }
            
        }
        // ✅ Ces modificateurs doivent être appliqués ici, pas dans un if/else
        .onAppear {
            if let userId = authViewModel.user?._id,
               let token = authViewModel.token,
               authViewModel.isAuthenticated {
                viewModel.fetchFavoris(for: userId, token: token)
            }
        }
        
        .sheet(isPresented: $showAuthSheet) {
            AuthOptionsView(authVM: authViewModel)
        }
    }
    
    var filteredHaltes: [HalteModel] {
        switch selectedFilter {
        case .all:
            return viewModel.favoris
        case .bus:
            return viewModel.favoris.filter { $0.typeTransport.contains("Bus") }
        case .metro:
            return viewModel.favoris.filter { $0.typeTransport.contains("Metro") || ["1", "2", "5", "6"].contains(where: $0.lignesDesservies.contains) }
        case .tram:
            return viewModel.favoris.filter { $0.typeTransport.contains("Tram") }
        }
    }
    
    func iconName(for mode: TransitFilter) -> String {
        switch mode {
        case .all: return "star"
        case .bus: return "bus"
        case .metro, .tram: return "tram.fill"
        }
    }
}
