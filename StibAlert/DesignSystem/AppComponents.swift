import SwiftUI

struct PrimaryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(DesignSystem.Typography.buttonCTA)
            .foregroundColor(.white)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous)
                    .fill(DesignSystem.Colors.primary)
                    .opacity(configuration.isPressed ? 0.85 : 1)
            )
            .scaleEffect(configuration.isPressed ? 0.98 : 1)
    }
}

struct AuthFieldStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding()
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.medium, style: .continuous))
            .textInputAutocapitalization(.never)
    }
}

extension View {
    func authFieldStyle() -> some View {
        modifier(AuthFieldStyle())
    }
}
