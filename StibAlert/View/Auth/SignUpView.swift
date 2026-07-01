import SwiftUI
import AuthenticationServices

struct SignUpView: View {
    @EnvironmentObject private var session: AuthSession
    let onRequireActivation: () -> Void
    var onGoToSignIn: () -> Void = {}
    var onClose: () -> Void = {}

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

    private var hasMinLength: Bool { motDePasse.count >= 8 }
    private var hasUppercase: Bool { motDePasse.range(of: "[A-Z]", options: .regularExpression) != nil }
    private var hasDigit: Bool { motDePasse.range(of: "[0-9]", options: .regularExpression) != nil }

    private var shouldShowPasswordCriteria: Bool {
        focusedField == .password || !motDePasse.isEmpty
    }

    private var canSubmit: Bool {
        !nom.trimmingCharacters(in: .whitespaces).isEmpty &&
        Self.isValidEmail(email) &&
        motDePasse.count >= 8
    }

    private var hasInvalidEmail: Bool {
        let trimmed = email.trimmingCharacters(in: .whitespaces)
        return !trimmed.isEmpty && !Self.isValidEmail(trimmed)
    }

    /// RFC-light pragmatic regex : letters/digits/_.-+ before @, then domain
    /// with at least one dot and a 2+ char TLD. Catches "a@", "a@b", "a@b.c"
    /// before the request hits the backend (which used to return a cryptic
    /// 5-second-late error).
    static func isValidEmail(_ candidate: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return candidate.trimmingCharacters(in: .whitespaces)
            .range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    var body: some View {
        AuthEditorialScaffold(mode: .signup, onClose: onClose) {
            hero
            modeSwitch
            socialSection
            AuthDivider()
            formSection
            termsBlock
            guestLink
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
        AuthModeSwitch(mode: .signup, onSelectSignIn: onGoToSignIn, onSelectSignUp: {})
    }

    private var socialSection: some View {
        AppleSignInButtonView { result in
            handleAppleSignIn(result)
        }
        .padding(.bottom, 12)
    }

    private func handleAppleSignIn(_ result: Result<AppleSignInPayload, Error>) {
        switch result {
        case .success(let payload):
            isLoading = true
            errorMessage = nil
            Task {
                do {
                    try await session.signInWithApple(
                        identityToken: payload.identityToken,
                        fullName: payload.fullName
                    )
                } catch {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
                isLoading = false
            }
        case .failure(let error):
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationError.errorDomain,
               nsErr.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            AuthField(label: "PRÉNOM", icon: "person", text: $nom, isSecure: false)
                .focused($focusedField, equals: .nom)

            VStack(alignment: .leading, spacing: 4) {
                AuthField(label: "EMAIL", icon: "envelope", text: $email, isSecure: false, keyboard: .emailAddress)
                    .focused($focusedField, equals: .email)

                if hasInvalidEmail && focusedField != .email {
                    Text("Format d'email invalide")
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(DS.Color.statusMajor)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: hasInvalidEmail)

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

            if shouldShowPasswordCriteria {
                passwordCriteria
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }

            if !motDePasse.isEmpty {
                passwordStrength
            }

            if let errorMessage {
                VStack(alignment: .leading, spacing: 8) {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundColor(DS.Color.statusMajor)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    // D — Si l'email est déjà utilisé, on propose direct un
                    // CTA "Se connecter à la place" plutôt que de laisser
                    // l'utilisateur naviguer manuellement vers Sign In.
                    if errorMessage.lowercased().contains("déjà utilisé") ||
                       errorMessage.lowercased().contains("already") {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onGoToSignIn()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text("Se connecter à la place")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            .foregroundStyle(DS.Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }
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

    private var passwordCriteria: some View {
        VStack(alignment: .leading, spacing: 4) {
            criterionRow(label: "8 caractères minimum", satisfied: hasMinLength, required: true)
            criterionRow(label: "Une majuscule", satisfied: hasUppercase, required: false)
            criterionRow(label: "Un chiffre", satisfied: hasDigit, required: false)
        }
        .padding(.horizontal, 2)
        .animation(.easeOut(duration: 0.18), value: motDePasse)
    }

    private func criterionRow(label: String, satisfied: Bool, required: Bool) -> some View {
        HStack(spacing: 6) {
            Image(systemName: satisfied ? "checkmark.circle.fill" : "circle")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(satisfied ? DS.Color.statusOK : DS.Color.inkMute.opacity(0.6))
            Text(label)
                .font(.system(size: 11.5, weight: satisfied ? .semibold : .regular))
                .foregroundStyle(satisfied ? DS.Color.ink : DS.Color.inkMute)
            if !required {
                Text("· recommandé")
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.Color.inkMute.opacity(0.8))
            }
            Spacer(minLength: 0)
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
        VStack(spacing: 8) {
            Text("En créant un compte vous acceptez nos conditions et notre politique de confidentialité.")
                .font(.system(size: 11))
                .foregroundColor(DS.Color.inkMute)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            HStack(spacing: 12) {
                if let url = URL(string: "\(AppConfig.backendBaseURL)/terms") {
                    Link(destination: url) {
                        Text("Conditions d’utilisation")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Color.statusMajor)
                    }
                }
                if let url = URL(string: "\(AppConfig.backendBaseURL)/privacy") {
                    Link(destination: url) {
                        Text("Politique de confidentialité")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Color.statusMajor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 20)
    }

    private var guestLink: some View {
        HStack {
            Spacer()
            Button {
                onClose()
            } label: {
                Text("CONTINUER EN TANT QU’INVITÉ →")
                    .font(DS.Font.mono.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1.5)
            }
            Spacer()
        }
        .padding(.top, 24)
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
