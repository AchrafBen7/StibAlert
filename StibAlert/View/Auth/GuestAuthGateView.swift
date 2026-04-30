import SwiftUI

struct GuestAuthGateView: View {
    let reason: GuestAuthReason
    let onSignIn: () -> Void
    let onSignUp: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(DS.Color.ink.opacity(0.14))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 24)

            ZStack {
                Circle()
                    .fill(DS.Color.paper2)
                    .frame(width: 76, height: 76)
                Image(systemName: reason.icon)
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(reason.gateAccent)
            }
            .padding(.bottom, 18)

            Text(reason.title)
                .font(DS.Font.displayH2)
                .foregroundStyle(DS.Color.ink)
                .multilineTextAlignment(.center)

            Text(reason.subtitle)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 28)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(reason.gateBenefits, id: \.title) { benefit in
                    HStack(spacing: 10) {
                        Image(systemName: benefit.icon)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(reason.gateAccent)
                            .frame(width: 16)
                        Text(benefit.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                        Spacer()
                    }
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .padding(.horizontal, 24)
            .padding(.top, 24)

            VStack(spacing: 12) {
                Button(action: onSignUp) {
                    Text("Créer un compte")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.primaryForeground)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DS.Color.primary)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DS.Color.ink, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PressableScaleStyle())

                Button(action: onSignIn) {
                    Text("Se connecter")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(PressableScaleStyle())

                if let onDismiss {
                    Button(action: onDismiss) {
                        Text("CONTINUER EN TANT QU’INVITÉ")
                            .font(DS.Font.mono.weight(.bold))
                            .foregroundStyle(DS.Color.inkMute)
                            .tracking(1.3)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 36)
        }
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .modifier(PaperGrainBackground())
    }
}

private extension GuestAuthReason {
    struct GateBenefit: Hashable {
        let icon: String
        let title: String
    }

    var gateAccent: Color {
        switch self {
        case .favorites: return DS.Color.primary
        case .report: return DS.Color.statusMajor
        case .profile: return DS.Color.community
        case .confirm: return DS.Color.statusMinor
        }
    }

    var gateBenefits: [GateBenefit] {
        switch self {
        case .favorites:
            return [
                .init(icon: "star.fill", title: "Sauvegarde tes lignes et arrêts"),
                .init(icon: "bell.fill", title: "Reçois des alertes ciblées")
            ]
        case .report:
            return [
                .init(icon: "exclamationmark.bubble.fill", title: "Publie un signalement terrain"),
                .init(icon: "person.2.fill", title: "Aide la communauté en temps réel")
            ]
        case .profile:
            return [
                .init(icon: "person.crop.circle", title: "Retrouve ton historique"),
                .init(icon: "creditcard", title: "Gère ta carte STIB et tes préférences")
            ]
        case .confirm:
            return [
                .init(icon: "hand.thumbsup.fill", title: "Confirme ou résous les incidents"),
                .init(icon: "waveform.path.ecg", title: "Améliore la fiabilité du flux communautaire")
            ]
        }
    }
}

enum GuestAuthReason {
    case favorites
    case report
    case profile
    case confirm

    var icon: String {
        switch self {
        case .favorites: return "star.fill"
        case .report:    return "exclamationmark.bubble.fill"
        case .profile:   return "person.crop.circle.fill"
        case .confirm:   return "hand.thumbsup.fill"
        }
    }

    var title: String {
        switch self {
        case .favorites: return "Sauvegardez vos lignes"
        case .report:    return "Signalez un problème"
        case .profile:   return "Votre profil"
        case .confirm:   return "Confirmez ce signalement"
        }
    }

    var subtitle: String {
        switch self {
        case .favorites: return "Créez un compte pour sauvegarder vos lignes favorites et recevoir des alertes personnalisées."
        case .report:    return "Connectez-vous pour signaler un problème et aider la communauté STIB en temps réel."
        case .profile:   return "Connectez-vous pour accéder à votre historique et vos contributions."
        case .confirm:   return "Connectez-vous pour confirmer ou résoudre des signalements communautaires."
        }
    }
}

// MARK: - Convenience modifier

extension View {
    func guestAuthGate(
        isPresented: Binding<Bool>,
        reason: GuestAuthReason,
        onSignIn: @escaping () -> Void,
        onSignUp: @escaping () -> Void
    ) -> some View {
        self.sheet(isPresented: isPresented) {
            GuestAuthGateView(
                reason: reason,
                onSignIn: { isPresented.wrappedValue = false; onSignIn() },
                onSignUp: { isPresented.wrappedValue = false; onSignUp() },
                onDismiss: { isPresented.wrappedValue = false }
            )
            .presentationDetents([.height(420)])
            .presentationDragIndicator(.hidden)
            .presentationBackground(DS.Color.paper)
        }
    }
}
