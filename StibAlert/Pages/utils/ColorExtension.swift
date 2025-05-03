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
    
    /// ✅ Couleur orange utilisée pour l'arrêt sélectionné
    static let selectedStopOrange = Color(hex: "#F9C06B")
    
    /// ✅ Fait une couleur plus foncée d’un pourcentage donné (pour les overlays/bordures)
    func darker(by percentage: CGFloat = 30.0) -> Color {
        return Color(UIColor(self).darker(by: percentage))
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
