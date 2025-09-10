//
//  SplashView.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.
import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var showLogo = false
    @StateObject private var meldingenVM = MeldingenViewModel()
    
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false //

    var body: some View {
        NavigationView {
            ZStack {
                if isActive {
                    AppRoot() // ✅ on passe par le gate onboarding
                        .transition(.opacity)
                        .navigationBarBackButtonHidden(true)
                } else {
                    Color.white.ignoresSafeArea()

                    VStack {
                        Spacer()

                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .opacity(showLogo ? 1 : 0.4)
                            .animation(.easeIn(duration: 1), value: showLogo)

                        Spacer()
                    }
                }
            }
            .onAppear {
                startupTasks()
            }
        }
        .navigationViewStyle(StackNavigationViewStyle())
    }

    private func startupTasks() {
            showLogo = true

            // 🔧 DEV: forcer l’onboarding à s’afficher à chaque lancement
            hasSeenOnboarding = false    // ⬅️ enlève cette ligne quand c’est validé

            let isFirstLaunch = FirstLaunchManager.checkFirstLaunch()
            if isFirstLaunch {
                print("[SplashView] 🎉 Premier lancement détecté.")
                meldingenVM.fetchMeldingen()
                UserDefaults.standard.set(Date(), forKey: "lastUpdateDate")
            }

            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                withAnimation { self.isActive = true }
            }
        }
    }


