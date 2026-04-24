import SwiftUI

struct LoginView: View {
    @EnvironmentObject private var session: AuthSession
    let onGoToSignUp: () -> Void

    @State private var email: String = ""
    @State private var motDePasse: String = ""
    @State private var isLoading = false
    @State private var errorMessage: String?

    var body: some View {
        ZStack {
            AppTheme.Colors.onboardingBackground.ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 0) {
                            Text("Stib").foregroundStyle(AppTheme.Colors.onboardingTitleBlue)
                            Text("Alert").foregroundStyle(AppTheme.Colors.onboardingTitleSand)
                        }
                        .font(AppTheme.Fonts.display)

                        Text("Connectez-vous pour signaler et suivre le réseau STIB.")
                            .font(AppTheme.Fonts.body(14))
                            .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                    }
                    .padding(.top, 40)

                    VStack(spacing: AppTheme.Spacing.md) {
                        AuthField(title: "Email", text: $email, isSecure: false, keyboard: .emailAddress)
                        AuthField(title: "Mot de passe", text: $motDePasse, isSecure: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.Fonts.body(13))
                            .foregroundStyle(AppTheme.Colors.danger)
                    }

                    Button(action: submit) {
                        HStack {
                            if isLoading { ProgressView().tint(.black) } else { Text("Se connecter") }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.ButtonHeight.primary)
                        .background(AppTheme.Colors.onboardingTitleSand)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .font(AppTheme.Fonts.body(15, weight: .semibold))
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                    }
                    .disabled(isLoading || email.isEmpty || motDePasse.isEmpty)
                    .opacity(email.isEmpty || motDePasse.isEmpty ? 0.6 : 1)
                    .accessibilityLabel("Se connecter")
                    .accessibilityHint("Envoie vos identifiants pour ouvrir la session.")

                    HStack {
                        Spacer()
                        Button(action: onGoToSignUp) {
                            (Text("Pas encore de compte ? ")
                                .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                             + Text("Créer un compte")
                                .foregroundStyle(AppTheme.Colors.onboardingTitleBlue))
                            .font(AppTheme.Fonts.body(13))
                        }
                        .accessibilityLabel("Créer un compte")
                        .accessibilityHint("Ouvre l'écran d'inscription pour recevoir un code d'activation.")
                        Spacer()
                    }
                    .padding(.top, 4)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 28)
            }
        }
        .navigationBarBackButtonHidden(true)
    }

    private func submit() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await session.connexion(email: email.trimmingCharacters(in: .whitespaces), motDePasse: motDePasse)
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}

struct AuthField: View {
    let title: String
    @Binding var text: String
    let isSecure: Bool
    var keyboard: UIKeyboardType = .default

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title)
                .font(AppTheme.Fonts.body(12, weight: .semibold))
                .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
            Group {
                if isSecure {
                    SecureField("", text: $text)
                } else {
                    TextField("", text: $text)
                        .keyboardType(keyboard)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled(true)
                }
            }
            .foregroundStyle(.white)
            .font(AppTheme.Fonts.body)
            .padding(.horizontal, 14)
            .frame(height: AppTheme.ButtonHeight.primary)
            .background(AppTheme.Palette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md)
                    .stroke(AppTheme.Palette.borderStrong, lineWidth: 1)
            )
        }
    }
}
