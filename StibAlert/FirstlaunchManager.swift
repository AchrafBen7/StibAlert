//
//  FirstlaunchManager.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.
//

import Foundation

struct FirstLaunchManager {
    static func checkFirstLaunch() -> Bool {
        let hasLaunchedBefore = UserDefaults.standard.bool(forKey: "hasLaunchedBefore")
        if !hasLaunchedBefore {
            UserDefaults.standard.set(true, forKey: "hasLaunchedBefore")
        }
        return !hasLaunchedBefore
    }
}
