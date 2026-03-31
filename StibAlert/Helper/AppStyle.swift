import SwiftUI

struct AppStyle {
    enum Padding: CGFloat {
        case verySmall8 = 8
        case small16 = 16
        case medium24 = 24
        case big32 = 32
    }

    enum TextStyle {
        case title
        case heroTitle
        case sectionTitle
        case buttonSecondary
        case buttonCTA
        case chipLabel
        case description
        case navigationAction
        case navigationTitle
        case subtitle
        case caption
        case infoLabel

        var font: Font {
            switch self {
            case .title:
                return DesignSystem.Typography.title
            case .heroTitle:
                return DesignSystem.Typography.heroTitle
            case .sectionTitle:
                return DesignSystem.Typography.sectionTitle
            case .buttonSecondary:
                return DesignSystem.Typography.buttonSecondary
            case .buttonCTA:
                return DesignSystem.Typography.buttonCTA
            case .chipLabel:
                return DesignSystem.Typography.labelMedium
            case .description:
                return DesignSystem.Typography.body
            case .navigationAction:
                return DesignSystem.Typography.bodySemibold
            case .navigationTitle:
                return DesignSystem.Typography.navigationTitle
            case .subtitle:
                return DesignSystem.Typography.subtitle
            case .caption:
                return DesignSystem.Typography.description
            case .infoLabel:
                return DesignSystem.Typography.body
            }
        }

        var defaultColor: Color {
            switch self {
            case .title, .heroTitle, .sectionTitle, .navigationTitle, .chipLabel:
                return DesignSystem.Colors.primaryText
            case .buttonCTA:
                return .white
            case .buttonSecondary:
                return DesignSystem.Colors.primaryText
            case .description, .subtitle, .caption, .infoLabel:
                return DesignSystem.Colors.secondaryText
            case .navigationAction:
                return DesignSystem.Colors.accent
            }
        }
    }
}

extension View {
    func textView(style: AppStyle.TextStyle, color: Color? = nil) -> some View {
        font(style.font)
            .foregroundColor(color ?? style.defaultColor)
    }
}
