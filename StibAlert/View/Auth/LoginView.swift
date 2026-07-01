import SwiftUI
import AuthenticationServices

enum AuthEditorialMode: String {
    case signin
    case signup
}

struct LoginView: View {
    @EnvironmentObject private var session: AuthSession
    let onGoToSignUp: () -> Void
    var onClose: () -> Void = {}

    @State private var email = ""
    @State private var motDePasse = ""
    @State private var showPassword = false
    @State private var isLoading = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: Field?

    private enum Field {
        case email
        case password
    }

    var body: some View {
        AuthEditorialScaffold(mode: .signin, onClose: onClose) {
            hero
            modeSwitch
            socialSection
            AuthDivider()
            formSection
            guestLink
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            (
                Text("Reprenez votre ")
                    .foregroundColor(DS.Color.ink)
                + Text("trajet")
                    .font(.system(size: 36, weight: .bold, design: .serif))
                    .italic()
                    .foregroundColor(DS.Color.primary)
                + Text(".")
                    .foregroundColor(DS.Color.ink)
            )
            .font(.system(size: 36, weight: .bold))
            .tracking(-1.2)

            Text("Vos lignes favorites, alertes et trajets, reconnectés en un instant.")
                .font(.system(size: 13.5))
                .foregroundColor(DS.Color.inkSoft)
                .frame(maxWidth: 280, alignment: .leading)
                .padding(.top, DS.Spacing.xs)
        }
    }

    private var modeSwitch: some View {
        AuthModeSwitch(mode: .signin, onSelectSignIn: {}, onSelectSignUp: onGoToSignUp)
    }

    private var socialSection: some View {
        AppleSignInButtonView { result in
            handleAppleSignIn(result)
        }
        .padding(.bottom, DS.Spacing.md)
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
            // ASAuthorizationError.canceled is fine — user just dismissed the sheet.
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationError.errorDomain,
               nsErr.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            errorMessage = error.localizedDescription
        }
    }

    private var formSection: some View {
        VStack(spacing: DS.Spacing.lg) {
            AuthField(
                label: AppLocalizer.string("auth.field.email", defaultValue: "EMAIL"),
                icon: "envelope",
                text: $email,
                isSecure: false,
                keyboard: .emailAddress
            )
            .focused($focusedField, equals: .email)

            AuthField(
                label: AppLocalizer.string("auth.field.password", defaultValue: "MOT DE PASSE"),
                icon: "lock",
                text: $motDePasse,
                isSecure: !showPassword,
                keyboard: .default,
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

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Color.statusMajor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack {
                Spacer()
                Button(action: openPasswordReset) {
                    Text("Mot de passe oublié ?")
                        .font(DS.Font.mono.weight(.bold))
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
                        Text("Se connecter")
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
                .opacity(isLoading ? 0.6 : 1)
            }
            .disabled(isLoading || email.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || motDePasse.isEmpty)
            .buttonStyle(PressableScaleStyle())
        }
    }

    private func openPasswordReset() {
        // Self-service reset isn't wired yet — opens a pre-filled support
        // mail so reviewers (and real users) reach a working escalation path.
        let subject = "Réinitialisation de mot de passe — Blayse"
        let body = """
        Bonjour,

        J'ai besoin de réinitialiser mon mot de passe Blayse.
        Email associé au compte : \(email.isEmpty ? "(à compléter)" : email)

        Merci.
        """
        let encodedSubject = subject.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? subject
        let encodedBody = body.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? body
        if let url = URL(string: "mailto:support@stibalert.app?subject=\(encodedSubject)&body=\(encodedBody)") {
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
                if case let APIError.server(status, message) = error, status == 401 {
                    errorMessage = message ?? "Email ou mot de passe incorrect."
                } else {
                    errorMessage = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
            isLoading = false
        }
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
        .padding(.top, DS.Spacing.xxl)
    }
}

struct AuthEditorialScaffold<Content: View>: View {
    let mode: AuthEditorialMode
    var onClose: () -> Void = {}
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                // Close bar — replaces the old "BON RETOUR" / "BIENVENUE"
                // eyebrow. Now that auth is a full-screen page (not a sheet
                // with a drag handle) it needs an explicit dismiss control,
                // plus real breathing room under the status bar.
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
                    .accessibilityLabel("Fermer")
                    Spacer()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.sm)

                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, DS.Spacing.xxl)
                .padding(.bottom, DS.Spacing.xxxl)
            }
        }
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
                .font(DS.Font.mono.weight(.bold))
                .tracking(1.2)
                .foregroundColor(active ? DS.Color.paper : DS.Color.inkMute)
                .frame(maxWidth: .infinity, minHeight: 36)
        }
        .buttonStyle(.plain)
    }
}

struct AuthDivider: View {
    var body: some View {
        HStack(spacing: DS.Spacing.md) {
            DS.Rule().frame(maxWidth: .infinity)
            Text("OU AVEC VOTRE EMAIL")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
            DS.Rule().frame(maxWidth: .infinity)
        }
        .padding(.bottom, DS.Spacing.xl)
    }
}

struct AuthField: View {
    let label: String
    let icon: String
    @Binding var text: String
    let isSecure: Bool
    var keyboard: UIKeyboardType = .default
    var trailing: AnyView? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text(label)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
                .padding(.horizontal, DS.Spacing.xxs)

            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .foregroundColor(DS.Color.inkMute)

                Group {
                    if isSecure {
                        SecureField("", text: $text)
                            .textInputAutocapitalization(.never)
                            .autocorrectionDisabled()
                    } else {
                        TextField("", text: $text)
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
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }
}

