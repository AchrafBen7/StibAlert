import SwiftUI
import UIKit

struct DesignSystem {
    struct Palette {
        static let screen = Color(hex: "#0F141D")
        static let screenElevated = Color(hex: "#151C27")
        static let surface = Color(hex: "#1A2330")
        static let surfaceElevated = Color(hex: "#202B3A")
        static let surfaceMuted = Color(hex: "#263244")

        static let brand = Color(hex: "#CFC3AE")
        static let brandStrong = Color(hex: "#B9CFFF")

        static let textPrimary = Color.white
        static let textSecondary = Color.white.opacity(0.72)
        static let textMuted = Color.white.opacity(0.52)
        static let textOnBrand = Color(hex: "#11151D")

        static let alert = Color(hex: "#FF7A7A")
        static let warning = Color(hex: "#FF9B2F")
        static let success = Color(hex: "#57E3B6")
        static let info = Color(hex: "#7DB2FF")

        static let border = Color.white.opacity(0.08)
        static let borderStrong = Color.white.opacity(0.16)
        static let divider = Color.white.opacity(0.08)
        static let overlay = Color.black.opacity(0.42)

        static let glowBrand = Color(hexRGB: "#BBC9DC", alpha: 0.90)
        static let glowInfo = Color(hexRGB: "#7487B0", alpha: 1.0)
    }

    struct Colors {
        static let primary = Palette.textPrimary
        static let primaryText = Palette.textPrimary
        static let secondaryText = Palette.textSecondary

        static let accent = Palette.brandStrong
        static let accentBlue = Palette.brandStrong
        static let accentSoft = Palette.surfaceMuted
        static let accentSand = Palette.brand

        static let background = Palette.screen
        static let cardBackground = Palette.surface
        static let overlayBackground = Palette.overlay

        static let success = Palette.success
        static let warning = Palette.warning
        static let error = Palette.alert
        static let info = Palette.info

        static let border = Palette.border
        static let borderStrong = Palette.borderStrong
        static let dividerLight = Palette.divider

        static let homeFilterSelectedBg = Palette.surfaceElevated
        static let homeFilterUnselected = Palette.textMuted
        static let contentTabSelected = Palette.textPrimary
        static let contentTabUnselected = Palette.textMuted
        static let homeProviderCardOverlay = Color.black.opacity(0.16)
        static let bookingsHeroOverlay = Color.black.opacity(0.22)

        static let tabBarBackground = Palette.surface
        static let tabBarActive = Palette.brandStrong
        static let tabBarInactive = Palette.textMuted

        static let shadow = Color.black.opacity(0.18)
        static let shadowMedium = Color.black.opacity(0.26)
        static let shadowStrong = Color.black.opacity(0.38)
    }

    struct Typography {
        static let display = Font.custom("DelaGothicOne-Regular", size: 32, relativeTo: .largeTitle)
        static let title1 = Font.custom("DelaGothicOne-Regular", size: 24, relativeTo: .title)
        static let title2 = Font.custom("DelaGothicOne-Regular", size: 20, relativeTo: .title2)
        static let title3 = Font.custom("Montserrat-SemiBold", size: 16, relativeTo: .headline)
        static let body = Font.custom("Montserrat-Regular", size: 15, relativeTo: .body)
        static let bodyStrong = Font.custom("Montserrat-SemiBold", size: 15, relativeTo: .body)
        static let caption = Font.custom("Montserrat-Regular", size: 12, relativeTo: .caption)
        static let captionStrong = Font.custom("Montserrat-SemiBold", size: 12, relativeTo: .caption)

        static let heroTitle = display
        static let title = display
        static let pageTitle = display
        static let navigationTitle = title1
        static let heroTitleLarge = display

        static let sectionTitle = title1
        static let sectionTitleSmall = title3
        static let homeSectionTitle = title3
        static let pageTitlePoppins = title1
        static let pageSubtitlePoppins = body

        static let heading32 = display
        static let heading32Bold = display
        static let heading26Bold = title1
        static let heading28 = title1
        static let heading28Regular = title1
        static let heading24Semibold = title1
        static let heading22 = title2
        static let heading22Medium = title2

        static let cardTitle = title3
        static let cardTitleMedium = title3
        static let cardTitleSemibold = title3
        static let cardTitleBold = title3

        static let subtitle = body
        static let subtitleMedium = bodyStrong
        static let subtitleSemibold = bodyStrong
        static let subtitleBold = bodyStrong

        static let body17 = body
        static let body17Medium = bodyStrong
        static let bodyMedium = bodyStrong
        static let bodySemibold = bodyStrong
        static let bodyBold = bodyStrong
        static let body17Bold = bodyStrong

        static let smallBody = body
        static let smallBodyMedium = bodyStrong
        static let smallBodySemibold = bodyStrong
        static let smallBodyBold = bodyStrong

        static let description = body
        static let descriptionMedium = body
        static let descriptionSemibold = bodyStrong
        static let descriptionBold = bodyStrong
        static let homeLocationLabel = body
        static let homeFilterChip = caption
        static let tabBarLabel = caption
        static let contentTabLabel = captionStrong

        static let label = caption
        static let labelMedium = captionStrong
        static let labelSemibold = captionStrong
        static let footnote = caption
        static let footnoteMedium = captionStrong
        static let footnoteSemibold = captionStrong
        static let badge = caption
        static let badgeCount = captionStrong

        static let micro = caption
        static let microMedium = captionStrong
        static let microSemibold = captionStrong
        static let microBold = captionStrong

        static let buttonText = bodyStrong
        static let buttonCTA = bodyStrong
        static let buttonSecondary = bodyStrong

        static let captionBold = captionStrong

        static func system(size: CGFloat, weight: Font.Weight = .regular) -> Font {
            .system(size: size, weight: weight)
        }
    }

    struct Spacing {
        static let xs: CGFloat = 4
        static let sm: CGFloat = 8
        static let md: CGFloat = 16
        static let lg: CGFloat = 24
        static let xl: CGFloat = 32
        static let xxl: CGFloat = 40
        static let xxxl: CGFloat = 60

        static let homeSectionTitleToCards: CGFloat = 8
        static let homeFiltersToFirstSection: CGFloat = 8
        static let homeSectionBetween: CGFloat = 24
        static let homeWhiteSectionGradientHeight: CGFloat = 6
        static let homeFiltersTopPadding: CGFloat = 2
        static let homeWhiteSectionOverlap: CGFloat = 130
        static let bookingsWhiteSectionOverlap: CGFloat = 70
        static let homeFilterChipsSpacing: CGFloat = 10
        static let homeFiltersVerticalPadding: CGFloat = 12
        static let homeFilterChipHorizontalPadding: CGFloat = 18
        static let bookingsHeaderToWhiteSection: CGFloat = 31
        static let bookingsTabsTopPadding: CGFloat = 19
        static let pageTitleToSubtitleSpacing: CGFloat = 4
    }

    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 24
        static let homeWhiteSection: CGFloat = 24
        static let pill: CGFloat = 999
    }

    struct Button {
        static let primaryHeight: CGFloat = 52
        static let secondaryHeight: CGFloat = 44
    }

    struct Layout {
        static let profileGridCardHeight: CGFloat = 130
        static let homeHeroImageHeight: CGFloat = 380
        static let homeHeroTitleHeight: CGFloat = 115
        static let homeProviderCardWidth: CGFloat = 260
        static let homeProviderCardHeight: CGFloat = 200
        static let bookingCardImageSize: CGFloat = 120
        static let bookingsHeroHeight: CGFloat = 220
    }

    struct Shadows {
        static let small = Shadow(color: Colors.shadow, radius: 4, offsetY: 2)
        static let medium = Shadow(color: Colors.shadowMedium, radius: 8, offsetY: 4)
        static let large = Shadow(color: Colors.shadowStrong, radius: 16, offsetY: 8)

        struct Shadow {
            let color: Color
            let radius: CGFloat
            let offsetY: CGFloat
        }
    }

    struct Animation {
        static let microFade = SwiftUI.Animation.easeInOut(duration: 0.15)
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.2)
        static let fade = SwiftUI.Animation.easeOut(duration: 0.25)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.3)
        static let slow = SwiftUI.Animation.easeInOut(duration: 0.5)

        static let springSnappy = SwiftUI.Animation.spring(response: 0.28, dampingFraction: 0.9)
        static let springQuick = SwiftUI.Animation.spring(response: 0.3, dampingFraction: 0.8)
        static let springStandard = SwiftUI.Animation.spring(response: 0.4, dampingFraction: 0.8)
        static let springSmooth = SwiftUI.Animation.spring(response: 0.45, dampingFraction: 0.85)
        static let springSlow = SwiftUI.Animation.spring(response: 0.5, dampingFraction: 0.8)
    }
}

enum AppHaptics {
    static func success() {
        UINotificationFeedbackGenerator().notificationOccurred(.success)
    }

    static func error() {
        UINotificationFeedbackGenerator().notificationOccurred(.error)
    }

    static func soft() {
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
    }

    static func medium() {
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
    }

    static func light() {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
    }
}

enum AppMotion {
    static func spring(reduceMotion: Bool, response: Double = 0.35, dampingFraction: Double = 0.82) -> Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .spring(response: response, dampingFraction: dampingFraction)
    }

    static func quick(reduceMotion: Bool) -> Animation {
        reduceMotion ? .linear(duration: 0.01) : .easeInOut(duration: 0.18)
    }
}
