import SwiftUI

struct GuestAuthGateView: View {
    let reason: GuestAuthReason
    let onSignIn: () -> Void
    let onSignUp: () -> Void
    var onDismiss: (() -> Void)? = nil

    var body: some View {
        VStack(spacing: 0) {
            Capsule()
                .fill(Color.white.opacity(0.15))
                .frame(width: 36, height: 4)
                .padding(.top, 12)
                .padding(.bottom, 28)

            Image(systemName: reason.icon)
                .font(.system(size: 36, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.brand)
                .padding(.bottom, 18)

            Text(reason.title)
                .font(AppTheme.Fonts.display(20))
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .multilineTextAlignment(.center)

            Text(reason.subtitle)
                .font(AppTheme.Fonts.body(14))
                .foregroundStyle(AppTheme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.top, 8)
                .padding(.horizontal, 32)

            VStack(spacing: 12) {
                Button(action: onSignUp) {
                    Text("Créer un compte")
                        .font(AppTheme.Fonts.body(15, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.ButtonHeight.primary)
                        .background(AppTheme.Palette.brand)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                }
                .buttonStyle(.plain)

                Button(action: onSignIn) {
                    Text("Se connecter")
                        .font(AppTheme.Fonts.body(15, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.brand)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.ButtonHeight.primary)
                        .background(AppTheme.Palette.brand.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                }
                .buttonStyle(.plain)

                if let onDismiss {
                    Button(action: onDismiss) {
                        Text("Continuer en tant qu'invité")
                            .font(AppTheme.Fonts.body(13))
                            .foregroundStyle(AppTheme.Palette.textMuted)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 32)
            .padding(.bottom, 40)
        }
        .background(AppTheme.Palette.screenElevated)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
            .presentationBackground(AppTheme.Palette.screenElevated)
        }
    }
}
