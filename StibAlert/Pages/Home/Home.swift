//
//  Home.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct Home: View {
    @State var isLoggedIn = true
    @State var userName = "Michael"
    @State var userProfileImage: Image? = Image(systemName: "person.fill")
    @State var selectedTab = 0

    // Utilisation du view model pour récupérer les signalements dynamiques
    @StateObject private var meldingenVM = MeldingenViewModel()

    var body: some View {
        ZStack {
            // Fond
            Color(hex: "#FAFAFD").ignoresSafeArea()

            VStack(spacing: 0) {
                // ----- TOP BAR -----
                HStack {
                    if isLoggedIn {
                        userProfileImage?
                            .resizable()
                            .scaledToFill()
                            .frame(width: 36, height: 36)
                            .clipShape(Circle())
                    } else {
                        Button("Se connecter") {}
                            .font(.caption2)
                            .padding(.vertical, 4)
                            .padding(.horizontal, 8)
                            .background(Color.gray.opacity(0.15))
                            .cornerRadius(6)
                    }

                    Spacer()

                    Text("Hey, \(userName)")
                        .font(.subheadline)
                        .fontWeight(.semibold)

                    Spacer()

                    Button {
                        // Notification
                    } label: {
                        Image(systemName: "bell")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                // ----- VUE DYNAMIQUE : Bannière ou autre élément visuel -----
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
                        // Action pour le filtre
                    } label: {
                        Image(systemName: "line.3.horizontal.decrease.circle")
                            .font(.title3)
                            .foregroundColor(.orange)
                    }
                }
                .padding(.horizontal, 24)

                // ----- GRILLE DYNAMIQUE -----
                if meldingenVM.meldingen.isEmpty {
                    // Affiche un message ou l'erreur si aucune donnée n'est reçue
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
                            ForEach(meldingenVM.meldingen) { signalement in
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
}


// MARK: - PREVIEW
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Home()
    }
}

