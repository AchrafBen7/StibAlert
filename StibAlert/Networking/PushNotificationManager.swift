import Foundation
import UIKit
import UserNotifications
#if canImport(OneSignalFramework)
import OneSignalFramework
#endif

extension Notification.Name {
    static let pushOpened = Notification.Name("pushOpened")
    static let routeDeepLink = Notification.Name("routeDeepLink")
}

final class PushNotificationManager: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    static weak var current: PushNotificationManager?

    override init() {
        super.init()
        Self.current = self
    }

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        configureOneSignal(launchOptions: launchOptions)
        return true
    }

    func requestAuthorizationAndRegister() async {
        guard AppConfig.isBackendEnabled else { return }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
#if canImport(OneSignalFramework)
            OneSignal.Notifications.requestPermission({ _ in }, fallbackToSettings: false)
#endif
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            ErrorReporting.capture(error, tag: "push.authRequest")
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        // APNs nous appelle dès qu'il a un token, indépendamment de l'état
        // auth de l'app. Si l'utilisateur n'est pas encore loggé (mode guest
        // ou avant connexion), on ne peut PAS appeler /enregistrer-token
        // qui exige un JWT → 401 dans les logs Render. On stocke le token
        // en local et `flushPendingPushToken()` le rejoue après login.
        Self.storePendingAPNsToken(token)
        Task {
            await flushPendingPushTokenIfAuthenticated()
        }
    }

    /// Appelé par AuthSession après chaque login réussi → rejoue
    /// l'enregistrement du token push si l'APNs nous l'avait donné avant
    /// que l'utilisateur soit authentifié.
    func flushPendingPushTokenIfAuthenticated() async {
        guard KeychainHelper.readToken() != nil else { return }
        let pending = Self.pendingAPNsToken()
        guard pending != nil || OneSignalPlayerIdNonEmpty() else { return }
        do {
            if let pending {
                try await UtilisateurService.enregistrerTokenPush(pending)
            }
            await registerCurrentOneSignalPlayerIdIfAvailable()
            Self.clearPendingAPNsToken()
        } catch {
            // On garde le pending pour retry au prochain login.
            ErrorReporting.capture(error, tag: "push.tokenRegistration")
        }
    }

    private func OneSignalPlayerIdNonEmpty() -> Bool {
#if canImport(OneSignalFramework)
        let id = OneSignal.User.pushSubscription.id
        return id?.isEmpty == false
#else
        return false
#endif
    }

    // MARK: - Pending APNs token persistence

    private static let pendingTokenKey = "stibalert.pendingAPNsToken"

    private static func storePendingAPNsToken(_ token: String) {
        UserDefaults.standard.set(token, forKey: pendingTokenKey)
    }

    private static func pendingAPNsToken() -> String? {
        UserDefaults.standard.string(forKey: pendingTokenKey)
    }

    private static func clearPendingAPNsToken() {
        UserDefaults.standard.removeObject(forKey: pendingTokenKey)
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        ErrorReporting.capture(error, tag: "push.apnsRegistration")
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound, .badge])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        NotificationCenter.default.post(name: .pushOpened, object: nil, userInfo: response.notification.request.content.userInfo)
        completionHandler()
    }

    func loginOneSignal(userId: String) {
#if canImport(OneSignalFramework)
        OneSignal.login(userId)
#endif
        // Quel que soit l'état OneSignal, on retente l'enregistrement du
        // token APNs (qui peut avoir été reçu avant la connexion utilisateur)
        // maintenant qu'on a un JWT en keychain.
        Task {
            await flushPendingPushTokenIfAuthenticated()
        }
    }

    func logoutOneSignal() {
#if canImport(OneSignalFramework)
        OneSignal.logout()
#endif
    }

    private func configureOneSignal(launchOptions: [UIApplication.LaunchOptionsKey: Any]?) {
#if canImport(OneSignalFramework)
        guard let appId = Bundle.main.object(forInfoDictionaryKey: "OneSignalAppID") as? String,
              !appId.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return
        }
        // OneSignal.initialize() does sync I/O (reads provisioning profile,
        // ~3KB log dump) + network during didFinishLaunching → 12 s hang at
        // cold start. Defer to the next run-loop tick so the first frame
        // ships before OneSignal does its setup. Push registration still
        // succeeds; we just don't block launch on it.
        DispatchQueue.main.async {
            #if DEBUG
            OneSignal.Debug.setLogLevel(.LL_ERROR)
            #endif
            OneSignal.initialize(appId, withLaunchOptions: launchOptions)
            OneSignal.Notifications.addClickListener(self)
        }
#endif
    }

    private func registerCurrentOneSignalPlayerIdIfAvailable() async {
#if canImport(OneSignalFramework)
        let playerId = OneSignal.User.pushSubscription.id
        guard let playerId, !playerId.isEmpty else { return }
        do {
            try await UtilisateurService.enregistrerTokenPush(oneSignalPlayerId: playerId)
        } catch {
            ErrorReporting.capture(error, tag: "push.oneSignalRegistration")
        }
#endif
    }
}

#if canImport(OneSignalFramework)
extension PushNotificationManager: OSNotificationClickListener {
    func onClick(event: OSNotificationClickEvent) {
        Analytics.track(.pushOpened)
        let additionalData = event.notification.additionalData ?? [:]
        NotificationCenter.default.post(name: .pushOpened, object: nil, userInfo: additionalData)
    }
}
#endif
