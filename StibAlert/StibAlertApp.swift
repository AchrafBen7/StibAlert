      
//
//  StibAlertApp.swift
//  StibAlert
//
//  Created by studentehb on 06/03/2025.
//

import SwiftUI
import AppIntents

@main
struct StibAlertApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) private var pushNotificationManager
    @StateObject private var connectivity = NetworkConnectivityMonitor()
    @StateObject private var offlineQueue = OfflineQueueSync()
    @StateObject private var languageStore = AppLanguageStore.shared

    init() {
        ErrorReporting.setUp()
        UITextView.appearance().backgroundColor = .clear
        StibAlertShortcuts.updateAppShortcutParameters()
        if #available(iOS 17.0, *) {
            HomeFeatureTour.configure()
        }
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(connectivity)
                .environmentObject(offlineQueue)
                .environmentObject(languageStore)
                // Re-applies the locale to the whole tree when the user picks a
                // language in Profil → Langues. Reading `languageStore.languageOverride`
                // makes this view depend on the @Published so the env override
                // updates reactively.
                .environment(\.locale, localeForCurrentOverride(languageStore.languageOverride))
                .task {
                    offlineQueue.bind(to: connectivity)
                    await offlineQueue.sync()
                }
        }
    }

    private func localeForCurrentOverride(_ override: String?) -> Locale {
        let code: String
        if let override = override?.lowercased(), !override.isEmpty {
            code = override.hasPrefix("nl") ? "nl_BE" : "fr_BE"
        } else {
            code = AppLocale.localeIdentifier
        }
        return Locale(identifier: code)
    }
}
