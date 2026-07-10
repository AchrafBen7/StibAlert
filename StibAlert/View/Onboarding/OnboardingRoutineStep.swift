import SwiftUI

struct OnboardingRoutineStep: View {
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = AppTheme.ButtonHeight.primary

    @State private var homeLabel: String = OnboardingPreferenceStore.load().homeLabel
    @State private var departureTime: Date = {
        // B3 — validation stricte du format "HH:mm" lu depuis storage.
        // Avant : Int(parts.first ?? "8") ?? 8 acceptait toute string +
        // tombait en fallback "8h15" silencieux sur malformé. Désormais :
        // - exige deux composants séparés par ":"
        // - exige des heures dans [0..23] et minutes dans [0..59]
        // - tout autre cas → fallback explicite 8:15 (heure rush hour
        //   matin par défaut)
        let stored = OnboardingPreferenceStore.load().departureTime
        var components = DateComponents()
        components.hour = 8
        components.minute = 15
        let parts = stored.split(separator: ":").map(String.init)
        if parts.count == 2,
           let hour = Int(parts[0]), (0...23).contains(hour),
           let minute = Int(parts[1]), (0...59).contains(minute) {
            components.hour = hour
            components.minute = minute
        }
        return Calendar.current.date(from: components) ?? Date()
    }()
    @State private var skipDeparture: Bool = false
    @FocusState private var homeFieldFocus: Bool

    let onContinue: () -> Void
    let onSkip: () -> Void

    private var formattedTime: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: departureTime)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                header
                departureCard
                homeCard
                valueExplainer
            }
            .padding(.horizontal, 22)
            .padding(.top, 44)
            .padding(.bottom, 24)
        }
        // `safeAreaInset` RÉSERVE la hauteur du bloc de boutons : le contenu peut
        // défiler jusqu'au bout au lieu de passer dessous. Un ZStack + un dégradé
        // (l'ancienne version) laissait la dernière puce transparaître derrière le
        // bouton — on croyait à un chevauchement, c'en était un.
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(spacing: 10) {
                continueButton
                skipButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 14)
            .padding(.bottom, 12)
            .background(DS.Color.background)
        }
        .background(DS.Color.background)
        .onTapGesture {
            homeFieldFocus = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ÉTAPE 2 / 3")
                    .font(DS.Font.monoSmall)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("ROUTINE")
                    .font(DS.Font.monoSmall)
                    .tracking(2)
                    .foregroundStyle(DS.Color.primary)
            }

            VStack(alignment: .leading, spacing: 10) {
                Text("Ton trajet régulier.")
                    .font(DesignSystem.Typography.display)
                    .foregroundStyle(DS.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                Text("On peut t'envoyer un brief 15 min avant ton départ habituel. Si rien à signaler, silence.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DS.Color.inkSoft)
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var departureCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Heure de départ")
                    .font(DS.Font.monoSmall)
                    .tracking(1.8)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text(formattedTime)
                    .font(.custom("DelaGothicOne-Regular", size: 22))
                    .foregroundStyle(DS.Color.ink)
            }

            DatePicker(
                "",
                selection: $departureTime,
                displayedComponents: .hourAndMinute
            )
            .datePickerStyle(.wheel)
            .labelsHidden()
            .frame(maxWidth: .infinity)
            // La roue native mesure ~180 pt. Forcée à 140 SANS `clipped()`, elle
            // débordait : ses rangées grises se superposaient au libellé au-dessus et
            // au toggle en dessous. 150 pt laissent cinq rangées lisibles, et le clip
            // garde la carte « point de départ » au-dessus du bouton.
            .frame(height: 150)
            .clipped()
            // Le clip tranchait les rangées du haut et du bas en plein milieu. Le
            // masque les fait disparaître en fondu : la coupe devient voulue.
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.18),
                        .init(color: .black, location: 0.82),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .opacity(skipDeparture ? 0.3 : 1)
            .disabled(skipDeparture)

            DS.Rule()

            Toggle(isOn: $skipDeparture) {
                Text("Horaire variable — pas de brief programmé")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)
            }
            .toggleStyle(SwitchToggleStyle(tint: DS.Color.primary))
        }
        .padding(18)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }

    private var homeCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Ton point de départ")
                .font(DS.Font.monoSmall)
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.inkMute)

            HStack(spacing: 10) {
                Image(systemName: "house.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.primary)
                TextField("ex: Gallait, Maison, Schaerbeek", text: $homeLabel)
                    .focused($homeFieldFocus)
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DS.Color.ink)
                    .textInputAutocapitalization(.words)
                    .submitLabel(.done)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 14)
            .background(DS.Color.paper2.opacity(0.6))
            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(homeFieldFocus ? DS.Color.primary : DS.Color.border, lineWidth: homeFieldFocus ? 1.5 : 1)
            )

            // Pas de monospace : elle est réservée aux données temps réel.
            Text("Tu pourras associer un vrai arrêt STIB plus tard dans Profil.")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(18)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }

    private var valueExplainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Color.primary)
                Text("CE QUE ÇA DÉBLOQUE")
                    .font(DS.Font.monoSmall.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(DS.Color.primary)
            }

            VStack(alignment: .leading, spacing: 8) {
                bullet("Push 15 min avant ton départ (si perturbation)")
                bullet("Verdict auto à l'ouverture de l'app")
                bullet("Recommandation Plan B personnalisée")
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.primary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.2), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    /// `LocalizedStringKey`, pas `String` : `Text(uneStringVariable)` ne se localise
    /// jamais. Les trois puces restaient donc en français dans l'app en néerlandais.
    private func bullet(_ text: LocalizedStringKey) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "checkmark")
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(DS.Color.primary)
                .padding(.top, 3)
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var continueButton: some View {
        Button {
            persist()
            AppHaptics.success()
            onContinue()
        } label: {
            HStack(spacing: 10) {
                Text("Continuer")
                Image(systemName: "arrow.right")
            }
            .font(DesignSystem.Typography.bodyStrong)
            .foregroundStyle(DS.Color.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(DS.Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.95), lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
    }

    private var skipButton: some View {
        Button {
            persist()
            onSkip()
        } label: {
            Text("Passer cette étape")
                .font(DS.Font.mono)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func persist() {
        let existing = OnboardingPreferenceStore.load()
        let storedTime = skipDeparture ? "" : formattedTime
        OnboardingPreferenceStore.save(OnboardingPreferences(
            favoriteLines: existing.favoriteLines,
            stibFavoriteStopIds: existing.stibFavoriteStopIds,
            homeLabel: homeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            departureTime: storedTime.isEmpty ? "08:15" : storedTime
        ))
    }
}
