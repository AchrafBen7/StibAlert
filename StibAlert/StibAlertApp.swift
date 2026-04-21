      
//
//  StibAlertApp.swift
//  StibAlert
//
//  Created by studentehb on 06/03/2025.
//

import SwiftUI

@main
struct StibAlertApp: App {
    @UIApplicationDelegateAdaptor(PushNotificationManager.self) private var pushNotificationManager

    init() {
        UITextView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }
}
