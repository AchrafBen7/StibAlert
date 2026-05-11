      
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

    init() {
        UITextView.appearance().backgroundColor = .clear
        StibAlertShortcuts.updateAppShortcutParameters()
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
                .environmentObject(connectivity)
        }
    }
}
