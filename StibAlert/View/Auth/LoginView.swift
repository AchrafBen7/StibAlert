import SwiftUI

enum AuthEditorialMode: String {
    case signin
    case signup
}

/// Formulaire de connexion seul. L'en-tête, le sélecteur de mode, le bouton
/// Apple et le lien invité appartiennent à `AuthPage`, qui les garde immobiles
/// pendant la bascule connexion ⇄ inscription.
struct SignInFormSection: View {
    @EnvironmentObject private var session: AuthSession
    @Binding var email: String
    @Binding var motDePasse: String

    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    private var canSubmit: Bool {
        !email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !motDePasse.isEmpty
    }

    var body: some View {
        VStack(spacing: DS.Spacing.lg) {
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

            AuthField(
                label: AppLocalizer.string("auth.field.password", defaultValue: "MOT DE PASSE"),
                icon: "lock",
                placeholder: AppLocalizer.string("auth.placeholder.password", defaultValue: "Ton mot de passe"),
                text: $motDePasse,
                isSecure: !showPassword,
                keyboard: .default,
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Color.statusMajor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(action: openPasswordReset) {
                    Text(AppLocalizer.string("Mot de passe oublié ?", defaultValue: "Mot de passe oublié ?"))
                        .font(DS.Font.label.weight(.bold))
                        .foregroundColor(DS.Color.ink)
                        .underline()
                        .tracking(1)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, DS.Spacing.xs)

            Button(action: submit) {
                HStack(spacing: DS.Spacing.sm) {
                    if isLoading {
                        ProgressView()
                            .progressViewStyle(.circular)
                            .tint(DS.Color.primaryForeground)
                    } else {
                        Text(AppLocalizer.string("auth.action.sign_in", defaultValue: "Se connecter"))
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
                .opacity(isLoading || !canSubmit ? 0.6 : 1)
            }
            .disabled(isLoading || !canSubmit)
            .buttonStyle(PressableScaleStyle())
        }
    }

    private func openPasswordReset() {
        // La réinitialisation en self-service n'est pas encore branchée : on
        // ouvre un mail pré-rempli, pour que le chemin d'escalade existe
        // vraiment (utilisateurs comme relecteurs App Store).
        let subject = AppLocalizer.string("auth.reset.subject", defaultValue: "Réinitialisation de mot de passe — Blayse")
        let body = AppLocalizer.format(
            "auth.reset.body",
            defaultValue: "Bonjour,\n\nJ'ai besoin de réinitialiser mon mot de passe Blayse.\nEmail associé au compte : %@\n\nMerci.",
            email.isEmpty ? AppLocalizer.string("auth.reset.to_complete", defaultValue: "(à compléter)") : email
        )
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:support@blayse.app?subject=\(encodedSubject)&body=\(encodedBody)") {
            UIApplication.shared.open(url)
        }
    }

    private func submit() {
        focusedField = nil
        isLoading = true
        errorMessage = nil

        Task {
            do {
                try await session.connexion(
                    email: email.trimmingCharacters(in: .whitespaces),
                    motDePasse: motDePasse
                )
            } catch {
                if case APIError.server(let status, _) = error, status == 401 {
                    // On IGNORE volontairement le message du serveur.
                    //
                    // Le backend répond « Email ou mot de passe incorrect. » en
                    // français en dur ; comme on le préférait à notre propre
                    // texte, l'erreur restait française dans l'app néerlandaise.
                    // Pour un 401 de connexion, notre libellé traduit dit
                    // exactement la même chose — le serveur n'ajoute rien.
                    errorMessage = AppLocalizer.string(
                        "auth.error.bad_credentials",
                        defaultValue: "Email ou mot de passe incorrect."
                    )
                } else {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
            isLoading = false
        }
    }
}

// MARK: - Coquille commune

struct AuthEditorialScaffold<Content: View>: View {
    let mode: AuthEditorialMode
    var onClose: () -> Void = {}
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Barre de fermeture : l'auth est une page plein écran (plus une
                // feuille avec sa poignée), il lui faut donc un moyen explicite
                // de sortir, avec de l'air sous la barre d'état.
                HStack {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 40, height: 40)
                            .background(DS.Color.paper)
                            .overlay(Circle().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(AppLocalizer.string("common.close", defaultValue: "Fermer"))
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.xxl)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .background(DS.Color.paper.ignoresSafeArea())
        .modifier(PaperGrainBackground())
        .toolbar(.hidden, for: .navigationBar)
    }
}

struct AuthModeSwitch: View {
    let mode: AuthEditorialMode
    let onSelectSignIn: () -> Void
    let onSelectSignUp: () -> Void

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            ZStack(alignment: .leading) {
                Capsule()
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
                    .background(Capsule().fill(DS.Color.paper2.opacity(0.6)))

                Capsule()
                    .fill(DS.Color.ink)
                    .frame(width: width / 2 - 8, height: 32)
                    .padding(.leading, 4)
                    .offset(x: mode == .signup ? width / 2 : 0)
                    .shadow(color: DS.Color.ink.opacity(0.1), radius: 2, y: 1)
                    .animation(.spring(response: 0.35, dampingFraction: 0.85), value: mode)

                HStack(spacing: 0) {
                    modeButton(AppLocalizer.string("auth.mode.sign_in"), active: mode == .signin, action: onSelectSignIn)
                    modeButton(AppLocalizer.string("auth.mode.sign_up"), active: mode == .signup, action: onSelectSignUp)
                }
            }
        }
        .frame(height: 40)
        .padding(.bottom, DS.Spacing.xl)
    }

    private func modeButton(_ label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.label.weight(.bold))
                .tracking(1.2)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .foregroundColor(active ? DS.Color.paper : DS.Color.inkMute)
                .frame(maxWidth: .infinity, minHeight: 36)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}

struct AuthDivider: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DS.Rule().frame(maxWidth: .infinity)
            // `lineLimit(1)` + `fixedSize` : en néerlandais « OF MET JE E-MAIL »
            // se coupait en deux lignes entre les deux filets, ce qui déformait
            // tout le bloc. Le texte garde sa largeur, les filets se partagent
            // le reste.
            Text(AppLocalizer.string("auth.divider.email", defaultValue: "OU AVEC VOTRE EMAIL"))
                .font(DS.Font.labelSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(0.8)
                .lineLimit(1)
                .fixedSize(horizontal: true, vertical: false)
            DS.Rule().frame(maxWidth: .infinity)
        }
        .padding(.bottom, DS.Spacing.xl)
    }
}

struct AuthField: View {
    let label: String
    let icon: String
    var placeholder: String = ""
    @Binding var text: String
    let isSecure: Bool
    var keyboard: UIKeyboardType = .default
    /// Piloté par le `@FocusState` du parent : le champ actif se souligne, au
    /// lieu de laisser deux rectangles vides identiques.
    var isFocused: Bool = false
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(label)
                .font(DS.Font.labelSmall.weight(.bold))
                .foregroundColor(isFocused ? DS.Color.primary : DS.Color.inkMute)
                .tracking(1)
                .padding(.horizontal, DS.Spacing.xxs)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(isFocused ? DS.Color.primary : DS.Color.inkMute)

                Group {
                    if isSecure {
                        SecureField(placeholder, text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField(placeholder, text: $text)
                            .keyboardType(keyboard)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    }
                }
                .font(.system(size: 14))
                .foregroundColor(DS.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)

                if let trailing {
                    trailing
                }
            }
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 48)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(
                        isFocused ? DS.Color.primary : DS.Color.ink.opacity(0.15),
                        lineWidth: isFocused ? 1.5 : 1
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .animation(.easeOut(duration: 0.16), value: isFocused)
    }
}
