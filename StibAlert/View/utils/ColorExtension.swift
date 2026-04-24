//
//  ColorExtension.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

import SwiftUI

extension Color {
    init(hex: String) {
        let scanner = Scanner(string: hex.trimmingCharacters(in: .whitespacesAndNewlines))
        var rgbValue: UInt64 = 0
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

    init(hexRGB: String, alpha: Double = 1.0) {
        let clean = hexRGB.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: clean).scanHexInt64(&int)

        let r, g, b: UInt64
        switch clean.count {
        case 3:
            r = (int >> 8) * 17
            g = (int >> 4 & 0xF) * 17
            b = (int & 0xF) * 17
        default:
            r = (int >> 16) & 0xFF
            g = (int >> 8) & 0xFF
            b = int & 0xFF
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: alpha
        )
    }

    static let selectedStopOrange = Color(hex: "#F9C06B")

    func darker(by percentage: CGFloat = 30.0) -> Color {
        return Color(UIColor(self).darker(by: percentage))
    }

    var isDark: Bool {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        UIColor(self).getRed(&r, green: &g, blue: &b, alpha: &a)
        let luminance = 0.299 * r + 0.587 * g + 0.114 * b
        return luminance < 0.55
    }
}

extension UIColor {
    func darker(by percentage: CGFloat = 30.0) -> UIColor {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        if getRed(&r, green: &g, blue: &b, alpha: &a) {
            return UIColor(
                red: max(r - percentage / 100, 0.0),
                green: max(g - percentage / 100, 0.0),
                blue: max(b - percentage / 100, 0.0),
                alpha: a
            )
        }
        return self
    }
}
