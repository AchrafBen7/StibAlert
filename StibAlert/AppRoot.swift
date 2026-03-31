//
//  AppRoot.swift
//  StibAlert
//
//  Created by studentehb on 10/09/2025.
//

import SwiftUI

struct AppRoot: View {
    @StateObject private var tabBarVisibility = TabBarVisibility()
    @StateObject private var mainTabSelection = MainTabSelection()

    var body: some View {
        MainTabView()
            .environmentObject(tabBarVisibility)
            .environmentObject(mainTabSelection)
    }
}
