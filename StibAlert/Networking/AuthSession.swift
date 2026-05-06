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

    func deconnexion() async {
        try? await AuthService.deconnexion()
        KeychainHelper.deleteToken()
        KeychainHelper.deleteRefreshToken()
        pendingActivationToken = nil
        pendingActivationEmail = nil
        activationSuccessVisible = false
        PushNotificationManager.current?.logoutOneSignal()
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
        state = .signedOut
    }

    func refreshCurrentUser() async {
        guard isSignedIn else { return }
        do {
            let user = try await UtilisateurService.me()
            state = .signedIn(user)
        } catch {
            print("User refresh failed: \(error.localizedDescription)")
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
