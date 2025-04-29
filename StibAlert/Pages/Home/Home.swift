//
//  Home.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.

import SwiftUI

struct Home: View {
    // On se base sur le AuthViewModel pour l’état de connexion
    @StateObject var authViewModel = AuthViewModel()
    @State var selectedTab = 0
    @State private var showAuthSheet = false  // Pour présenter le flux d'authentification
    
    // ViewModel pour récupérer les signalements dynamiques
    @StateObject private var meldingenVM = MeldingenViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#FAFAFD").ignoresSafeArea()
                
                VStack(spacing: 0) {
                    // ----- OFFLINE BANNER -----
                    if !networkMonitor.isConnected {
                        OfflineBanner()
                    }
                    // ----- TOP BAR -----
                    if selectedTab != 1 && selectedTab != 2 && selectedTab != 3 {
                        topBar
                    }
                    
                    
                    // ----- CONTENU DYNAMIQUE -----
                    Group {
                        switch selectedTab {
                        case 0:
                            normalHomeContent
                        case 1:
                            // Ici, on affiche la vue de transit/carte.
                            TransitMapView()  // Remplacez ou adaptez cette vue selon vos besoins.
                        case 2:
                            NewMeldingView()
                        case 3:
                            // Placeholder pour le quatrième onglet (par exemple "Favoris")
                            FavorisView(authViewModel: authViewModel)
                            
                        default:
                            normalHomeContent
                        }
                    }
                    .animation(.easeInOut, value: selectedTab)
                    
                    Spacer(minLength: 0)
                    
                    // ----- TAB BAR -----
                    CustomTabBar(selectedTab: $selectedTab)
                        .frame(height: 60)
                }
            }
            .onAppear {
                meldingenVM.fetchMeldingen()
            }
            .onChange(of: networkMonitor.isConnected) { connected in
                if connected {
                    print("[DEBUG] ✅ Connexion rétablie : rechargement automatique des données")
                    meldingenVM.fetchMeldingen()
                }
            }

            .navigationBarHidden(true)
        }
        .sheet(isPresented: $showAuthSheet) {
            AuthOptionsView(authVM: authViewModel)
        }
    }
    
    // MARK: - Sous-vues
    
    private var topBar: some View {
        HStack {
            // Bouton profil dynamique
            if authViewModel.isAuthenticated, let user = authViewModel.user {
                NavigationLink {
                    ProfilView(authViewModel: authViewModel)
                } label: {
                    // Affiche la première lettre du nom de l'utilisateur en rond
                    if let firstChar = user.nom.first {
                        Text(String(firstChar))
                            .font(.system(size: 16, weight: .bold))
                            .foregroundColor(.white)
                            .frame(width: 36, height: 36)
                            .background(Color.blue)
                            .clipShape(Circle())
                            .overlay(
                                Circle().stroke(Color(hex: "#ECECEC"), lineWidth: 1)
                            )
                    } else {
                        Image(systemName: "person.fill")
                            .resizable()
                            .frame(width: 24, height: 24)
                            .foregroundColor(.blue)
                    }
                }
            } else {
                // Bouton qui ouvre la feuille d'authentification
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
    }
    
    private var normalHomeContent: some View {
        VStack {
            // Banniere dynamique
            MobibCardView(authViewModel: authViewModel)
            
                .frame(height: 200)
                .padding(.horizontal, 24)
                .padding(.top, 40)
            
            Spacer(minLength: 20)
            
            // Section "Latest reports" avec filtre
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
            
            // Grille des signalements
            let validMeldingen = meldingenVM.meldingen
                .filter { Date().timeIntervalSince($0.dateSignalement) <= (24 * 60 * 60) }
                .sorted { $0.dateSignalement > $1.dateSignalement }
            
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
                            NavigationLink(
                                destination: MeldingDetailView(
                                    arretId: signalement.arretId._id,
                                    signalementId: signalement._id
                                )
                            ) {
                                MeldingenCardView(signalement: signalement)
                                    .frame(height: 150)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 16)
                }
                .refreshable {
                    meldingenVM.fetchMeldingen()
                }
            }
            Spacer()
        }
    }
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Home()
    }
}
