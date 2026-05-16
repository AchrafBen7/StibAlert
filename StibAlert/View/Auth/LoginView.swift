import SwiftUI
import AuthenticationServices

enum AuthEditorialMode: String {
    case signin
    case signup
}

struct LoginView: View {
    @EnvironmentObject private var session: AuthSession
    @Environment(\.dismiss) private var dismiss
    let onGoToSignUp: () -> Void

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
        AuthEditorialScaffold(mode: .signin) {
            hero
            modeSwitch
            socialSection
            AuthDivider()
            formSection
            guestLink
        }
    }

    private var hero: some View {
        VStack(alignment: .leading, spacing: 8) {
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
                .padding(.top, 6)
        }
    }

    private var modeSwitch: some View {
        AuthModeSwitch(mode: .signin, onSelectSignIn: {}, onSelectSignUp: onGoToSignUp)
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
        VStack(spacing: 14) {
            AuthField(
                label: "EMAIL",
                icon: "envelope",
                text: $email,
                isSecure: false,
                keyboard: .emailAddress
            )
            .focused($focusedField, equals: .email)

            AuthField(
                label: "MOT DE PASSE",
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
                Button {} label: {
                    Text("Mot de passe oublié ?")
                        .font(DS.Font.mono.weight(.bold))
                        .foregroundColor(DS.Color.ink)
                        .underline()
                        .tracking(1)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 4)

            Button(action: submit) {
                HStack(spacing: 8) {
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
                dismiss()
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
}

struct AuthEditorialScaffold<Content: View>: View {
    let mode: AuthEditorialMode
    @ViewBuilder let content: () -> Content

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                PageHeader(
                    title: "",
                    eyebrow: mode == .signin ? "BON RETOUR" : "BIENVENUE",
                    large: false
                )
                .padding(.horizontal, 20)
                .padding(.top, 12)

                VStack(alignment: .leading, spacing: 0) {
                    content()
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                .padding(.bottom, 40)
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
                    modeButton("SE CONNECTER", active: mode == .signin, action: onSelectSignIn)
                    modeButton("S'INSCRIRE", active: mode == .signup, action: onSelectSignUp)
                }
            }
        }
        .frame(height: 40)
        .padding(.bottom, 20)
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

struct AuthSocialButton: View {
    let label: String
    let icon: AnyView
    let primary: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                icon
                Text(label)
                    .font(.system(size: 14, weight: .semibold))
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .foregroundColor(primary ? DS.Color.paper : DS.Color.ink)
            .background(primary ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(primary ? DS.Color.ink : DS.Color.ink.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(PressableScaleStyle())
        .padding(.bottom, label == "Continuer avec Google" ? 20 : 0)
    }
}

struct AuthDivider: View {
    var body: some View {
        HStack(spacing: 12) {
            DS.Rule().frame(maxWidth: .infinity)
            Text("OU AVEC VOTRE EMAIL")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
            DS.Rule().frame(maxWidth: .infinity)
        }
        .padding(.bottom, 20)
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
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
                .padding(.horizontal, 2)

            HStack(spacing: 8) {
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
            .padding(.horizontal, 12)
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

struct AuthGoogleIcon: View {
    var body: some View {
        Image(systemName: "g.circle.fill")
            .font(.system(size: 16))
            .foregroundStyle(
                LinearGradient(
                    colors: [
                        Color(red: 0.26, green: 0.52, blue: 0.96),
                        Color(red: 0.92, green: 0.26, blue: 0.21)
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .frame(width: 16, height: 16)
    }
}
