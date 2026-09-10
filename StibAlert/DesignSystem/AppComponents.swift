import SwiftUI





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



