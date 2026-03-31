import SwiftUI

struct HighlightButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color.black.opacity(configuration.isPressed ? 0.12 : 0))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.buttonCTA)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .background(DesignSystem.Colors.primary.opacity(configuration.isPressed ? 0.84 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.buttonSecondary)
            .padding(.vertical, DesignSystem.Spacing.md)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .foregroundStyle(DesignSystem.Colors.primary)
            .frame(maxWidth: .infinity)
            .background(DesignSystem.Colors.cardBackground)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium)
                    .stroke(DesignSystem.Colors.borderStrong, lineWidth: 1.2)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct AppleHoverButton: ButtonStyle {
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.system(size: fontSize, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: 56)
            .foregroundColor(configuration.isPressed ? .white : DesignSystem.Colors.primaryText)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .fill(configuration.isPressed ? DesignSystem.Colors.primary : DesignSystem.Colors.cardBackground)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}
