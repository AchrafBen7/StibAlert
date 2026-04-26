import SwiftUI

struct ActivationView: View {
    @EnvironmentObject private var session: AuthSession
    @State private var code: String = ""
    @State private var isLoading = false
    @State private var isResending = false
    @State private var errorMessage: String?
    @State private var resendCooldown = 0
    @FocusState private var codeFocused: Bool

    private let timer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        ZStack {
            AppTheme.Colors.onboardingBackground.ignoresSafeArea()

            VStack(alignment: .leading, spacing: AppTheme.Spacing.lg) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Code d'activation")
                        .font(AppTheme.Fonts.display(22))
                        .foregroundStyle(AppTheme.Colors.onboardingTitleSand)
                    if let email = session.pendingActivationEmail {
                        Text("Entrez le code envoyé à \(email).")
                            .font(AppTheme.Fonts.body(14))
                            .foregroundStyle(AppTheme.Colors.onboardingTextSecondary)
                    }
                }
                .padding(.top, 20)

                TextField("", text: $code)
                    .keyboardType(.numberPad)
                    .focused($codeFocused)
                    .font(AppTheme.Fonts.display(28))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.white)
                    .frame(height: 64)
                    .background(AppTheme.Palette.surfaceMuted)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.lg)
                            .stroke(AppTheme.Palette.borderStrong, lineWidth: 1)
                    )
                    .onChange(of: code) { _, new in
                        let filtered = String(new.filter { $0.isNumber }.prefix(4))
                        if filtered != new { code = filtered }
                    }

                if let errorMessage {
                    Text(errorMessage)
                        .font(AppTheme.Fonts.body(13))
                        .foregroundStyle(AppTheme.Colors.danger)
                }

                Button(action: submit) {
                    HStack {
                        if isLoading { ProgressView().tint(.black) } else { Text("Activer mon compte") }
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.ButtonHeight.primary)
                    .background(AppTheme.Colors.onboardingTitleSand)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .font(AppTheme.Fonts.body(15, weight: .semibold))
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg))
                }
                .disabled(isLoading || code.count != 4)
                .opacity(code.count == 4 ? 1 : 0.6)
                .accessibilityLabel("Activer mon compte")
                .accessibilityHint("Vérifie le code reçu par email pour finaliser le compte.")

                Button(action: resend) {
                    HStack(spacing: 6) {
                        if isResending {
                            ProgressView().tint(AppTheme.Colors.onboardingTitleSand)
                        } else if resendCooldown > 0 {
                            Text("Renvoyer le code (\(resendCooldown)s)")
                        } else {
                            Text("Renvoyer le code")
                        }
                    }
                    .font(AppTheme.Fonts.body(14))
                    .foregroundStyle(AppTheme.Colors.onboardingTitleSand.opacity(resendCooldown > 0 ? 0.5 : 1))
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isResending || resendCooldown > 0 || isLoading)

                Spacer()
            }
            .padding(.horizontal, 28)
        }
        .onAppear { codeFocused = true }
        .onReceive(timer) { _ in
            if resendCooldown > 0 { resendCooldown -= 1 }
        }
    }

    private func submit() {
        isLoading = true
        errorMessage = nil
        Task {
            do {
                try await session.activer(code: code)
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }

    private func resend() {
        isResending = true
        errorMessage = nil
        Task {
            do {
                try await session.renvoyerCode()
                resendCooldown = 60
            } catch {
                errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isResending = false
        }
    }
}
