//
//  StibAlertApp.swift
//  StibAlert
//
//  Created by studentehb on 06/03/2025.
//

import SwiftUI

@main
struct StibAlertApp: App {
    init() {
        // ✅ Essentiel pour que le TextEditor ne masque pas le placeholder
        UITextView.appearance().backgroundColor = .clear
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }
}


