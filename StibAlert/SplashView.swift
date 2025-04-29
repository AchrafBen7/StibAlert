//
//  SplashView.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var showLogo = false

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
    }

    private func startupTasks() {
        let _ = FirstLaunchManager.checkFirstLaunch() // Tu peux utiliser cette ligne si tu veux faire un fetch ici.

        showLogo = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isActive = true
            }
        }
    }
}
