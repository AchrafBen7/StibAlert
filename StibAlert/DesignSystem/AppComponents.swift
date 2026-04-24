import SwiftUI

struct HighlightButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .overlay(Color.black.opacity(configuration.isPressed ? 0.2 : 0))
    }
}

struct PrimaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.buttonCTA)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .foregroundStyle(DesignSystem.Palette.textOnBrand)
            .frame(maxWidth: .infinity)
            .frame(height: DesignSystem.Button.primaryHeight)
            .background(DesignSystem.Palette.brand.opacity(configuration.isPressed ? 0.88 : 1.0))
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct SecondaryButton: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.buttonSecondary)
            .padding(.horizontal, DesignSystem.Spacing.lg)
            .foregroundStyle(DesignSystem.Palette.textPrimary)
            .frame(maxWidth: .infinity)
            .frame(height: DesignSystem.Button.secondaryHeight)
            .background(DesignSystem.Palette.surfaceMuted)
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .stroke(DesignSystem.Palette.borderStrong, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
            .scaleEffect(configuration.isPressed ? 0.98 : 1.0)
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct AppleHoverButton: ButtonStyle {
    var fontSize: CGFloat = 17

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.system(size: fontSize, weight: .semibold))
            .frame(maxWidth: .infinity, minHeight: DesignSystem.Button.primaryHeight)
            .foregroundColor(configuration.isPressed ? DesignSystem.Palette.textPrimary : DesignSystem.Palette.textPrimary)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                    .stroke(DesignSystem.Palette.border, lineWidth: 1)
                    .background(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large)
                            .fill(configuration.isPressed ? DesignSystem.Palette.surfaceElevated : DesignSystem.Palette.surface)
                    )
            )
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            .animation(DesignSystem.Animation.quick, value: configuration.isPressed)
    }
}

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(DesignSystem.Typography.body)
            .padding(.horizontal, DesignSystem.Spacing.md)
            .frame(height: DesignSystem.Button.primaryHeight)
            .background(DesignSystem.Palette.surfaceMuted)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .stroke(DesignSystem.Palette.border, lineWidth: 1)
            )
            .textInputAutocapitalization(.never)
    }
}

extension View {
    func authFieldStyle() -> some View {
        modifier(AuthFieldStyle())
    }
}

struct NIOSCardModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DesignSystem.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                    .stroke(DesignSystem.Palette.border, lineWidth: 1)
            )
            .shadow(color: DesignSystem.Colors.shadow, radius: 6, x: 0, y: 3)
    }
}

extension View {
    func niosCard() -> some View {
        modifier(NIOSCardModifier())
    }
}

struct SectionHeader: View {
    let title: String
    let subtitle: String?
    var action: (() -> Void)? = nil
    var actionLabel: String = "See all"

    var body: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.sectionTitleSmall)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                if let subtitle {
                    Text(subtitle)
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            }

            Spacer()

            if let action {
                Button(action: action) {
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .frame(width: 30, height: 30)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DesignSystem.Colors.border, lineWidth: 1))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

struct StatusBadge: View {
    let label: String
    let color: Color

    var body: some View {
        Text(label)
            .font(DesignSystem.Typography.labelMedium)
            .foregroundColor(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(color)
            .clipShape(Capsule())
    }
}

struct InfoAlertRow: View {
    let icon: String
    let message: String
    let tint: Color

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(tint)
                .frame(width: 22)

            Text(message)
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(DesignSystem.Spacing.md)
        .background(tint.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                .stroke(tint.opacity(0.3), lineWidth: 1)
        )
    }
}
