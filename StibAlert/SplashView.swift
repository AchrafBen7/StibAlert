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
        NavigationStack {
            ZStack {
                if isActive {
                    AppRoot()
                        .transition(.opacity)
                        .navigationBarBackButtonHidden(true)
                } else {
                    AppTheme.Colors.background.ignoresSafeArea()

                    VStack {
                        Spacer()

                        Image("logo")
                            .resizable()
                            .scaledToFit()
                            .frame(width: 180, height: 180)
                            .opacity(showLogo ? 1 : 0.4)
                            .animation(.easeIn(duration: 1), value: showLogo)
                            .accessibilityLabel(L10n.Splash.accessibilityLogo)

                        Spacer()
                    }
                }
            }
            .onAppear {
                startupTasks()
            }
        }
    }

    private func startupTasks() {
        showLogo = true

        if FirstLaunchManager.checkFirstLaunch() {
            meldingenVM.fetchMeldingen()
            UserDefaults.standard.set(Date(), forKey: AppStorageKeys.lastUpdateDate)
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isActive = true
            }
        }
    }
}
