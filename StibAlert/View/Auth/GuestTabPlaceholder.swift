import SwiftUI

struct GuestTabPlaceholder: View {
    let reason: GuestAuthReason
    let onSignIn: () -> Void
    let onSignUp: () -> Void

    var body: some View {
        ZStack {
            AppTheme.Palette.screen.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                VStack(spacing: 20) {
                    ZStack {
                        Circle()
                            .fill(AppTheme.Palette.brand.opacity(0.12))
                            .frame(width: 80, height: 80)
                        Image(systemName: reason.icon)
                            .font(.system(size: 32, weight: .semibold))
                            .foregroundStyle(AppTheme.Palette.brand)
                    }

                    VStack(spacing: 10) {
                        Text(reason.title)
                            .font(AppTheme.Fonts.display(22))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .multilineTextAlignment(.center)

                        Text(reason.subtitle)
                            .font(AppTheme.Fonts.body(14))
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal, 40)
                    }
                }

                Spacer()

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
                }
                .padding(.horizontal, 28)
                .padding(.bottom, 120)
            }
        }
    }
}
