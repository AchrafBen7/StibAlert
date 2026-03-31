import SwiftUI

enum AppTheme {
    enum Colors {
        static let background = DesignSystem.Colors.background
        static let surface = DesignSystem.Colors.accentSoft
        static let elevatedSurface = DesignSystem.Colors.cardBackground
        static let primary = DesignSystem.Colors.primary
        static let primarySoft = DesignSystem.Colors.accent
        static let accent = DesignSystem.Colors.accentSand
        static let textPrimary = DesignSystem.Colors.primaryText
        static let textInverse = Color.white
        static let textSecondary = DesignSystem.Colors.secondaryText
        static let onboardingBackground = Color(hex: "#0B111E")
        static let onboardingTextSecondary = Color.white.opacity(0.7)
        static let onboardingTitleBlue = Color(hex: "#CADBFF")
        static let onboardingTitleSand = Color(hex: "#CBC1AD")
        static let onboardingIndicatorBlue = Color(hex: "#B5CFF8")
        static let onboardingGlowWhite = Color(hexRGB: "#BBC9DC", alpha: 0.90)
        static let onboardingGlowBlue = Color(hexRGB: "#7487B0", alpha: 1.0)
        static let danger = DesignSystem.Colors.error
    }

    enum Spacing {
        static let xs: CGFloat = DesignSystem.Spacing.sm
        static let sm: CGFloat = 12
        static let md: CGFloat = DesignSystem.Spacing.md
        static let lg: CGFloat = DesignSystem.Spacing.lg
        static let xl: CGFloat = DesignSystem.Spacing.xl
    }

    enum Radius {
        static let sm: CGFloat = DesignSystem.CornerRadius.small
        static let md: CGFloat = DesignSystem.CornerRadius.medium
        static let lg: CGFloat = DesignSystem.CornerRadius.large
        static let xl: CGFloat = DesignSystem.CornerRadius.xlarge
    }

    enum Fonts {
        static func display(_ size: CGFloat) -> Font {
            .custom("DelaGothicOne-Regular", size: size)
        }

        static func clash(_ size: CGFloat) -> Font {
            .custom("ClashDisplay-Variable", size: size)
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
