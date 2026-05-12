import SwiftUI

struct OnboardingRoutineStep: View {
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = AppTheme.ButtonHeight.primary

    @State private var homeLabel: String = OnboardingPreferenceStore.load().homeLabel
    @State private var departureTime: Date = {
        let stored = OnboardingPreferenceStore.load().departureTime
        let parts = stored.split(separator: ":").map(String.init)
        var components = DateComponents()
        components.hour = Int(parts.first ?? "8") ?? 8
        components.minute = Int(parts.count > 1 ? parts[1] : "15") ?? 15
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
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    departureCard
                    homeCard
                    valueExplainer
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 180)
            }

            VStack(spacing: 10) {
                continueButton
                skipButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .background(
                LinearGradient(
                    colors: [DS.Color.background.opacity(0), DS.Color.background, DS.Color.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(DS.Color.background)
        .onTapGesture {
            homeFieldFocus = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("ÉTAPE 2 SUR 3")
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
            .frame(height: 140)
            .opacity(skipDeparture ? 0.3 : 1)
            .disabled(skipDeparture)

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

            Text("Tu pourras associer un vrai arrêt STIB plus tard dans Profil.")
                .font(DS.Font.monoSmall)
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

    private func bullet(_ text: String) -> some View {
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
            homeLabel: homeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
            departureTime: storedTime.isEmpty ? "08:15" : storedTime
        ))
    }
}
