import SwiftUI

struct AppRoot: View {
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = AuthSession()
    @AppStorage(AppStorageKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppStorageKeys.onboardingPendingPushPermission) private var onboardingPendingPushPermission = false
    @AppStorage(AppStorageKeys.hasAcceptedPrivacyConsent) private var hasAcceptedPrivacyConsent = false
    @AppStorage(AppStorageKeys.privacyConsentVersion) private var privacyConsentVersion = ""

    var body: some View {
        content
            .environmentObject(nav)
            .environmentObject(session)
            .fullScreenCover(isPresented: $nav.showAuthFlow) {
                AuthFlowView(initialRoute: nav.authInitialRoute)
                    .environmentObject(session)
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
                await applyOnboardingPreferencesIfNeeded()
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
                    ProgressView().tint(.white)
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
                HomeView()
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
