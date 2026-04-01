import SwiftUI

struct DesignSystem {
    struct Colors {
        static let primary = Color(hex: "#232323")
        static let primaryText = Color(hex: "#1F1F1F")
        static let secondaryText = Color(hex: "#777777")

        static let accent = Color(hex: "#4557A1")
        static let accentBlue = Color(hex: "#4557A1")
        static let accentSoft = Color(hex: "#EEF2FF")
        static let accentSand = Color(hex: "#CBC1AD")

        static let background = Color(hex: "#F6F6F3")
        static let cardBackground = Color.white
        static let overlayBackground = Color.black.opacity(0.4)

        static let success = Color.green
        static let warning = Color.orange
        static let error = Color.red
        static let info = Color.blue

        static let border = Color.black.opacity(0.08)
        static let borderStrong = Color.black.opacity(0.16)
        static let dividerLight = Color(hex: "#E6E6E6")

        static let homeFilterSelectedBg = primary
        static let homeFilterUnselected = Color(hex: "#989898")
        static let contentTabSelected = primary
        static let contentTabUnselected = Color(hex: "#989898")
        static let homeProviderCardOverlay = Color.black.opacity(0.1)
        static let bookingsHeroOverlay = Color.black.opacity(0.2)

        static let tabBarBackground = cardBackground
        static let tabBarActive = accent
        static let tabBarInactive = secondaryText

        static let shadow = Color.black.opacity(0.05)
        static let shadowMedium = Color.black.opacity(0.1)
        static let shadowStrong = Color.black.opacity(0.16)
    }

    struct Typography {
        static let heroTitle = Font.custom("DelaGothicOne-Regular", size: 52)
        static let title = Font.custom("DelaGothicOne-Regular", size: 37)
        static let pageTitle = Font.custom("DelaGothicOne-Regular", size: 32)
        static let navigationTitle = Font.custom("DelaGothicOne-Regular", size: 28)
        static let heroTitleLarge = Font.custom("DelaGothicOne-Regular", size: 32)

        static let sectionTitle = Font.custom("Montserrat-SemiBold", size: 24)
        static let sectionTitleSmall = Font.custom("Montserrat-SemiBold", size: 16)
        static let homeSectionTitle = Font.custom("Montserrat-SemiBold", size: 16)
        static let pageTitlePoppins = Font.custom("DelaGothicOne-Regular", size: 24)
        static let pageSubtitlePoppins = Font.custom("Montserrat-Regular", size: 14)

        static let heading32 = Font.system(size: 32)
        static let heading32Bold = Font.system(size: 32, weight: .bold)
        static let heading26Bold = Font.system(size: 26, weight: .bold)
        static let heading28 = Font.system(size: 28, weight: .semibold)
        static let heading28Regular = Font.system(size: 28)
        static let heading24Semibold = Font.system(size: 24, weight: .semibold)
        static let heading22 = Font.system(size: 22, weight: .bold)
        static let heading22Medium = Font.system(size: 22, weight: .medium)

        static let cardTitle = Font.custom("Montserrat-SemiBold", size: 16)
        static let cardTitleMedium = Font.custom("Montserrat-SemiBold", size: 16)
        static let cardTitleSemibold = Font.custom("Montserrat-SemiBold", size: 16)
        static let cardTitleBold = Font.custom("Montserrat-SemiBold", size: 16)

        static let subtitle = Font.custom("Montserrat-Regular", size: 18)
        static let subtitleMedium = Font.system(size: 18, weight: .medium)
        static let subtitleSemibold = Font.system(size: 18, weight: .semibold)
        static let subtitleBold = Font.custom("Montserrat-SemiBold", size: 18)

        static let body = Font.custom("Montserrat-Regular", size: 16)
        static let body17 = Font.system(size: 17)
        static let body17Medium = Font.system(size: 17, weight: .medium)
        static let bodyMedium = Font.custom("Montserrat-SemiBold", size: 16)
        static let bodySemibold = Font.custom("Montserrat-SemiBold", size: 16)
        static let bodyBold = Font.custom("Montserrat-SemiBold", size: 16)
        static let body17Bold = Font.system(size: 17, weight: .bold)

        static let smallBody = Font.custom("Montserrat-Regular", size: 15)
        static let smallBodyMedium = Font.system(size: 15, weight: .medium)
        static let smallBodySemibold = Font.system(size: 15, weight: .semibold)
        static let smallBodyBold = Font.system(size: 15, weight: .bold)

        static let description = Font.custom("Montserrat-Regular", size: 14)
        static let descriptionMedium = Font.custom("Montserrat-Regular", size: 14)
        static let descriptionSemibold = Font.custom("Montserrat-SemiBold", size: 14)
        static let descriptionBold = Font.custom("Montserrat-SemiBold", size: 14)
        static let homeLocationLabel = Font.custom("Montserrat-Regular", size: 14)
        static let homeFilterChip = Font.custom("Montserrat-Regular", size: 12)
        static let tabBarLabel = Font.custom("Montserrat-Regular", size: 12)
        static let contentTabLabel = Font.custom("Montserrat-SemiBold", size: 12)

        static let label = Font.custom("Montserrat-Regular", size: 12)
        static let labelMedium = Font.custom("Montserrat-SemiBold", size: 12)
        static let labelSemibold = Font.custom("Montserrat-SemiBold", size: 12)
        static let footnote = Font.custom("Montserrat-Regular", size: 12)
        static let footnoteMedium = Font.custom("Montserrat-SemiBold", size: 12)
        static let footnoteSemibold = Font.custom("Montserrat-SemiBold", size: 12)
        static let badge = Font.custom("Montserrat-Regular", size: 12)
        static let badgeCount = Font.custom("Montserrat-SemiBold", size: 12)

        static let micro = Font.system(size: 11)
        static let microMedium = Font.system(size: 11, weight: .medium)
        static let microSemibold = Font.system(size: 11, weight: .semibold)
        static let microBold = Font.system(size: 11, weight: .bold)

        static let buttonText = Font.custom("Montserrat-Regular", size: 16)
        static let buttonCTA = Font.custom("Montserrat-SemiBold", size: 18)
        static let buttonSecondary = Font.custom("Montserrat-SemiBold", size: 18)

        static let caption = description
        static let captionBold = descriptionBold

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

        static let homeSectionTitleToCards: CGFloat = 4
        static let homeFiltersToFirstSection: CGFloat = 9
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
        static let pageTitleToSubtitleSpacing: CGFloat = 2
    }

    struct CornerRadius {
        static let small: CGFloat = 8
        static let medium: CGFloat = 12
        static let large: CGFloat = 16
        static let xlarge: CGFloat = 20
        static let homeWhiteSection: CGFloat = 25
        static let pill: CGFloat = 999
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
        static let small = Shadow(color: Colors.shadow, radius: 2, offsetY: 1)
        static let medium = Shadow(color: Colors.shadowMedium, radius: 4, offsetY: 2)
        static let large = Shadow(color: Colors.shadowStrong, radius: 8, offsetY: 4)

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
