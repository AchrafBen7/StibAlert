//
//  SplashView.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var animateLights = false
    @StateObject private var meldingenVM = MeldingenViewModel()

    var body: some View {
        NavigationStack {
            ZStack {
                if isActive {
                    AppRoot()
                        .transition(.opacity)
                        .navigationBarBackButtonHidden(true)
                } else {
                    splashArtwork
                        .transition(.opacity)
                }
            }
            .onAppear {
                startupTasks()
            }
        }
    }

    private var splashArtwork: some View {
        GeometryReader { proxy in
            let size = proxy.size
            let referenceWidth: CGFloat = 506
            let referenceHeight: CGFloat = 1096
            let titleLeading = size.width * (73 / referenceWidth)
            let titleTop = size.height * (352 / referenceHeight)
            let bottomGlowX = size.width * ((268.52 + (211.74203491210938 / 2)) / referenceWidth)
            let bottomGlowY = size.height * ((737.34 + (177.65673828125 / 2)) / referenceHeight)

            ZStack {
                Color(hex: "#0B111E")
                    .ignoresSafeArea()

                Circle()
                    .fill(Color(hexRGB: "#CBD4DF", alpha: 0.89))
                    .frame(width: size.width * 1.22, height: size.width * 1.22)
                    .blur(radius: 120)
                    .offset(x: -size.width * 0.48, y: -size.height * 0.29)
                    .scaleEffect(animateLights ? 1.04 : 0.96)
                    .opacity(animateLights ? 1 : 0.9)

                Circle()
                    .fill(Color(hexRGB: "#CBD4DF", alpha: 0.28))
                    .frame(width: 108, height: 108)
                    .blur(radius: 36)
                    .offset(x: -size.width * 0.35, y: size.height * 0.15)
                    .opacity(animateLights ? 0.55 : 0.35)

                Ellipse()
                    .fill(Color(hexRGB: "#E4DED3", alpha: 0.72))
                    .frame(width: 211.74, height: 177.66)
                    .blur(radius: 100)
                    .position(x: bottomGlowX, y: bottomGlowY)
                    .scaleEffect(animateLights ? 1.06 : 0.94)
                    .opacity(animateLights ? 0.95 : 0.82)

                Ellipse()
                    .fill(
                        LinearGradient(
                            colors: [
                                Color(hexRGB: "#AFC4FF", alpha: 0.88),
                                Color(hexRGB: "#CBD4DF", alpha: 0.68)
                            ],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: size.width * 0.94, height: size.height * 0.36)
                    .blur(radius: 85)
                    .offset(x: size.width * 0.22, y: size.height * 0.39)
                    .opacity(animateLights ? 0.78 : 0.64)

                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 0) {
                        Text("Stib")
                            .foregroundStyle(Color(hex: "#C7D7FF"))
                        Text("Alert")
                            .foregroundStyle(Color(hex: "#E1D4BC"))
                    }
                    .font(AppTheme.Fonts.clash(64))
                    .fontWeight(.medium)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)

                    Text(L10n.Splash.subtitle)
                        .font(.system(size: 20, weight: .regular, design: .rounded))
                        .foregroundStyle(Color.white.opacity(0.92))
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.leading, titleLeading)
                .padding(.top, titleTop)
            }
            .compositingGroup()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Splash.accessibilityLogo)
    }

    private func startupTasks() {
        withAnimation(.easeInOut(duration: 2.2).repeatForever(autoreverses: true)) {
            animateLights = true
        }

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
