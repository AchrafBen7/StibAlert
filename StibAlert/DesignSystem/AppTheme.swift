import SwiftUI

enum AppTheme {
    enum Palette {
        static let screen = DesignSystem.Palette.screen
        static let screenElevated = DesignSystem.Palette.screenElevated
        static let surface = DesignSystem.Palette.surface
        static let surfaceElevated = DesignSystem.Palette.surfaceElevated
        static let surfaceMuted = DesignSystem.Palette.surfaceMuted
        static let brand = DesignSystem.Palette.brand
        static let brandStrong = DesignSystem.Palette.brandStrong
        static let textPrimary = DesignSystem.Palette.textPrimary
        static let textSecondary = DesignSystem.Palette.textSecondary
        static let textMuted = DesignSystem.Palette.textMuted
        static let textOnBrand = DesignSystem.Palette.textOnBrand
        static let alert = DesignSystem.Palette.alert
        static let warning = DesignSystem.Palette.warning
        static let success = DesignSystem.Palette.success
        static let info = DesignSystem.Palette.info
        static let border = DesignSystem.Palette.border
        static let borderStrong = DesignSystem.Palette.borderStrong
        static let divider = DesignSystem.Palette.divider
        static let overlay = DesignSystem.Palette.overlay
        static let glowBrand = DesignSystem.Palette.glowBrand
        static let glowInfo = DesignSystem.Palette.glowInfo
    }

    enum Colors {
        static let background = DesignSystem.Colors.background
        static let surface = Palette.surface
        static let elevatedSurface = Palette.surfaceElevated
        static let primary = Palette.brandStrong
        static let primarySoft = Palette.surfaceMuted
        static let accent = Palette.brand
        static let textPrimary = Palette.textPrimary
        static let textInverse = Palette.textPrimary
        static let textSecondary = Palette.textSecondary
        static let onboardingBackground = Palette.screen
        static let onboardingTextSecondary = Palette.textSecondary
        static let onboardingTitleBlue = Palette.brandStrong
        static let onboardingTitleSand = Palette.brand
        static let onboardingIndicatorBlue = Palette.brandStrong
        static let onboardingGlowWhite = Palette.glowBrand
        static let onboardingGlowBlue = Palette.glowInfo
        static let danger = Palette.alert
    }

    enum Spacing {
        static let xs: CGFloat = DesignSystem.Spacing.sm
        static let sm: CGFloat = 12
        static let md: CGFloat = DesignSystem.Spacing.md
        static let lg: CGFloat = DesignSystem.Spacing.lg
        static let xl: CGFloat = DesignSystem.Spacing.xl
    }

    enum Radius {
        static let sm: CGFloat = 8
        static let md: CGFloat = 12
        static let lg: CGFloat = 16
        static let xl: CGFloat = 24
    }

    enum Fonts {
        static func clash(_ size: CGFloat) -> Font {
            .custom("ClashDisplay-Variable", size: size)
        }

        static let display = DesignSystem.Typography.display
        static let title1 = DesignSystem.Typography.title1
        static let title2 = DesignSystem.Typography.title2
        static let title3 = DesignSystem.Typography.title3
        static let body = DesignSystem.Typography.body
        static let bodyStrong = DesignSystem.Typography.bodyStrong
        static let caption = DesignSystem.Typography.caption
        static let captionStrong = DesignSystem.Typography.captionStrong

        static func display(_ size: CGFloat) -> Font {
            if size >= 30 { return display }
            if size >= 22 { return title1 }
            if size >= 18 { return title2 }
            return title3
        }

        static func body(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
            if size <= 12 {
                return weight == .regular ? caption : captionStrong
            }
            return weight == .regular ? body : bodyStrong
        }
    }

    enum ButtonHeight {
        static let primary: CGFloat = DesignSystem.Button.primaryHeight
        static let secondary: CGFloat = DesignSystem.Button.secondaryHeight
    }
}
