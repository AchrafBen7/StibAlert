//
//  AppRoot.swift
//  StibAlert
//
//  Created by studentehb on 10/09/2025.
//

import SwiftUI

struct AppRoot: View {
    @AppStorage("hasSeenOnboarding") private var hasSeenOnboarding = false

    var body: some View {
        Group {
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            } else {
                Home()
            }
        }
        .preferredColorScheme(.dark)
    }
}


