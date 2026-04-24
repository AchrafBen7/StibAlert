import SwiftUI

struct SearchOffRouteStatusCard: View {
    let title: String
    let message: String
    let tone: Tone

    enum Tone {
        case warning
        case rerouting
        case updated

        var accent: Color {
            switch self {
            case .warning:
                return DesignSystem.Colors.warning
            case .rerouting:
                return DesignSystem.Colors.info
            case .updated:
                return DesignSystem.Colors.success
            }
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Circle()
                .fill(tone.accent)
                .frame(width: 12, height: 12)
                .padding(.top, 5)

            VStack(alignment: .leading, spacing: 6) {
                Text(title)
                    .font(DesignSystem.Typography.labelSemibold)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                Text(message)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DesignSystem.Colors.cardBackground.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(tone.accent.opacity(0.4), lineWidth: 1)
        )
    }
}
