//
//  SplashView.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.

import SwiftUI

struct SplashView: View {
    @State private var isActive = false
    @State private var reveal = false

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
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            // Bloc de marque centré verticalement — logo, nom (Dela Gothic),
            // tagline, puis une barre de chargement fine. Épuré, 100% DS,
            // aucune font serif (qui jurait avec l'identité Dela Gothic).
            VStack(spacing: 0) {
                Spacer()

                Image("BlayseLogo")
                    .resizable()
                    .scaledToFit()
                    .frame(width: 132, height: 132)
                    .shadow(color: DS.Color.primary.opacity(0.18), radius: 16, y: 8)
                    .scaleEffect(reveal ? 1 : 0.86)
                    .opacity(reveal ? 1 : 0)

                Text("Blayse")
                    .font(.custom("DelaGothicOne-Regular", size: 30, relativeTo: .largeTitle))
                    .foregroundStyle(DS.Color.ink)
                    .padding(.top, 20)
                    .opacity(reveal ? 1 : 0)

                Text("Le réseau bruxellois, en clair.")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Color.inkSoft)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
                    .opacity(reveal ? 1 : 0)

                // Barre de chargement fine et indéterminée.
                LoadingBar(active: reveal)
                    .frame(width: 132, height: 3)
                    .padding(.top, 30)

                Spacer()

                // Disclaimer obligatoire App Store (app non officielle).
                Text("Application indépendante non affiliée à STIB-MIVB, SNCB, De Lijn ou TEC.")
                    .font(.system(size: 10.5, weight: .medium))
                    .tracking(0.2)
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 300)
                    .padding(.horizontal, 24)
                    .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity)
        }
        .modifier(PaperGrainBackground())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Splash.accessibilityLogo)
    }

    private func startupTasks() {
        withAnimation(.easeOut(duration: 0.5)) {
            reveal = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isActive = true
            }
        }
    }
}

/// Barre de chargement fine et indéterminée : un segment orange qui balaie
/// le rail (gris papier) en boucle. Remplace le texte "Chargement en cours"
/// par un signal visuel propre, cohérent avec le DS.
private struct LoadingBar: View {
    let active: Bool
    @State private var slide = false

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            Capsule()
                .fill(DS.Color.ink.opacity(0.08))
                .overlay(alignment: .leading) {
                    Capsule()
                        .fill(DS.Color.primary)
                        .frame(width: width * 0.4)
                        .offset(x: slide ? width * 0.6 : -width * 0.4)
                }
                .clipShape(Capsule())
        }
        .onAppear {
            guard active else { return }
            withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: false)) {
                slide = true
            }
        }
    }
}
