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

            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Text("BRUXELLES · STIB-MIVB · 2026")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(DS.Color.inkMute)
                    Spacer()
                    Text("ÉDITION D'OUVERTURE")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.5)
                        .foregroundStyle(DS.Color.inkMute)
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 10)

                DS.Rule(thick: true)
                    .padding(.horizontal, 20)

                Spacer(minLength: 36)

                VStack(alignment: .leading, spacing: 18) {
                    Text("№ 000 · LECTURE DU RÉSEAU")
                        .font(DS.Font.mono.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(DS.Color.primary)

                    (
                        Text(AppLocalizer.string("splash.hero.brussels_line"))
                            .foregroundStyle(DS.Color.ink)
                        + Text("en route.")
                            .font(.system(size: 42, weight: .bold, design: .serif))
                            .italic()
                            .foregroundStyle(DS.Color.primary)
                    )
                    .font(.system(size: 42, weight: .bold))
                    .tracking(-1.4)
                    .lineSpacing(-2)

                    Text("Temps réel, lignes utiles et lecture claire du réseau, dès l’ouverture.")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Color.inkSoft)
                        .frame(maxWidth: 290, alignment: .leading)

                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .fill(DS.Color.primary.opacity(0.15))
                            Image(systemName: "tram.fill")
                                .font(.system(size: 28, weight: .semibold))
                                .foregroundStyle(DS.Color.primary)
                        }
                        .frame(width: 88, height: 88)
                        .shadow(color: DS.Color.ink.opacity(0.08), radius: 10, y: 5)
                        .scaleEffect(reveal ? 1 : 0.9)

                        VStack(alignment: .leading, spacing: 6) {
                            Text("StibAlert")
                                .font(DS.Font.displayH3)
                                .foregroundStyle(DS.Color.ink)
                            Text("Le réseau en clair, pour de vrai.")
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(DS.Color.inkMute)
                            Text("Chargement en cours")
                                .font(DS.Font.monoSmall.weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(DS.Color.primary)
                        }
                    }
                    .padding(14)
                    .background(DS.Color.paper.opacity(0.96))
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
                    )
                }
                .padding(.horizontal, 20)

                Spacer()

                VStack(alignment: .leading, spacing: 10) {
                    DS.Rule()
                    Text(L10n.Splash.subtitle)
                        .font(.system(size: 13.5))
                        .foregroundStyle(DS.Color.inkSoft)
                        .frame(maxWidth: 320, alignment: .leading)
                    // App Store : disclaimer obligatoire — Apple peut rejeter
                    // une app qui s'affiche comme officielle d'un opérateur
                    // sans accord. On le met dès le splash + dans Profile/
                    // Confidentialité (section À propos).
                    Text("Application indépendante non affiliée à STIB-MIVB, SNCB, De Lijn ou TEC.")
                        .font(.system(size: 10.5, weight: .medium))
                        .tracking(0.2)
                        .foregroundStyle(DS.Color.inkMute)
                        .frame(maxWidth: 320, alignment: .leading)
                        .padding(.top, 2)
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 34)
                .opacity(reveal ? 1 : 0.7)
            }
        }
        .modifier(PaperGrainBackground())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L10n.Splash.accessibilityLogo)
    }

    private func startupTasks() {
        withAnimation(.easeInOut(duration: 0.6)) {
            reveal = true
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            withAnimation {
                isActive = true
            }
        }
    }
}
