//
//  ColorExtension.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//


import SwiftUI

import SwiftUI

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .whitespacesAndNewlines))
        var rgbValue: UInt64 = 0
        // Si le caractère "#" est présent, le scanner l'ignore
        scanner.scanString("#", into: nil)
        scanner.scanHexInt64(&rgbValue)
        
        let r = (rgbValue >> 16) & 0xff
        let g = (rgbValue >> 8) & 0xff
        let b = rgbValue & 0xff
        
        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: 1
        )
    }
}


