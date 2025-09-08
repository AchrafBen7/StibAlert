//
//  Home.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.

import SwiftUI

struct Home: View {
   
    @StateObject var authViewModel = AuthViewModel()
    @State var selectedTab = 0
    @State private var showAuthSheet = false
    @State private var navigateToConnexion = false
    

    @StateObject private var meldingenVM = MeldingenViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared
    var body: some View {
        NavigationView {
            ZStack {
                Color(hex: "#FAFAFD").ignoresSafeArea()
                
                VStack(spacing: 0) {
          
                    if !networkMonitor.isConnected {
                        OfflineBanner()
                    }
                    
         
                    Group {
                        switch selectedTab {
                        case 0:
                            TransitMapView(
                                authViewModel: authViewModel,
                                navigateToConnexion: $navigateToConnexion
                            )
                        case 1:
                            AllReportsView()
                        case 2:
                            NewMeldingView()
                        case 3:
                            FavorisView(authViewModel: authViewModel)

                            
                        default:
                            normalHomeContent
                        }
                    }
                    .animation(.easeInOut, value: selectedTab)
                    
                    Spacer(minLength: 0)
                    
            
                    CustomTabBar(selectedTab: $selectedTab)
                        .frame(height: 60)
                }
            }
            .onAppear {
                meldingenVM.fetchMeldingen()
            }
            .onChange(of: networkMonitor.isConnected) { connected in
                if connected {
                    print("✅ Verbinding hersteld: automatische gegevensherlading")
                    meldingenVM.fetchMeldingen()
                }
            }
            
            .navigationBarHidden(true)
        }
        NavigationLink(
            destination: ConnexionView(authVM: authViewModel),
            isActive: $navigateToConnexion
        ) {
            EmptyView()
        }
        .hidden()
        
        
    }
    
    // MARK: - onder-views
    
    private var topBar: some View {
        HStack {
            if authViewModel.isAuthenticated, let user = authViewModel.user {
                // ✅ Cercle avec initiale
                NavigationLink(destination: ProfilView(authViewModel: authViewModel)) {
                    Text(String(user.nom.prefix(1)).uppercased())
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.white)
                        .frame(width: 32, height: 32)
                        .background(Color(hex: "#2D2C6F"))
                        .clipShape(Circle())
                }
            } else {
               
                Button {
                    navigateToConnexion = true
                } label: {
                    Image(systemName: "person")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.white)
                }
            }
            
            Spacer()
            
            Text("Hey, \(authViewModel.user?.nom ?? "Invité")")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.white)
                .lineLimit(1)
            
            Spacer()
            
            Button {
        
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 24))
                    .foregroundColor(.white)
            }
        }
        
        .frame(height: 60)
        .padding(.horizontal, 24)
        .background(Color(hex: "#3E3C7D"))
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    
    private var normalHomeContent: some View {
        VStack {
   
            Spacer(minLength: 20)
            
         
            HStack {
                Text("Latest reports")
                    .font(.title3)
                    .fontWeight(.semibold)
                
                Spacer()
                
                Button {
   
                } label: {
                    Image(systemName: "line.3.horizontal.decrease.circle.fill")
                        .foregroundColor(.black.opacity(0.5))
                        .font(.title3)
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            
    
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
                            GridItem(.flexible(), spacing: 16),
                            GridItem(.flexible(), spacing: 16)
                        ],
                        spacing: 16
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
                    
            
                    NavigationLink(destination: AllReportsView()) {
                        Text("Other reports")
                            .font(.system(size: 14, weight: .semibold))
                            .underline()
                            .foregroundColor(.black)
                    }
                    .padding(.top, 10)
                    .frame(maxWidth: .infinity, alignment: .center)
                }
                .refreshable {
                    meldingenVM.fetchMeldingen()
                }
            }
            
            Spacer()
        }
    }
    
    
    struct HomeView_Previews: PreviewProvider {
        static var previews: some View {
            Home()
        }
    }
}
