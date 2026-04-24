import SwiftUI

struct OnboardingView: View {
    @ScaledMetric(relativeTo: .body) private var lineChipHeight: CGFloat = AppTheme.ButtonHeight.secondary
    @ScaledMetric(relativeTo: .body) private var inputHeight: CGFloat = AppTheme.ButtonHeight.primary
    @State private var selectedLines: Set<String> = Set(OnboardingPreferenceStore.load().favoriteLines)
    @State private var homeLabel = OnboardingPreferenceStore.load().homeLabel
    @State private var departureTime = OnboardingPreferenceStore.load().departureTime
    var onFinish: () -> Void = {}

    private let suggestedLines = ["1", "2", "3", "4", "5", "6", "7", "8", "9", "10", "12", "19", "25", "38", "46", "71", "81", "92", "95"]

    private var canContinue: Bool {
        !selectedLines.isEmpty || !homeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        ZStack {
            AppTheme.Colors.onboardingBackground.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    favoriteLinesSection
                    homeSection
                    departureSection
                    footerNote
                    continueButton
                }
                .padding(.horizontal, 24)
                .padding(.top, 56)
                .padding(.bottom, 32)
            }
        }
        .preferredColorScheme(.dark)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Rends StibAlert utile dès demain")
                .font(.custom("DelaGothicOne-Regular", size: 28))
                .foregroundStyle(AppTheme.Colors.onboardingTitleSand)

            Text("Choisis 2 à 3 lignes que tu prends souvent et ton point de départ habituel. Stibi pourra ensuite te prévenir avant ton départ.")
                .font(.custom("Montserrat-Regular", size: 15))
                .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var favoriteLinesSection: some View {
        onboardingCard(title: "Tes lignes du quotidien", subtitle: "Sélectionne les lignes que tu veux surveiller.") {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 60), spacing: 10)], spacing: 10) {
                ForEach(suggestedLines, id: \.self) { line in
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
                            .frame(height: lineChipHeight)
                            .background(isSelected ? AppTheme.Colors.onboardingTitleSand : Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Ligne \(line)")
                    .accessibilityValue(isSelected ? "Sélectionnée" : "Non sélectionnée")
                    .accessibilityHint("Double-tape pour \(isSelected ? "retirer" : "ajouter") cette ligne favorite")
                }
            }
        }
    }

    private var homeSection: some View {
        onboardingCard(title: "Ton arrêt domicile", subtitle: "Exemple : De Brouckère, Simonis, Ma Campagne.") {
            TextField("Nom de l'arrêt ou zone", text: $homeLabel)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: inputHeight)
                .background(AppTheme.Palette.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                .accessibilityLabel("Arrêt domicile")
        }
    }

    private var departureSection: some View {
        onboardingCard(title: "Heure habituelle", subtitle: "Pour recevoir le brief du matin au bon moment.") {
            TextField("08:15", text: $departureTime)
                .keyboardType(.numbersAndPunctuation)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(.white)
                .padding(.horizontal, 14)
                .frame(height: inputHeight)
                .background(AppTheme.Palette.surfaceMuted)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                .accessibilityLabel("Heure habituelle de départ")
        }
    }

    private var footerNote: some View {
        Text("Tu pourras ajuster tout ça plus tard dans le profil. Le plus important est de donner à Stibi assez de contexte pour surveiller ce qui compte.")
            .font(.custom("Montserrat-Regular", size: 13))
            .foregroundStyle(Color.white.opacity(0.65))
            .fixedSize(horizontal: false, vertical: true)
    }

    private var continueButton: some View {
        Button(action: finishOnboarding) {
            Text("Continuer")
                .font(DesignSystem.Typography.bodyStrong)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: inputHeight)
                .background(canContinue ? AppTheme.Colors.onboardingTitleSand : Color.white.opacity(0.16))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
        .accessibilityHint("Enregistre tes préférences et ouvre l’application")
    }

    private func onboardingCard<Content: View>(
        title: String,
        subtitle: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(.white)

                Text(subtitle)
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(Color.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
            }

            content()
        }
        .padding(18)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
    }

    private func finishOnboarding() {
        let normalizedTime = departureTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "08:15" : departureTime
        let preferences = OnboardingPreferences(
            favoriteLines: selectedLines.sorted(),
            homeLabel: homeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            departureTime: normalizedTime
        )
        OnboardingPreferenceStore.save(preferences)
        AppHaptics.success()
        onFinish()
    }
}
