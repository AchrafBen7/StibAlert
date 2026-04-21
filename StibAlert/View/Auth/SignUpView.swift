import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var session: AuthSession
    let onRequireActivation: () -> Void

    @State private var nom: String = ""
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
                        Text("Créer un compte")
                            .font(AppTheme.Fonts.display(22))
                            .foregroundStyle(AppTheme.Colors.onboardingTitleSand)
                        Text("Recevez un code d'activation par email.")
                            .font(AppTheme.Fonts.body(14))
                            .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                    }
                    .padding(.top, 20)

                    VStack(spacing: AppTheme.Spacing.md) {
                        AuthField(title: "Nom", text: $nom, isSecure: false)
                        AuthField(title: "Email", text: $email, isSecure: false, keyboard: .emailAddress)
                        AuthField(title: "Mot de passe (min. 8 caractères)", text: $motDePasse, isSecure: true)
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(AppTheme.Fonts.body(13))
                            .foregroundStyle(AppTheme.Colors.danger)
                    }

                    Button(action: submit) {
                        HStack {
                            if isLoading { ProgressView().tint(.black) } else { Text("Recevoir mon code") }
                        }
                        .frame(maxWidth: .infinity)
                        .frame(height: 52)
                        .background(AppTheme.Colors.onboardingTitleSand)
                        .foregroundStyle(.black)
                        .font(AppTheme.Fonts.body(15, weight: .semibold))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .disabled(isLoading || !canSubmit)
                    .opacity(canSubmit ? 1 : 0.6)

                    Spacer(minLength: 40)
                }
                .padding(.horizontal, 28)
            }
        }
    }

    private var canSubmit: Bool {
        !nom.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        motDePasse.count >= 8
    }

    private func submit() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await session.inscription(
                    nom: nom.trimmingCharacters(in: .whitespaces),
                    email: email.trimmingCharacters(in: .whitespaces),
                    motDePasse: motDePasse
                )
                onRequireActivation()
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}
