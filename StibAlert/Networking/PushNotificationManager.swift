import Foundation
import UIKit
import UserNotifications

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
        return true
    }

    func requestAuthorizationAndRegister() async {
        guard AppConfig.isBackendEnabled else { return }

        do {
            let granted = try await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            guard granted else { return }
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
        } catch {
            print("Push auth error: \(error.localizedDescription)")
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        let token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task {
            do {
                try await UtilisateurService.enregistrerTokenPush(token)
            } catch {
                print("Push token registration failed: \(error.localizedDescription)")
            }
        }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("APNs registration failed: \(error.localizedDescription)")
    }
}
