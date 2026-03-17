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
        NavigationStack {
            ZStack {
                AppTheme.Colors.background.ignoresSafeArea()
                
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
                        .foregroundColor(AppTheme.Colors.textInverse)
                        .frame(width: 32, height: 32)
                        .background(AppTheme.Colors.primary)
                        .clipShape(Circle())
                }
            } else {
               
                Button {
                    navigateToConnexion = true
                } label: {
                    Image(systemName: "person")
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(AppTheme.Colors.textInverse)
                }
            }
            
            Spacer()
            
            Text(L10n.Home.greeting(authViewModel.user?.nom ?? L10n.Common.guestName))
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(AppTheme.Colors.textInverse)
                .lineLimit(1)
            
            Spacer()
            
            Button {
        
            } label: {
                Image(systemName: "bell")
                    .font(.system(size: 24))
                    .foregroundColor(AppTheme.Colors.textInverse)
            }
        }
        
        .frame(height: 60)
        .padding(.horizontal, 24)
        .background(AppTheme.Colors.primary)
        .cornerRadius(16)
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }
    
    
    private var normalHomeContent: some View {
        VStack {
   
            Spacer(minLength: 20)
            
         
            HStack {
                Text(L10n.Home.latestReports)
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
                    Text(L10n.Home.errorPrefix(error))
                        .foregroundColor(AppTheme.Colors.danger)
                        .padding(.top, 40)
                } else {
                    Text(L10n.Home.noReportsToday)
                        .foregroundColor(AppTheme.Colors.textSecondary)
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
                        Text(L10n.Home.otherReports)
                            .font(.system(size: 14, weight: .semibold))
                            .underline()
                            .foregroundColor(AppTheme.Colors.textPrimary)
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
