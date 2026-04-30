import SwiftUI

struct SignUpView: View {
    @EnvironmentObject private var session: AuthSession
    @Environment(\.dismiss) private var dismiss
    let onRequireActivation: () -> Void

    @State private var nom = ""
    @State private var email = ""
    @State private var motDePasse = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case nom
        case email
        case password
    }

    private var passwordScore: Int {
        var score = 0
        if motDePasse.count >= 8 { score += 1 }
        if motDePasse.count >= 12 { score += 1 }
        let hasUpper = motDePasse.range(of: "[A-Z]", options: .regularExpression) != nil
        let hasLower = motDePasse.range(of: "[a-z]", options: .regularExpression) != nil
        if hasUpper && hasLower { score += 1 }
        let hasDigit = motDePasse.range(of: "[0-9]", options: .regularExpression) != nil
        let hasSym = motDePasse.range(of: "[^A-Za-z0-9]", options: .regularExpression) != nil
        if hasDigit && hasSym { score += 1 }
        return min(4, score)
    }

    private var canSubmit: Bool {
        !nom.trimmingCharacters(in: .whitespaces).isEmpty &&
        email.contains("@") &&
        motDePasse.count >= 8
    }

    var body: some View {
        AuthEditorialScaffold(mode: .signup) {
            hero
            modeSwitch
            socialSection
            AuthDivider()
            formSection
            termsBlock
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
            (
                Text("Le réseau, ")
                    .foregroundColor(DS.Color.ink)
                + Text("à vous")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .italic()
                    .foregroundColor(DS.Color.primary)
                + Text(".")
                    .foregroundColor(DS.Color.ink)
            )
            .font(.system(size: 36, weight: .bold))
            .tracking(-1.2)

            Text("Quelques secondes pour personnaliser vos alertes et synchroniser vos favoris.")
                .font(.system(size: 13.5))
                .foregroundColor(DS.Color.inkSoft)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.top, 6)
        }
    }

    private var modeSwitch: some View {
        AuthModeSwitch(mode: .signup, onSelectSignIn: { dismiss() }, onSelectSignUp: {})
    }

    private var socialSection: some View {
        VStack(spacing: 10) {
            AuthSocialButton(label: "Continuer avec Apple", icon: AnyView(Image(systemName: "applelogo").font(.system(size: 16))), primary: true) {}
            AuthSocialButton(label: "Continuer avec Google", icon: AnyView(AuthGoogleIcon()), primary: false) {}
        }
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            AuthField(label: "PRÉNOM", icon: "person", text: $nom, isSecure: false)
                .focused($focusedField, equals: .nom)

            AuthField(label: "EMAIL", icon: "envelope", text: $email, isSecure: false, keyboard: .emailAddress)
                .focused($focusedField, equals: .email)

            AuthField(
                label: "MOT DE PASSE",
                icon: "lock",
                text: $motDePasse,
                isSecure: !showPassword,
                trailing: AnyView(
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundColor(DS.Color.inkMute)
                    }
                    .buttonStyle(.plain)
                )
            )
            .focused($focusedField, equals: .password)

            if !motDePasse.isEmpty {
                passwordStrength
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Color.statusMajor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            Button(action: submit) {
                HStack(spacing: 8) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(DS.Color.primaryForeground)
                    } else {
                        Text("Recevoir mon code")
                            .font(.system(size: 14, weight: .bold))
                        Image(systemName: "arrow.right")
                            .font(.system(size: 14, weight: .bold))
                    }
                }
                .frame(maxWidth: .infinity, minHeight: 48)
                .foregroundColor(DS.Color.primaryForeground)
                .background(DS.Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.primary, lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .shadow(color: DS.Color.ink.opacity(0.15), radius: 8, y: 4)
            }
            .disabled(isLoading || !canSubmit)
            .opacity(canSubmit ? 1 : 0.6)
            .buttonStyle(PressableScaleStyle())
        }
    }

    private var passwordStrength: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(0..<4, id: \.self) { index in
                    Capsule()
                        .fill(index < passwordScore ? strengthColor : DS.Color.ink.opacity(0.1))
                        .frame(height: 4)
                }
            }
            Text("FORCE : \(strengthLabel.uppercased())")
                .font(DS.Font.mono.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
        }
        .padding(.horizontal, 2)
    }

    private var strengthColor: Color {
        switch passwordScore {
        case 0, 1: return DS.Color.statusMajor
        case 2: return DS.Color.statusMinor
        default: return DS.Color.statusOK
        }
    }

    private var strengthLabel: String {
        ["très faible", "faible", "correct", "fort", "excellent"][min(passwordScore, 4)]
    }

    private var termsBlock: some View {
        Text("En créant un compte vous acceptez nos conditions et notre politique de confidentialité.")
            .font(.system(size: 11))
            .foregroundColor(DS.Color.inkMute)
            .multilineTextAlignment(.center)
            .lineSpacing(2)
            .frame(maxWidth: .infinity)
            .padding(.top, 20)
    }

    private func submit() {
        focusedField = nil
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
