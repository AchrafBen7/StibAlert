import SwiftUI

struct AppRoot: View {
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = AuthSession()
    @AppStorage(AppStorageKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppStorageKeys.hasSeenFeatureTour) private var hasSeenFeatureTour = false
    @AppStorage(AppStorageKeys.onboardingPendingPushPermission) private var onboardingPendingPushPermission = false
    @AppStorage(AppStorageKeys.hasAcceptedPrivacyConsent) private var hasAcceptedPrivacyConsent = false
    @AppStorage(AppStorageKeys.privacyConsentVersion) private var privacyConsentVersion = ""
    /// #3 — debounce de la synchro des favoris multi-opérateurs.
    @State private var favSyncTask: Task<Void, Never>?
    /// B4 — true une fois qu'on a adopté/seedé l'état serveur des favoris
    /// (évite d'effacer les favoris locaux d'un compte legacy au 1er run).
    @AppStorage("operatorFavoritesServerSynced") private var operatorFavoritesServerSynced = false

    var body: some View {
        content
            .preferredColorScheme(.light)
            .environmentObject(nav)
            .environmentObject(session)
            .fullScreenCover(isPresented: $nav.showAuthFlow) {
                AuthFlowView(initialRoute: nav.authInitialRoute)
                    .environmentObject(session)
            }
            // Visite guidée 3-cards montrée UNE FOIS quand l'utilisateur a
            // fini son onboarding (favoris, etc.) mais n'a pas encore vu
            // les explications produit (carte / signalement / voix). Cf.
            // FeatureTourView. Réinitialisable depuis Profil.
            .fullScreenCover(isPresented: shouldShowFeatureTour) {
                FeatureTourView { hasSeenFeatureTour = true }
            }
            .onChange(of: session.isSignedIn) { _, signedIn in
                guard signedIn else { return }
                if session.activationSuccessVisible {
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 1_200_000_000)
                        session.activationSuccessVisible = false
                        nav.showAuthFlow = false
                        nav.authInitialRoute = nil
                    }
                } else {
                    nav.showAuthFlow = false
                    nav.authInitialRoute = nil
                }
            }
            .task { await session.bootstrap() }
            .task(id: session.currentUser?.id) {
                // B4 — Favoris multi-opérateurs : le serveur est AUTORITAIRE
                // (remplace le cache local) pour que les suppressions se
                // propagent cross-device. Garde anti-wipe : si on n'a jamais
                // synchronisé ET que le serveur est vide mais qu'on a des
                // favoris locaux (compte legacy), on SEED le serveur depuis le
                // local au lieu d'effacer.
                if session.currentUser != nil {
                    let serverFavs = session.currentUser?.operatorFavorites ?? []
                    if operatorFavoritesServerSynced || !serverFavs.isEmpty {
                        OperatorStopFavorites.shared.replaceFromServer(serverFavs)
                        SNCBGareFavorites.shared.replaceFromServer(serverFavs)
                        operatorFavoritesServerSynced = true
                    } else {
                        // 1er run, serveur vide : seed depuis le local s'il existe.
                        operatorFavoritesServerSynced = true
                        let localCombined = OperatorStopFavorites.shared.snapshotDTO()
                            + SNCBGareFavorites.shared.snapshotDTO()
                        if !localCombined.isEmpty {
                            NotificationCenter.default.post(name: .operatorFavoritesDidChange, object: nil)
                        }
                    }
                }
                await applyOnboardingPreferencesIfNeeded()
            }
            .onReceive(NotificationCenter.default.publisher(for: .operatorFavoritesDidChange)) { _ in
                // #3 — Pousse les favoris (De Lijn/TEC/SNCB) au serveur, debounce
                // 0,8 s pour éviter un PATCH par tap rapide. Offline-first :
                // l'échec réseau ne casse rien (cache local intact).
                guard let userId = session.currentUser?.id else { return }
                favSyncTask?.cancel()
                favSyncTask = Task {
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    guard !Task.isCancelled else { return }
                    let combined = OperatorStopFavorites.shared.snapshotDTO()
                        + SNCBGareFavorites.shared.snapshotDTO()
                    if let updated = try? await UtilisateurService.mettreAJourProfil(
                        userId: userId,
                        operatorFavorites: combined
                    ) {
                        await MainActor.run { session.applyCurrentUserUpdate(updated) }
                    }
                }
            }
            .onReceive(NotificationCenter.default.publisher(for: .pushOpened)) { output in
                handlePush(userInfo: output.userInfo)
            }
            .onOpenURL { url in
                guard session.state != .unknown, let link = DeepLinkRouter.parse(url) else { return }
                applyDeepLink(link)
            }
    }

    private var needsPrivacyConsent: Bool {
        !hasAcceptedPrivacyConsent || privacyConsentVersion != PrivacyConsent.currentVersion
    }

    /// Tour produit (3 cards) — montré uniquement quand l'utilisateur est
    /// arrivé sur Home après tous les preliminary screens, et qu'il ne l'a
    /// pas encore vu. Évite de l'afficher pendant la phase de chargement /
    /// pendant l'AuthFlow.
    private var shouldShowFeatureTour: Binding<Bool> {
        Binding(
            get: {
                hasAcceptedPrivacyConsent
                && privacyConsentVersion == PrivacyConsent.currentVersion
                && hasSeenOnboarding
                && !hasSeenFeatureTour
                && !nav.showAuthFlow
                && session.isSignedIn
            },
            set: { newValue in
                if !newValue { hasSeenFeatureTour = true }
            }
        )
    }

    @ViewBuilder
    private var content: some View {
        if needsPrivacyConsent {
            PrivacyConsentView { _ in
                // AppStorage is auto-updated by PrivacyConsentView
            }
        } else {
            switch session.state {
            case .unknown:
                ZStack {
                    DS.Color.background.ignoresSafeArea()
                    VStack(spacing: 14) {
                        ProgressView()
                            .tint(DS.Color.ink)
                            .scaleEffect(1.3)
                        Text("Connexion…")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
            case .signedOut:
                if !hasSeenOnboarding {
                    OnboardingView {
                        hasSeenOnboarding = true
                    }
                } else {
                    HomeView()
                }
            case .signedIn:
                // New sign-ups also go through onboarding (favorites picker)
                // until they've completed it once on this device, otherwise the
                // tester lands on an empty Favoris/Map and never sees the setup.
                if !hasSeenOnboarding {
                    OnboardingView {
                        hasSeenOnboarding = true
                    }
                } else {
                    HomeView()
                }
            }
        }
    }

    private func handlePush(userInfo: [AnyHashable: Any]?) {
        guard case .signedIn = session.state else { return }
        let raw = DeepLinkRouter.extractRawDeepLink(from: userInfo)
        let link = DeepLinkRouter.parse(raw) ?? .home
        applyDeepLink(link)
    }

    func applyDeepLink(_ link: DeepLink) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            switch link {
            case .home:
                nav.currentPage = .home
            case .line:
                nav.currentPage = .signalements
            case .signalements, .signalementDetail:
                nav.currentPage = .reports
            case .favorites:
                nav.currentPage = .favorites
            case .profile:
                nav.currentPage = .profile
            case .report:
                nav.currentPage = .home
                nav.showReportSheet = true
            case .clusterDetail(let clusterIndex):
                // BUG #3 — bascule sur Home + pose le clusterIndex pour que
                // HomeView ouvre la sheet detail au prochain render.
                nav.currentPage = .home
                nav.pendingClusterFocusIndex = Int(clusterIndex)
            case .route(let fromName, let fromLat, let fromLng, let toName, let toLat, let toLng):
                nav.currentPage = .home
                NotificationCenter.default.post(
                    name: .routeDeepLink,
                    object: nil,
                    userInfo: [
                        "fromName": fromName, "fromLat": fromLat, "fromLng": fromLng,
                        "toName": toName, "toLat": toLat, "toLng": toLng
                    ]
                )
            }
        }
    }

    private func applyOnboardingPreferencesIfNeeded() async {
        guard let user = session.currentUser else { return }
        guard OnboardingPreferenceStore.shouldApply(for: user.id) else { return }

        let preferences = OnboardingPreferenceStore.load()
        guard preferences.hasUsefulData else {
            OnboardingPreferenceStore.markApplied(for: user.id)
            return
        }

        do {
            let updated = try await UtilisateurService.mettreAJourProfil(
                userId: user.id,
                favoriteLines: preferences.favoriteLines,
                routine: CommuteRoutineDTO(
                    enabled: true,
                    homeLabel: preferences.homeLabel.isEmpty ? "Domicile" : preferences.homeLabel,
                    workLabel: user.routine?.workLabel ?? "Travail",
                    departureTime: preferences.departureTime,
                    homeStopId: user.routine?.homeStopId,
                    workStopId: user.routine?.workStopId
                )
            )
            session.applyCurrentUserUpdate(updated)

            // Apply STIB favourite stops picked during onboarding. Dedupe
            // against the user's current favouris so we don't accidentally
            // toggle (= remove) an already-favourited stop.
            let alreadyFav = Set(updated.favoris ?? [])
            var didToggle = false
            for stopId in preferences.stibFavoriteStopIds where !alreadyFav.contains(stopId) {
                do {
                    _ = try await UtilisateurService.toggleFavori(userId: user.id, arretId: stopId)
                    didToggle = true
                } catch {
                    ErrorReporting.capture(error, tag: "onboarding.applyFavorites", context: ["stopId": stopId])
                }
            }
            if didToggle {
                await session.refreshCurrentUser()
            }

            OnboardingPreferenceStore.markApplied(for: user.id)
            await requestDeferredPushPermissionIfNeeded()
        } catch {
            ErrorReporting.capture(error, tag: "appRoot.onboardingSync")
        }
    }

    private func requestDeferredPushPermissionIfNeeded() async {
        guard session.isSignedIn else { return }
        await PushNotificationManager.current?.requestAuthorizationAndRegister()
    }
}
