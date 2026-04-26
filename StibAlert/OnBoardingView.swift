import SwiftUI

// MARK: - Entry point

struct OnboardingView: View {
    @State private var step: OnboardingStep = .lines
    @State private var savedLines: [String] = []
    var onFinish: () -> Void = {}

    var body: some View {
        ZStack {
            AppTheme.Colors.onboardingBackground.ignoresSafeArea()
            switch step {
            case .lines:
                OnboardingLinesStep(
                    onContinue: { lines in
                        savedLines = lines
                        step = .push
                    },
                    onSkip: onFinish
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .push:
                OnboardingPushStep(
                    primaryLine: savedLines.first ?? "92",
                    onFinish: onFinish
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: step)
        .preferredColorScheme(.dark)
    }

    private enum OnboardingStep { case lines, push }
}

// MARK: - Step 1 — Lignes

private struct OnboardingLinesStep: View {
    @ScaledMetric(relativeTo: .body) private var chipHeight: CGFloat = AppTheme.ButtonHeight.secondary
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = AppTheme.ButtonHeight.primary

    @State private var selectedLines: Set<String> = Set(OnboardingPreferenceStore.load().favoriteLines)
    @State private var availableLines: [String] = [
        "1","2","3","4","5","6","7","8","9","10","12","19","25","38","46","71","81","92","95"
    ]
    @State private var isLoading = false

    let onContinue: ([String]) -> Void
    let onSkip: () -> Void

    private var canContinue: Bool { !selectedLines.isEmpty }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 28) {
                header
                linesCard
                continueButton
                skipButton
            }
            .padding(.horizontal, 24)
            .padding(.top, 64)
            .padding(.bottom, 40)
        }
        .task { await loadLines() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quelle ligne tu prends tous les jours ?")
                .font(.custom("DelaGothicOne-Regular", size: 26))
                .foregroundStyle(AppTheme.Colors.onboardingTitleSand)
                .fixedSize(horizontal: false, vertical: true)

            Text("Stibi surveille les perturbations en temps réel et te prévient avant que ça bloque ton trajet.")
                .font(.custom("Montserrat-Regular", size: 15))
                .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var linesCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Tes lignes")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(.white)
                Text("Jusqu'à 4 lignes · tu pourras en ajouter d'autres.")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.45))
            }

            if isLoading && availableLines.isEmpty {
                ProgressView()
                    .tint(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                    ForEach(availableLines, id: \.self) { line in
                        let isSelected = selectedLines.contains(line)
                        Button {
                            if isSelected {
                                selectedLines.remove(line)
                            } else if selectedLines.count < 4 {
                                selectedLines.insert(line)
                            }
                            AppHaptics.soft()
                        } label: {
                            Text(line)
                                .font(DesignSystem.Typography.title3)
                                .foregroundStyle(isSelected ? .black : .white)
                                .frame(maxWidth: .infinity)
                                .frame(height: chipHeight)
                                .background(
                                    isSelected
                                    ? AppTheme.Colors.onboardingTitleSand
                                    : Color.white.opacity(0.07)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ligne \(line)")
                        .accessibilityValue(isSelected ? "Sélectionnée" : "Non sélectionnée")
                    }
                }
            }
        }
        .padding(18)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
    }

    private var continueButton: some View {
        Button {
            saveLines()
            AppHaptics.success()
            onContinue(selectedLines.sorted())
        } label: {
            Text("Continuer")
                .font(DesignSystem.Typography.bodyStrong)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: buttonHeight)
                .background(
                    canContinue
                    ? AppTheme.Colors.onboardingTitleSand
                    : Color.white.opacity(0.16)
                )
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
    }

    private var skipButton: some View {
        Button {
            saveLines()
            onSkip()
        } label: {
            Text("Je découvre d'abord")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func saveLines() {
        let existing = OnboardingPreferenceStore.load()
        OnboardingPreferenceStore.save(OnboardingPreferences(
            favoriteLines: selectedLines.sorted(),
            homeLabel: existing.homeLabel,
            departureTime: existing.departureTime
        ))
    }

    @MainActor
    private func loadLines() async {
        guard AppConfig.isBackendEnabled else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            let lignes = try await LigneService.etatLignes()
            let ids = lignes
                .map(\.lineid)
                .filter { !$0.isEmpty }
                .sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
            if !ids.isEmpty {
                availableLines = ids
                selectedLines = selectedLines.filter { availableLines.contains($0) }
            }
        } catch {}
    }
}

// MARK: - Step 2 — Push permission

private struct OnboardingPushStep: View {
    let primaryLine: String
    let onFinish: () -> Void

    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = AppTheme.ButtonHeight.primary
    @State private var selectedScenario = 0
    @State private var notifAppeared = false
    @State private var isRequesting = false

    // MARK: Scénarios

    private struct NotifScenario: Identifiable {
        let id: Int
        let tabIcon: String
        let tabLabel: String
        let badgeColor: Color
        let emoji: String
        let body: String
    }

    private var scenarios: [NotifScenario] {
        [
            NotifScenario(
                id: 0,
                tabIcon: "exclamationmark.triangle.fill",
                tabLabel: "Alerte",
                badgeColor: Color(hex: "#FF6B3D"),
                emoji: "⚠️",
                body: "Incident à Ixelles — ligne \(primaryLine) perturbée dès 8h40. Envisage un départ avant 8h25."
            ),
            NotifScenario(
                id: 1,
                tabIcon: "checkmark.circle.fill",
                tabLabel: "Tout roule",
                badgeColor: Color(hex: "#73F0D2"),
                emoji: "✅",
                body: "Ligne \(primaryLine) · 8h07 — Trafic normal ce matin. Prochain tram dans 4 min. Bon trajet 👍"
            ),
            NotifScenario(
                id: 2,
                tabIcon: "clock.badge.fill",
                tabLabel: "Retard",
                badgeColor: Color(hex: "#B5CFF8"),
                emoji: "🕐",
                body: "Ligne \(primaryLine) retardée de 8 min. Prochain départ depuis ton arrêt dans 11 min."
            ),
        ]
    }

    // MARK: Trust signals

    private let trustSignals: [(icon: String, text: String)] = [
        ("clock.badge.checkmark.fill", "Seulement avant ton trajet, pas à 2h du matin"),
        ("bell.slash.fill",            "Silence complet si ta ligne tourne normalement"),
        ("lock.shield.fill",           "Données jamais partagées ni vendues"),
    ]

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 28) {
                    Spacer(minLength: 64).fixedSize()
                    pushHeader
                    notificationPreviewCard
                    trustSignalsCard
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }

            ctaArea
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.15)) {
                notifAppeared = true
            }
        }
    }

    // MARK: Header

    private var pushHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Stibi prévient.\nToi, tu prends le bon tram.")
                .font(.custom("DelaGothicOne-Regular", size: 26))
                .foregroundStyle(AppTheme.Colors.onboardingTitleSand)
                .fixedSize(horizontal: false, vertical: true)

            Text("Active les alertes pour être informé avant ton départ — pas après.")
                .font(.custom("Montserrat-Regular", size: 15))
                .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Notification preview

    private var notificationPreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Barre de titre style iOS
            iOSNotifHeader

            Divider()
                .background(Color.white.opacity(0.08))

            // Corps de la notif animé
            notifBody
                .padding(16)
                .offset(y: notifAppeared ? 0 : 16)
                .opacity(notifAppeared ? 1 : 0)

            Divider()
                .background(Color.white.opacity(0.06))

            // Onglets de scénarios
            scenarioTabs
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(Color(hex: "#0E1520"))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(
                    LinearGradient(
                        colors: [Color.white.opacity(0.18), Color.white.opacity(0.05)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ),
                    lineWidth: 1
                )
        )
        .shadow(color: .black.opacity(0.4), radius: 24, x: 0, y: 12)
    }

    private var iOSNotifHeader: some View {
        HStack(spacing: 8) {
            // App icon
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(AppTheme.Colors.onboardingTitleSand)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "tram.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(.black)
                )

            Text("STIBALERT")
                .font(.custom("Montserrat-SemiBold", size: 11))
                .foregroundStyle(Color.white.opacity(0.5))
                .kerning(0.6)

            Spacer()

            Text("maintenant")
                .font(.custom("Montserrat-Regular", size: 11))
                .foregroundStyle(Color.white.opacity(0.35))

            // Badge indicateur scénario
            Circle()
                .fill(scenarios[selectedScenario].badgeColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var notifBody: some View {
        let scenario = scenarios[selectedScenario]
        return HStack(alignment: .top, spacing: 12) {
            Text(scenario.emoji)
                .font(.system(size: 28))

            VStack(alignment: .leading, spacing: 4) {
                Text("Ligne \(primaryLine) · Perturbation réseau")
                    .font(.custom("Montserrat-SemiBold", size: 13))
                    .foregroundStyle(.white)

                Text(scenario.body)
                    .font(.custom("Montserrat-Regular", size: 13))
                    .foregroundStyle(Color.white.opacity(0.78))
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedScenario)
    }

    private var scenarioTabs: some View {
        HStack(spacing: 8) {
            ForEach(scenarios) { scenario in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selectedScenario = scenario.id
                    }
                    AppHaptics.soft()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: scenario.tabIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(scenario.tabLabel)
                            .font(.custom("Montserrat-SemiBold", size: 11))
                    }
                    .foregroundStyle(selectedScenario == scenario.id ? .black : Color.white.opacity(0.55))
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        selectedScenario == scenario.id
                        ? scenario.badgeColor
                        : Color.white.opacity(0.07)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Trust signals

    private var trustSignalsCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(trustSignals.enumerated()), id: \.offset) { index, signal in
                HStack(spacing: 14) {
                    Image(systemName: signal.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Colors.onboardingTitleSand.opacity(0.85))
                        .frame(width: 20)

                    Text(signal.text)
                        .font(.custom("Montserrat-Regular", size: 13))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.vertical, 14)
                .padding(.horizontal, 16)

                if index < trustSignals.count - 1 {
                    Divider()
                        .background(Color.white.opacity(0.06))
                        .padding(.leading, 50)
                }
            }
        }
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
    }

    // MARK: CTA

    private var ctaArea: some View {
        VStack(spacing: 0) {
            // Fade gradient pour indiquer que le contenu continue
            LinearGradient(
                colors: [AppTheme.Colors.onboardingBackground.opacity(0), AppTheme.Colors.onboardingBackground],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 32)
            .allowsHitTesting(false)

            VStack(spacing: 10) {
                authorizeButton
                dialogHint
                laterButton
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 40)
            .background(AppTheme.Colors.onboardingBackground)
        }
    }

    private var authorizeButton: some View {
        Button {
            isRequesting = true
            Task {
                await PushNotificationManager.current?.requestAuthorizationAndRegister()
                isRequesting = false
                onFinish()
            }
        } label: {
            ZStack {
                if isRequesting {
                    ProgressView().tint(.black)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Autoriser les notifications")
                            .font(DesignSystem.Typography.bodyStrong)
                    }
                    .foregroundStyle(.black)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(AppTheme.Colors.onboardingTitleSand)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
        .accessibilityLabel("Autoriser les notifications push")
        .accessibilityHint("Une fenêtre iOS va s'ouvrir pour confirmer")
    }

    private var dialogHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 10))
                .foregroundStyle(Color.white.opacity(0.28))
            Text("Une fenêtre iOS va s'ouvrir pour confirmer")
                .font(.custom("Montserrat-Regular", size: 11))
                .foregroundStyle(Color.white.opacity(0.28))
        }
        .frame(maxWidth: .infinity)
    }

    private var laterButton: some View {
        Button(action: onFinish) {
            Text("Plus tard")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(Color.white.opacity(0.38))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
