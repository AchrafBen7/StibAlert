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
        Task {
            do {
                try await UtilisateurService.enregistrerTokenPush(token)
                await registerCurrentOneSignalPlayerIdIfAvailable()
            } catch {
                ErrorReporting.capture(error, tag: "push.tokenRegistration")
            }
        }
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
        Task { await registerCurrentOneSignalPlayerIdIfAvailable() }
#endif
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
        let additionalData = event.notification.additionalData ?? [:]
        NotificationCenter.default.post(name: .pushOpened, object: nil, userInfo: additionalData)
    }
}
#endif
