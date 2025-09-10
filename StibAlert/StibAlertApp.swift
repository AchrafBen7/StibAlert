      
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

        // 🔍 Debug : lister les polices chargées
        for family in UIFont.familyNames.sorted() {
            let fonts = UIFont.fontNames(forFamilyName: family)
            if !fonts.isEmpty {
                print("📚 \(family): \(fonts)")
            }
        }
    }

    var body: some Scene {
        WindowGroup {
            SplashView()
        }
    }
}
