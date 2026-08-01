import SwiftUI

/// Formulaire d'inscription seul. Comme `SignInFormSection`, il vit à
/// l'intérieur de `AuthPage` : l'email et le mot de passe sont des `@Binding`
/// partagés, donc se tromper d'onglet ne fait plus perdre la saisie.
struct SignUpFormSection: View {
    @EnvironmentObject private var session: AuthSession
    @Binding var email: String
    @Binding var motDePasse: String
    let onRequireActivation: () -> Void
    var onGoToSignIn: () -> Void = {}

    @State private var nom = ""
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

    /// Regex pragmatique : lettres/chiffres/_.-+ avant @, puis un domaine avec
    /// au moins un point et un TLD de 2+ caractères. Attrape « a@ », « a@b »,
    /// « a@b.c » avant l'aller-retour serveur (qui répondait une erreur obscure
    /// 5 secondes trop tard).
    static func isValidEmail(_ candidate: String) -> Bool {
        let pattern = #"^[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}$"#
        return candidate.trimmingCharacters(in: .whitespaces)
            .range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
            formFields
            termsBlock
        }
    }

    private var formFields: some View {
        VStack(spacing: 14) {
            AuthField(
                label: AppLocalizer.string("field.first_name_caps", defaultValue: "PRÉNOM"),
                icon: "person",
                placeholder: AppLocalizer.string("auth.placeholder.first_name", defaultValue: "Ton prénom"),
                text: $nom,
                isSecure: false,
                isFocused: focusedField == .nom
            )
            .focused($focusedField, equals: .nom)

            VStack(alignment: .leading, spacing: 4) {
                AuthField(
                    label: AppLocalizer.string("auth.field.email", defaultValue: "EMAIL"),
                    icon: "envelope",
                    placeholder: AppLocalizer.string("auth.placeholder.email", defaultValue: "ton@email.be"),
                    text: $email,
                    isSecure: false,
                    keyboard: .emailAddress,
                    isFocused: focusedField == .email
                )
                .focused($focusedField, equals: .email)

                if hasInvalidEmail && focusedField != .email {
                    Text(AppLocalizer.string("auth.error.invalid_email_format", defaultValue: "Format d'email invalide"))
                        .font(.system(size: 11.5, weight: .semibold))
                        .foregroundStyle(DS.Color.statusMajor)
                        .padding(.horizontal, 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.18), value: hasInvalidEmail)

            AuthField(
                label: AppLocalizer.string("auth.field.password", defaultValue: "MOT DE PASSE"),
                icon: "lock",
                placeholder: AppLocalizer.string("auth.placeholder.new_password", defaultValue: "8 caractères minimum"),
                text: $motDePasse,
                isSecure: !showPassword,
                isFocused: focusedField == .password,
                trailing: AnyView(
                    Button { showPassword.toggle() } label: {
                        Image(systemName: showPassword ? "eye.slash" : "eye")
                            .font(.system(size: 14))
                            .foregroundColor(DS.Color.inkMute)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(showPassword
                        ? AppLocalizer.string("auth.password.hide", defaultValue: "Masquer le mot de passe")
                        : AppLocalizer.string("auth.password.show", defaultValue: "Afficher le mot de passe"))
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
                    // Si l'email est déjà pris, on propose directement de
                    // basculer côté connexion plutôt que de laisser chercher.
                    if errorMessage.lowercased().contains("déjà utilisé") ||
                       errorMessage.lowercased().contains("already") ||
                       errorMessage.lowercased().contains("al in gebruik") {
                        Button {
                            UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            onGoToSignIn()
                        } label: {
                            HStack(spacing: 6) {
                                Image(systemName: "arrow.right.circle.fill")
                                    .font(.system(size: 12, weight: .bold))
                                Text(AppLocalizer.string("Se connecter à la place", defaultValue: "Se connecter à la place"))
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
                        Text(AppLocalizer.string("auth.action.send_code", defaultValue: "Recevoir mon code"))
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
            criterionRow(label: AppLocalizer.string("password.min_length", defaultValue: "8 caractères minimum"), satisfied: hasMinLength, required: true)
            criterionRow(label: AppLocalizer.string("password.one_uppercase", defaultValue: "Une majuscule"), satisfied: hasUppercase, required: false)
            criterionRow(label: AppLocalizer.string("password.one_digit", defaultValue: "Un chiffre"), satisfied: hasDigit, required: false)
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
                Text(AppLocalizer.string("common.recommended_dot", defaultValue: "· recommandé"))
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
            Text(AppLocalizer.format("password.strength", defaultValue: "FORCE : %@", strengthLabel.uppercased()))
                .font(DS.Font.label.weight(.bold))
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
        [
            AppLocalizer.string("password.strength.very_weak", defaultValue: "très faible"),
            AppLocalizer.string("password.strength.weak", defaultValue: "faible"),
            AppLocalizer.string("password.strength.fair", defaultValue: "correct"),
            AppLocalizer.string("password.strength.strong", defaultValue: "fort"),
            AppLocalizer.string("password.strength.excellent", defaultValue: "excellent"),
        ][min(passwordScore, 4)]
    }

    private var termsBlock: some View {
        VStack(spacing: 8) {
            Text(AppLocalizer.string("En créant un compte, tu acceptes nos conditions et notre politique de confidentialité.", defaultValue: "En créant un compte, tu acceptes nos conditions et notre politique de confidentialité."))
                .font(.system(size: 11))
                .foregroundColor(DS.Color.inkMute)
                .multilineTextAlignment(.center)
                .lineSpacing(2)
            HStack(spacing: 12) {
                if let url = URL(string: "https://blayse.app/terms") {
                    Link(destination: url) {
                        Text(AppLocalizer.string("legal.terms", defaultValue: "Conditions d’utilisation"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Color.statusMajor)
                    }
                }
                // Site public blayse.app (URLs déclarées dans App Store Connect),
                // jamais l'URL du backend (c'est l'API).
                if let url = URL(string: "https://blayse.app/privacy") {
                    Link(destination: url) {
                        Text(AppLocalizer.string("Politique de confidentialité", defaultValue: "Politique de confidentialité"))
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(DS.Color.statusMajor)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, DS.Spacing.lg)
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
