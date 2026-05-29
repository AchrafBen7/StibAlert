import Foundation

@MainActor
final class AuthSession: ObservableObject {
    enum State: Equatable {
        case unknown
        case signedOut
        case signedIn(UtilisateurDTO)
    }

    @Published private(set) var state: State = .unknown
    @Published var pendingActivationToken: String? = nil
    @Published var pendingActivationEmail: String? = nil
    @Published var activationSuccessVisible = false

    private var sessionExpiredObserver: NSObjectProtocol?

    init() {
        sessionExpiredObserver = NotificationCenter.default.addObserver(
            forName: .sessionExpired,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if self.isSignedIn {
                    KeychainHelper.deleteToken()
                    KeychainHelper.deleteRefreshToken()
                    self.state = .signedOut
                }
            }
        }
    }

    deinit {
        if let observer = sessionExpiredObserver {
            NotificationCenter.default.removeObserver(observer)
        }
    }

    var isSignedIn: Bool {
        if case .signedIn = state { return true }
        return false
    }

    var isGuest: Bool {
        if case .signedOut = state { return true }
        return false
    }

    var currentUser: UtilisateurDTO? {
        if case .signedIn(let u) = state { return u }
        return nil
    }

    func bootstrap() async {
        guard AppConfig.isBackendEnabled else {
            state = .signedOut
            return
        }
        guard KeychainHelper.readToken() != nil else {
            state = .signedOut
            return
        }
        do {
            let user = try await AuthService.me()
            state = .signedIn(user)
            PushNotificationManager.current?.loginOneSignal(userId: user.id)
            await registerForPushIfNeeded(using: user)
        } catch {
            KeychainHelper.deleteToken()
            state = .signedOut
        }
    }

    func inscription(nom: String, email: String, motDePasse: String) async throws {
        let response = try await AuthService.inscription(nom: nom, email: email, motDePasse: motDePasse)
        pendingActivationToken = response.activationToken
        pendingActivationEmail = email
    }

    func activer(code: String) async throws {
        guard let token = pendingActivationToken else {
            throw APIError.server(status: 0, message: "Aucune activation en attente.")
        }
        let auth = try await AuthService.activation(activationToken: token, code: code)
        KeychainHelper.saveToken(auth.token)
        if let refresh = auth.refreshToken { KeychainHelper.saveRefreshToken(refresh) }
        pendingActivationToken = nil
        pendingActivationEmail = nil
        activationSuccessVisible = true
        state = .signedIn(auth.utilisateur)
        PushNotificationManager.current?.loginOneSignal(userId: auth.utilisateur.id)
        await registerForPushIfNeeded(using: auth.utilisateur)
    }

    func renvoyerCode() async throws {
        guard let token = pendingActivationToken else {
            throw APIError.server(status: 0, message: "Aucune activation en attente.")
        }
        let response = try await AuthService.renvoyerCode(activationToken: token)
        pendingActivationToken = response.activationToken
    }

    func connexion(email: String, motDePasse: String) async throws {
        let auth = try await AuthService.connexion(email: email, motDePasse: motDePasse)
        KeychainHelper.saveToken(auth.token)
        if let refresh = auth.refreshToken { KeychainHelper.saveRefreshToken(refresh) }
        state = .signedIn(auth.utilisateur)
        PushNotificationManager.current?.loginOneSignal(userId: auth.utilisateur.id)
        await registerForPushIfNeeded(using: auth.utilisateur)
    }

    func signInWithApple(identityToken: String, fullName: String?) async throws {
        let auth = try await AuthService.appleSignIn(identityToken: identityToken, fullName: fullName)
        KeychainHelper.saveToken(auth.token)
        if let refresh = auth.refreshToken { KeychainHelper.saveRefreshToken(refresh) }
        state = .signedIn(auth.utilisateur)
        PushNotificationManager.current?.loginOneSignal(userId: auth.utilisateur.id)
        await registerForPushIfNeeded(using: auth.utilisateur)
    }

    func deconnexion() async {
        try? await AuthService.deconnexion()
        KeychainHelper.deleteToken()
        KeychainHelper.deleteRefreshToken()
        pendingActivationToken = nil
        pendingActivationEmail = nil
        activationSuccessVisible = false
        PushNotificationManager.current?.logoutOneSignal()
        // B2 — reset des @AppStorage onboarding pour éviter la contamination
        // cross-user (user 1 logout + user 2 login → user 2 sautait
        // l'onboarding et héritait des favoris/routine de user 1 stockés
        // dans @AppStorage globaux).
        Self.clearOnboardingState()
        state = .signedOut
    }

    func supprimerCompte() async throws {
        guard let userId = currentUser?.id else { return }
        try await AuthService.supprimerCompte(userId: userId)
        KeychainHelper.deleteToken()
        KeychainHelper.deleteRefreshToken()
        pendingActivationToken = nil
        pendingActivationEmail = nil
        activationSuccessVisible = false
        PushNotificationManager.current?.logoutOneSignal()
        Self.clearOnboardingState()
        state = .signedOut
    }

    /// B2 — reset des @AppStorage liés à l'onboarding au logout / delete.
    /// Le tour `hasSeenFeatureTour` est aussi réinitialisé pour que le
    /// prochain compte voie les 3 cards d'explication.
    private static func clearOnboardingState() {
        let defaults = UserDefaults.standard
        let keysToWipe: [String] = [
            AppStorageKeys.hasSeenOnboarding,
            AppStorageKeys.hasSeenFeatureTour,
            AppStorageKeys.onboardingFavoriteLines,
            AppStorageKeys.onboardingStibFavoriteStops,
            AppStorageKeys.onboardingHomeLabel,
            AppStorageKeys.onboardingDepartureTime,
            AppStorageKeys.onboardingNeedsProfileSync,
            AppStorageKeys.onboardingLastAppliedUserId,
            AppStorageKeys.onboardingPendingPushPermission,
        ]
        for key in keysToWipe { defaults.removeObject(forKey: key) }
    }

    func refreshCurrentUser() async {
        guard isSignedIn else { return }
        do {
            let user = try await UtilisateurService.me()
            state = .signedIn(user)
        } catch {
            ErrorReporting.capture(error, tag: "auth.userRefresh")
        }
    }

    func applyCurrentUserUpdate(_ user: UtilisateurDTO) {
        state = .signedIn(user)
    }

    private func registerForPushIfNeeded(using user: UtilisateurDTO) async {
        guard user.notifications ?? true else { return }
        await PushNotificationManager.current?.requestAuthorizationAndRegister()
    }
}
