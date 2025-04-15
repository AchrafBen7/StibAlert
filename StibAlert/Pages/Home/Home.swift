//
//  Home.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
//
//  Home.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct Home: View {
    // Suppression de l'état local "isLoggedIn" car nous nous reposons sur AuthViewModel
    @StateObject var authViewModel = AuthViewModel()
    @State var selectedTab = 0
    @State private var showAuthSheet = false  // Pour présenter le flux d'authentification
    
    // ViewModel pour récupérer les signalements dynamiques
    @StateObject private var meldingenVM = MeldingenViewModel()
    
    var body: some View {
        NavigationView {
            ZStack {
                // Fond
                Color(hex: "#FAFAFD").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ----- TOP BAR -----
                    HStack {
                        // Bouton profil dynamique
                        if authViewModel.isAuthenticated, authViewModel.user != nil {
                            // Si connecté, NavigationLink vers ProfilView
                            NavigationLink {
                                ProfilView(authViewModel: authViewModel)
                            } label: {
                                // Exemple avec une image système, vous pouvez personnaliser en utilisant authViewModel.user si vous avez une image
                                Image(systemName: "person.fill")
                                    .resizable()
                                    .frame(width: 24, height: 24)
                                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                                            .stroke(Color(hex: "#ECECEC"), lineWidth: 1)
                                    )
                            }
                        } else {
                            // Si non connecté, affiche un bouton qui ouvre la feuille d'authentification
                            Button {
                                showAuthSheet = true
                            } label: {
                                Image(systemName: "person.fill")
                                    .font(.system(size: 24))
                                    .foregroundColor(.gray)
                            }
                        }
                        
                        Spacer()
                        
                        Text("Hey, \(authViewModel.user?.nom ?? "Invité")")
                            .font(.subheadline)
                            .fontWeight(.semibold)
                        
                        Spacer()
                        
                        Button {
                            // Action de notification
                        } label: {
                            Image(systemName: "bell")
                                .font(.title3)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 8)
                    
                    // ----- BANNIÈRE DYNAMIQUE -----
                    TransitBannerView()
                        .frame(height: 200)
                        .padding(.horizontal, 24)
                        .padding(.top, 8)
                    
                    Spacer(minLength: 20)
                    
                    // ----- LATEST REPORTS + FILTRE -----
                    HStack {
                        Text("Latest reports")
                            .font(.headline)
                        Spacer()
                        Button {
                            // Action de filtre
                        } label: {
                            Image(systemName: "line.3.horizontal.decrease.circle")
                                .font(.title3)
                                .foregroundColor(.orange)
                        }
                    }
                    .padding(.horizontal, 24)
                    
                    // Calcul des signalements valides (moins de 24 heures) triés par date décroissante
                    let validMeldingen = meldingenVM.meldingen
                        .filter { Date().timeIntervalSince($0.dateSignalement) <= (24 * 60 * 60) }
                        .sorted { $0.dateSignalement > $1.dateSignalement }
                    
                    // ----- GRILLE DYNAMIQUE -----
                    if validMeldingen.isEmpty {
                        if let error = meldingenVM.errorMessage {
                            Text("Error: \(error)")
                                .foregroundColor(.red)
                                .padding(.top, 40)
                        } else {
                            Text("Pas de signalement aujourd'hui.")
                                .foregroundColor(.gray)
                                .padding(.top, 40)
                        }
                        Spacer()
                    } else {
                        ScrollView {
                            LazyVGrid(
                                columns: [
                                    GridItem(.flexible(minimum: 180), spacing: 20),
                                    GridItem(.flexible(minimum: 180), spacing: 20)
                                ],
                                spacing: 20
                            ) {
                                ForEach(validMeldingen) { signalement in
                                    MeldingenCardView(signalement: signalement)
                                        .frame(height: 150)
                                }
                            }
                            .padding(.horizontal, 24)
                            .padding(.top, 16)
                        }
                    }
                    
                    Spacer()
                    
                    // ----- TAB BAR -----
                    CustomTabBar(selectedTab: $selectedTab)
                        .frame(height: 60)
                }
            }
            .onAppear {
                meldingenVM.fetchMeldingen()
            }
            .navigationBarHidden(true)
        }
        // Présentation modale pour l'authentification (connexion/inscription)
        .sheet(isPresented: $showAuthSheet) {
            AuthOptionsView(authVM: authViewModel)
        }
    }
}

// MARK: - PREVIEW
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Home()
    }
}
