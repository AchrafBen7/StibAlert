import SwiftUI

enum AppTheme {
    enum Colors {
        static let background = Color(hex: "#FAFAFD")
        static let surface = Color(hex: "#F0F0F0")
        static let elevatedSurface = Color.white
        static let primary = Color(hex: "#2D2C6F")
        static let primarySoft = Color(hex: "#4557A1")
        static let accent = Color(hex: "#F18F5D")
        static let textPrimary = Color.black
        static let textInverse = Color.white
        static let textSecondary = Color.gray
        static let onboardingBackground = Color(hex: "#2F2E2E")
        static let onboardingTextSecondary = Color.white.opacity(0.7)
        static let danger = Color.red
    }

    enum Spacing {
        static let xs: CGFloat = 8
        static let sm: CGFloat = 12
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
    }

    enum Radius {
        static let sm: CGFloat = 10
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 48
    }

    enum Fonts {
        static func display(_ size: CGFloat) -> Font {
            .custom("DelaGothicOne-Regular", size: size)
        }

        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            switch weight {
            case .semibold, .bold:
                return .custom("Montserrat-SemiBold", size: size)
            default:
                return .custom("Montserrat-Regular", size: size)
            }
        }
    }
}
