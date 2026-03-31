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

        static let contentTabSelected = primary
        static let contentTabUnselected = Color(hex: "#989898")
        static let tabBarBackground = cardBackground
        static let tabBarActive = accent
        static let tabBarInactive = secondaryText

        static let shadow = Color.black.opacity(0.05)
        static let shadowMedium = Color.black.opacity(0.1)
        static let shadowStrong = Color.black.opacity(0.16)
    }

    struct Typography {
        static let heroTitle = Font.custom("DelaGothicOne-Regular", size: 42)
        static let title = Font.custom("DelaGothicOne-Regular", size: 32)
        static let pageTitle = Font.custom("DelaGothicOne-Regular", size: 24)
        static let navigationTitle = Font.custom("Montserrat-SemiBold", size: 22)
        static let sectionTitle = Font.custom("Montserrat-SemiBold", size: 18)
        static let sectionTitleSmall = Font.custom("Montserrat-SemiBold", size: 16)

        static let cardTitle = Font.custom("Montserrat-SemiBold", size: 16)
        static let subtitle = Font.custom("Montserrat-Regular", size: 18)
        static let subtitleBold = Font.custom("Montserrat-SemiBold", size: 18)

        static let body = Font.custom("Montserrat-Regular", size: 16)
        static let bodyMedium = Font.custom("Montserrat-SemiBold", size: 16)
        static let bodySemibold = Font.custom("Montserrat-SemiBold", size: 16)
        static let bodyBold = Font.custom("Montserrat-SemiBold", size: 16)

        static let smallBody = Font.custom("Montserrat-Regular", size: 15)
        static let smallBodyMedium = Font.custom("Montserrat-SemiBold", size: 15)
        static let smallBodySemibold = Font.custom("Montserrat-SemiBold", size: 15)

        static let description = Font.custom("Montserrat-Regular", size: 14)
        static let descriptionMedium = Font.custom("Montserrat-SemiBold", size: 14)
        static let descriptionSemibold = Font.custom("Montserrat-SemiBold", size: 14)

        static let label = Font.custom("Montserrat-Regular", size: 12)
        static let labelMedium = Font.custom("Montserrat-SemiBold", size: 12)
        static let labelSemibold = Font.custom("Montserrat-SemiBold", size: 12)
        static let footnote = Font.custom("Montserrat-Regular", size: 12)
        static let footnoteMedium = Font.custom("Montserrat-SemiBold", size: 12)
        static let badge = Font.custom("Montserrat-SemiBold", size: 12)
        static let tabBarLabel = Font.custom("Montserrat-Regular", size: 12)

        static let buttonText = Font.custom("Montserrat-SemiBold", size: 16)
        static let buttonCTA = Font.custom("Montserrat-SemiBold", size: 18)
        static let buttonSecondary = Font.custom("Montserrat-SemiBold", size: 18)

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
    }

    struct CornerRadius {
        static let small: CGFloat = 10
        static let medium: CGFloat = 16
        static let large: CGFloat = 24
        static let xlarge: CGFloat = 32
    }

    struct Animation {
        static let quick = SwiftUI.Animation.easeInOut(duration: 0.18)
        static let standard = SwiftUI.Animation.easeInOut(duration: 0.28)
    }
}
