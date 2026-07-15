      
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
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ErrorReporting.setUp()
        // Carte calme par défaut. Doit tourner AVANT que la Home ne lise ses
        // @AppStorage : sinon les installations existantes gardent les 4 calques
        // secondaires allumés et ne voient jamais le nouveau défaut.
        MapLayerDefaults.applyCalmDefaultIfNeeded()
        Analytics.start()
        // `App.opened` n'est PLUS émis ici : depuis l'init il ne comptait que le
        // démarrage à froid. La rétention (J+1/J+7) a besoin de CHAQUE retour au
        // premier plan → émis sur scenePhase `.active` (cf. body).
        UIWindow.appearance().overrideUserInterfaceStyle = .light
        UITextView.appearance().backgroundColor = .clear
        StibAlertShortcuts.updateAppShortcutParameters()
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
        .onChange(of: scenePhase) { _, phase in
            // Un `App.opened` par passage au premier plan (démarrage à froid ET
            // retour d'arrière-plan) : c'est ce que TelemetryDeck agrège pour la
            // rétention. Anonyme, aucun paramètre.
            if phase == .active { Analytics.track(.appOpened) }
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
