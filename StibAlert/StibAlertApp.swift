      
//
//  StibAlertApp.swift
//  StibAlert
//
//  Created by studentehb on 06/03/2025.
//

import SwiftUI
import AppIntents
import UIKit

@main
struct StibAlertApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) private var pushNotificationManager
    @StateObject private var connectivity = NetworkConnectivityMonitor()
    @StateObject private var offlineQueue = OfflineQueueSync()
    @StateObject private var languageStore = AppLanguageStore.shared

    init() {
        ErrorReporting.setUp()
        Analytics.start()
        Analytics.track(.appOpened)
        UIWindow.appearance().overrideUserInterfaceStyle = .light
        UITextView.appearance().backgroundColor = .clear
        StibAlertShortcuts.updateAppShortcutParameters()
        // Pre-warm Speech framework hors thread main pour éviter le freeze
        // ~300 ms au 1er tap du bouton micro. Idempotent et silent fail.
        VoiceAssistant.prewarm()
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(connectivity)
                .environmentObject(offlineQueue)
                .environmentObject(languageStore)
                .preferredColorScheme(.light)
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
