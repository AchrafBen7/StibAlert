import SwiftUI
import AuthenticationServices

/// Page d'authentification unique : connexion ET inscription au même endroit.
///
/// Avant, le sélecteur « Connexion | Inscription » ressemblait à un segmented
/// control mais **empilait un nouvel écran** dans la `NavigationStack` : on
/// touchait un onglet et la page glissait latéralement comme un lien. D'où la
/// confusion — un onglet promet de changer le contenu sur place, pas de
/// naviguer. Ici le mode est un simple `@State` : seul le formulaire change,
/// l'en-tête et le bouton Apple ne bougent plus.
///
/// Effet de bord voulu : l'email et le mot de passe saisis **survivent** au
/// changement de mode. Se tromper d'onglet ne coûte plus rien.
struct AuthPage: View {
    @EnvironmentObject private var session: AuthSession
    let onRequireActivation: () -> Void
    var onClose: () -> Void = {}

    @State private var mode: AuthEditorialMode
    @State private var email: String
    @State private var motDePasse = ""
    @State private var appleError: String?
    @State private var isAppleLoading = false

    init(
        initialMode: AuthEditorialMode,
        onRequireActivation: @escaping () -> Void,
        onClose: @escaping () -> Void = {}
    ) {
        self.onRequireActivation = onRequireActivation
        self.onClose = onClose
        _mode = State(initialValue: initialMode)
        _email = State(initialValue: "")
    }

    var body: some View {
        AuthEditorialScaffold(mode: mode, onClose: onClose) {
            hero
            AuthModeSwitch(
                mode: mode,
                onSelectSignIn: { select(.signin) },
                onSelectSignUp: { select(.signup) }
            )
            appleSection
            AuthDivider()
            forms
            guestLink
        }
    }

    // MARK: - En-tête

    private var hero: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Group {
                if mode == .signin {
                    (
                        Text(AppLocalizer.string("auth.hero.signin.prefix", defaultValue: "Reprends ton "))
                            .foregroundColor(DS.Color.ink)
                        + Text(AppLocalizer.string("auth.hero.signin.emphasis", defaultValue: "trajet"))
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .italic()
                            .foregroundColor(DS.Color.primary)
                        + Text(".").foregroundColor(DS.Color.ink)
                    )
                } else {
                    (
                        Text(AppLocalizer.string("signup.hero.prefix", defaultValue: "Le réseau, "))
                            .foregroundColor(DS.Color.ink)
                        + Text(AppLocalizer.string("signup.hero.emphasis", defaultValue: "à toi"))
                            .font(.system(size: 30, weight: .bold, design: .serif))
                            .italic()
                            .foregroundColor(DS.Color.primary)
                        + Text(".").foregroundColor(DS.Color.ink)
                    )
                }
            }
            // 30 et non 36 : à 36 le titre poussait le formulaire si bas que le
            // bouton principal frôlait le clavier, et l'écran finissait sur une
            // grande zone morte.
            .font(.system(size: 30, weight: .bold))
            .tracking(-1)

            Text(mode == .signin
                 ? AppLocalizer.string("Tes lignes favorites, alertes et trajets, reconnectés en un instant.", defaultValue: "Tes lignes favorites, alertes et trajets, reconnectés en un instant.")
                 : AppLocalizer.string("auth.hero.signup.subtitle", defaultValue: "Quelques secondes pour personnaliser tes alertes et synchroniser tes favoris."))
                .font(.system(size: 13.5))
                .foregroundColor(DS.Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 300, alignment: .leading)
                .padding(.top, DS.Spacing.xxs)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, DS.Spacing.xl)
    }

    // MARK: - Apple

    private var appleSection: some View {
        VStack(spacing: DS.Spacing.sm) {
            AppleSignInButtonView { result in
                handleAppleSignIn(result)
            }
            .opacity(isAppleLoading ? 0.6 : 1)
            .disabled(isAppleLoading)

            if let appleError {
                Text(appleError)
                    .font(.system(size: 12))
                    .foregroundColor(DS.Color.statusMajor)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(.bottom, DS.Spacing.md)
    }

    private func handleAppleSignIn(_ result: Result<AppleSignInPayload, Error>) {
        switch result {
        case .success(let payload):
            isAppleLoading = true
            appleError = nil
            Task {
                do {
                    try await session.signInWithApple(
                        identityToken: payload.identityToken,
                        fullName: payload.fullName
                    )
                } catch {
                    appleError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
                isAppleLoading = false
            }
        case .failure(let error):
            // ASAuthorizationError.canceled est normal : l'utilisateur a fermé
            // la feuille, ce n'est pas une erreur à afficher.
            let nsErr = error as NSError
            if nsErr.domain == ASAuthorizationError.errorDomain,
               nsErr.code == ASAuthorizationError.canceled.rawValue {
                return
            }
            appleError = error.localizedDescription
        }
    }

    // MARK: - Formulaires

    @ViewBuilder
    private var forms: some View {
        ZStack(alignment: .top) {
            if mode == .signin {
                SignInFormSection(email: $email, motDePasse: $motDePasse)
                    .transition(.opacity)
            } else {
                SignUpFormSection(
                    email: $email,
                    motDePasse: $motDePasse,
                    onRequireActivation: onRequireActivation,
                    onGoToSignIn: { select(.signin) }
                )
                .transition(.opacity)
            }
        }
    }

    private func select(_ next: AuthEditorialMode) {
        guard next != mode else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.easeInOut(duration: 0.22)) { mode = next }
    }

    // MARK: - Invité

    private var guestLink: some View {
        HStack {
            Spacer()
            Button(action: onClose) {
                Text(AppLocalizer.string("auth.continue_as_guest", defaultValue: "CONTINUER EN TANT QU’INVITÉ →"))
                    .font(DS.Font.label.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1.5)
            }
            .buttonStyle(.plain)
            Spacer()
        }
        .padding(.top, DS.Spacing.xxl)
    }
}
