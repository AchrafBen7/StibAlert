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

    /// Lignes favorites RÉELLEMENT en vigueur, compte ou pas.
    ///
    /// L'onboarding fait choisir jusqu'à 6 lignes AVANT toute création de
    /// compte. Ces choix étaient bien enregistrés localement, mais
    /// `applyOnboardingPreferencesIfNeeded` commence par
    /// `guard let user = session.currentUser` : sans compte, ils n'étaient
    /// jamais appliqués. Et tout le reste de l'app lisait
    /// `currentUser?.favoriteLines`. Résultat pour un invité : il choisit
    /// 6 lignes, et l'app se comporte comme s'il n'en avait aucune — carte non
    /// filtrée, aucune alerte ciblée, compteur à zéro.
    ///
    /// Les préférences locales ne servent QUE de repli : dès qu'un compte
    /// existe, c'est lui qui fait foi (il se synchronise entre appareils).
    var effectiveFavoriteLines: [String] {
        if let lines = currentUser?.favoriteLines, !lines.isEmpty { return lines }
        return OnboardingPreferenceStore.load().favoriteLines
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
            cacheUser(user)
            state = .signedIn(user)
            PushNotificationManager.current?.loginOneSignal(userId: user.id)
            await registerForPushIfNeeded(using: user)
        } catch {
            // ⚠️ NE PAS supprimer le jeton sur n'importe quelle erreur.
            //
            // Cette branche faisait `KeychainHelper.deleteToken()` quoi qu'il
            // arrive. Ouvrir l'app dans le métro, sans réseau, DÉCONNECTAIT
            // donc l'utilisateur pour de bon : au retour du réseau il devait
            // ressaisir son mot de passe, et entre-temps il perdait ses
            // favoris, ses alertes et le signalement.
            //
            // Seul un refus explicite du serveur signifie « ce jeton est
            // mort ». `APIError` distingue déjà les deux cas.
            if Self.isAuthFailure(error) {
                KeychainHelper.deleteToken()
                KeychainHelper.deleteRefreshToken()
                clearCachedUser()
                state = .signedOut
            } else if let cached = Self.cachedUser() {
                // Réseau absent ou réponse illisible : on repart du dernier
                // profil connu. Il sera remplacé dès que `/me` répondra.
                state = .signedIn(cached)
            } else {
                // Jeton CONSERVÉ : le prochain lancement avec du réseau
                // rétablira la session sans redemander le mot de passe.
                state = .signedOut
            }
        }
    }

    /// Seul un refus explicite du serveur (401/403) veut dire « jeton mort ».
    /// Une coupure réseau, un DNS absent ou un champ inattendu n'en sont pas.
    private static func isAuthFailure(_ error: Error) -> Bool {
        switch error {
        case APIError.unauthorized:
            return true
        case APIError.server(let status, _):
            return status == 401 || status == 403
        default:
            return false
        }
    }

    // MARK: - Profil mis en cache (repli hors ligne)

    private static let cachedUserKey = "blayse.cachedUser"

    /// Le profil sert UNIQUEMENT d'affichage de repli au démarrage sans
    /// réseau. Le jeton reste la seule preuve d'authentification.
    private func cacheUser(_ user: UtilisateurDTO) {
        guard let data = try? JSONEncoder().encode(user) else { return }
        UserDefaults.standard.set(data, forKey: Self.cachedUserKey)
    }

    private static func cachedUser() -> UtilisateurDTO? {
        guard let data = UserDefaults.standard.data(forKey: cachedUserKey) else { return nil }
        return try? JSONDecoder().decode(UtilisateurDTO.self, from: data)
    }

    private func clearCachedUser() {
        UserDefaults.standard.removeObject(forKey: Self.cachedUserKey)
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
        await refreshFullUserAfterAuth()
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
        await refreshFullUserAfterAuth()
    }


    /// La réponse de `/connexion` ne renvoie PAS `favorisDetails` : elle sérialise le
    /// document Mongo brut, où `favoris` n'est qu'une liste d'identifiants. Seul
    /// `/me` fait le `populate` + `buildFavorisDetails`.
    ///
    /// Sans ce rechargement, le Profil affichait « 0 Favoris » juste après la
    /// connexion (le compteur lit `favorisDetails`) — et ne se réparait qu'au
    /// prochain lancement de l'app, quand `bootstrap()` appelle enfin `/me`.
    ///
    /// On ne fait PAS échouer la connexion si ce rafraîchissement rate : l'utilisateur
    /// est authentifié, il verra juste des données partielles jusqu'au prochain lancement.
    private func refreshFullUserAfterAuth() async {
        if let full = try? await AuthService.me() {
            state = .signedIn(full)
        }
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
        do {
            try await AuthService.deconnexion()
        } catch {
            ErrorReporting.capture(error, tag: "auth.deconnexion")
        }
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
        clearCachedUser()
        state = .signedOut
    }

    /// B2 — reset des @AppStorage liés à l'onboarding au logout / delete.
    ///
    /// C'est `hasSeenHomeCoachMarks` qu'on réinitialise, pour que le prochain
    /// compte ait droit à la visite. La liste ne remettait à zéro que l'ANCIEN
    /// tour plein écran (`hasSeenFeatureTour`, supprimé depuis) : sans ce
    /// changement, un nouveau compte n'aurait plus eu aucune visite du tout.
    private static func clearOnboardingState() {
        let defaults = UserDefaults.standard
        let keysToWipe: [String] = [
            AppStorageKeys.hasSeenOnboarding,
            AppStorageKeys.hasSeenHomeCoachMarks,
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
            cacheUser(user)
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
