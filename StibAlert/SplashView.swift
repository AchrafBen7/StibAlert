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

    var body: some View {
        NavigationView {
            ZStack {
                if isActive {
                    Home()
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
        showLogo = true // ✅ Déclenche l’animation du logo

        let isFirstLaunch = FirstLaunchManager.checkFirstLaunch()

        if isFirstLaunch {
            print("[SplashView] 🎉 Premier lancement détecté.")

            meldingenVM.fetchMeldingen() // ✅ Sans closure
            UserDefaults.standard.set(Date(), forKey: "lastUpdateDate")
        }

        // Délai visuel
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                self.isActive = true
            }
        }
    }
}
