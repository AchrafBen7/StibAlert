//
//  SplashView.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var animateLights = false

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
            let titleLeading: CGFloat = 30
            let titleTop = size.height * 0.66

            ZStack {
                Color(hex: "#0B111E")
                    .ignoresSafeArea()

                Ellipse()
                    .fill(AppTheme.Colors.onboardingGlowWhite)
                    .frame(width: 665, height: 289)
                    .blur(radius: 79.5)
                    .offset(x: -54, y: -size.height * 0.43)
                    .scaleEffect(animateLights ? 1.03 : 0.98)

                Ellipse()
                    .fill(AppTheme.Colors.onboardingGlowBlue)
                    .frame(width: 587.54, height: 507)
                    .blur(radius: 132.3)
                    .offset(x: 18, y: -size.height * 0.25)
                    .opacity(animateLights ? 0.95 : 0.82)
                    .scaleEffect(animateLights ? 1.05 : 0.98)

                Circle()
                    .fill(AppTheme.Colors.onboardingIndicatorBlue.opacity(0.34))
                    .frame(width: 72, height: 72)
                    .blur(radius: 40)
                    .offset(x: size.width * 0.45, y: size.height * 0.02)
                    .opacity(animateLights ? 0.78 : 0.52)

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: 0) {
                        Text("Stib")
                            .foregroundStyle(AppTheme.Colors.onboardingTitleBlue)
                        Text("Alert")
                            .foregroundStyle(AppTheme.Colors.onboardingTitleSand)
                    }
                    .font(AppTheme.Fonts.clash(32))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
                    .padding(.bottom, 14)

                    Text(L10n.Splash.subtitle)
                        .font(AppTheme.Fonts.body(16))
                        .foregroundStyle(AppTheme.Colors.textInverse)
                        .frame(width: 300, alignment: .leading)
                        .lineSpacing(1)
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

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isActive = true
            }
        }
    }
}
