import SwiftUI

/// 3-cards swipeable tour montré une fois après l'onboarding pour expliquer
/// les 3 features principales (carte / signalement / voix). Remplace l'ancien
/// TipKit qui n'a jamais marché en TestFlight (popover white card vide).
///
/// Présenté en fullScreenCover par AppRoot quand
/// `!hasSeenFeatureTour && session.isSignedIn && !needsPrivacyConsent
///  && hasSeenOnboarding`. Le user peut skipper à tout moment ou aller
/// jusqu'à la 3e carte.
///
/// Réinitialisable depuis Profil → Aide pour rejouer.
struct FeatureTourView: View {
    var onFinish: () -> Void

    @State private var pageIndex = 0
    @State private var reveal = false

    // U2 — Tints alignés sur DS.Color (variantes dark adaptatives) au lieu
    // de hex fixes. info pour Carte (bleu), warning pour Signaler (orange),
    // danger pour Voix (rouge) — cohérent avec les statuses partout.
    private let pages: [TourPage] = [
        TourPage(
            symbol: "map.fill",
            symbolTint: DS.Color.info,
            eyebrow: "1 SUR 3 · CARTE",
            title: "Ta carte du réseau",
            description: "Tu vois en direct les arrêts proches, les vrais signalements de la communauté et les perturbations live des 4 opérateurs (STIB, SNCB, De Lijn, TEC).",
            bullets: [
                ("dot.radiowaves.left.and.right", "Perturbations live mises à jour toutes les minutes"),
                ("person.3.fill", "Signalements communauté en temps réel"),
                ("location.fill", "Arrêts autour de toi par GPS")
            ]
        ),
        TourPage(
            symbol: "plus.circle.fill",
            symbolTint: DS.Color.warning,
            eyebrow: "2 SUR 3 · SIGNALER",
            title: "Signale en 2 tap",
            description: "Tu vois un retard, une panne, un incident ? Préviens la communauté en 2 tap depuis le bouton « + » de la carte. Plus tu contribues, plus le réseau réagit vite.",
            bullets: [
                ("hand.tap.fill", "2 tap : type d'incident + ligne, c'est tout"),
                ("checkmark.seal.fill", "Confirmé automatiquement si d'autres signalent pareil"),
                ("bell.badge.fill", "Push envoyés aux gens sur la même ligne")
            ]
        ),
        TourPage(
            symbol: "waveform",
            symbolTint: DS.Color.danger,
            eyebrow: "3 SUR 3 · VOIX",
            title: "Hey Mobi, ton assistant",
            description: "Appuie sur le micro et demande ton trajet ou l'état du réseau à voix haute. Mobi te répond avec les vraies lignes STIB et te calcule le meilleur itinéraire.",
            bullets: [
                ("mic.fill", "Demande naturelle, en français"),
                ("tram.fill", "Réponses 100% transport en commun"),
                ("speaker.wave.2.fill", "Lecture à voix haute pendant que tu marches")
            ]
        )
    ]

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [DS.Color.background, DS.Color.paper2],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                // Skip top-right (toujours accessible)
                HStack {
                    Spacer()
                    Button(action: skip) {
                        Text("Passer")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Color.inkMute)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 8)
                            .background(DS.Color.paper)
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 12)

                // Pages
                TabView(selection: $pageIndex) {
                    ForEach(Array(pages.enumerated()), id: \.offset) { i, page in
                        cardView(page)
                            .tag(i)
                            .padding(.horizontal, 22)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .frame(maxHeight: .infinity)

                // Custom page indicator + CTA
                VStack(spacing: 18) {
                    HStack(spacing: 8) {
                        ForEach(0..<pages.count, id: \.self) { i in
                            Capsule()
                                .fill(pageIndex == i ? DS.Color.ink : DS.Color.ink.opacity(0.18))
                                .frame(width: pageIndex == i ? 24 : 7, height: 7)
                                .animation(.easeOut(duration: 0.25), value: pageIndex)
                        }
                    }

                    Button(action: next) {
                        HStack(spacing: 8) {
                            Text(pageIndex == pages.count - 1 ? "C'est parti !" : "Suivant")
                                .font(.system(size: 16, weight: .bold))
                            Image(systemName: pageIndex == pages.count - 1 ? "checkmark" : "arrow.right")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(DS.Color.primaryForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(DS.Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.ink, lineWidth: 1.5)
                        )
                    }
                    .buttonStyle(.plain)
                    .padding(.horizontal, 22)
                }
                .padding(.bottom, 30)
            }
        }
        .preferredColorScheme(.light)
        .onAppear {
            withAnimation(.easeOut(duration: 0.45)) { reveal = true }
        }
    }

    @ViewBuilder
    private func cardView(_ page: TourPage) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            Spacer(minLength: 12)

            ZStack {
                Circle()
                    .fill(page.symbolTint.opacity(0.18))
                    .frame(width: 110, height: 110)
                Image(systemName: page.symbol)
                    .font(.system(size: 52, weight: .heavy))
                    .foregroundStyle(page.symbolTint)
            }
            .frame(maxWidth: .infinity, alignment: .center)
            .scaleEffect(reveal ? 1.0 : 0.85)
            .opacity(reveal ? 1.0 : 0.0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7), value: reveal)

            VStack(alignment: .leading, spacing: 10) {
                Text(page.eyebrow)
                    .font(.system(size: 11, weight: .heavy, design: .monospaced))
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Text(page.title)
                    .font(.system(size: 28, weight: .black))
                    .tracking(-0.5)
                    .foregroundStyle(DS.Color.ink)
                Text(page.description)
                    .font(.system(size: 14.5, weight: .medium))
                    .lineSpacing(3)
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 10) {
                ForEach(Array(page.bullets.enumerated()), id: \.offset) { _, bullet in
                    HStack(spacing: 10) {
                        Image(systemName: bullet.0)
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(page.symbolTint)
                            .frame(width: 22)
                        Text(bullet.1)
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 12)
                    .background(DS.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
                    )
                }
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
    }

    private func next() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        if pageIndex < pages.count - 1 {
            withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) {
                pageIndex += 1
            }
        } else {
            finish()
        }
    }

    private func skip() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        finish()
    }

    private func finish() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // U3 — petit délai pour que le user perçoive le haptic et le tap du
        // bouton AVANT que le fullScreenCover ne disparaisse (sans ça la
        // dismission est instantanée + abrupte, le user a un flash sans
        // savoir pourquoi). 280 ms = pile dans la fenêtre perceptive.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 280_000_000)
            onFinish()
        }
    }
}

private struct TourPage {
    let symbol: String
    let symbolTint: Color
    let eyebrow: String
    let title: String
    let description: String
    let bullets: [(String, String)]
}
