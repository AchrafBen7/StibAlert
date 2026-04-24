import SwiftUI

struct RecommendedRouteCard: View {
    let alternative: SearchRouteAlternative
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Option recommandée")
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    Text(alternative.title)
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("\(alternative.eta) min")
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.accent)

                    if let confidenceText = alternative.confidenceText {
                        Text(confidenceText)
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(DesignSystem.Colors.success)
                    }
                }
            }

            Text(alternative.lineSummary)
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            if let severityLabel = alternative.severityLabel {
                Text(severityLabel)
                    .font(DesignSystem.Typography.labelSemibold)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .padding(.horizontal, 8)
                    .frame(height: 24)
                    .background(DesignSystem.Colors.accentSoft)
                    .clipShape(Capsule())
            }

            if let reason = alternative.reason {
                SearchReasonBlock(
                    title: "Pourquoi cette option",
                    detail: reason
                )
            }

            if let communitySummary = alternative.communitySummary {
                SearchReasonBlock(
                    title: "Lecture terrain",
                    detail: communitySummary
                )
            }

            if let sourceSummary = alternative.sourceSummary {
                SearchReasonBlock(
                    title: "Sources",
                    detail: sourceSummary
                )
            }

            if isSelected {
                Button("Guidage en cours") {
                    onSelect()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityHint("Réouvre le guidage actif pour cette option.")
            } else {
                Button("Choisir cette option") {
                    onSelect()
                }
                .buttonStyle(PrimaryButton())
                .accessibilityHint("Démarre le guidage sur cette alternative recommandée.")
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.cardBackground.opacity(0.90))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

struct AlternativeComparisonCard: View {
    let alternative: SearchRouteAlternative
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(alternative.title)
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(DesignSystem.Colors.primaryText)

                    Text(alternative.lineSummary)
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .lineLimit(2)
                }

                Spacer()

                Text("\(alternative.eta) min")
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.accent)
            }

            if let reason = alternative.reason {
                Text(reason)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                    .lineLimit(3)
            }

            HStack(spacing: 8) {
                if let trustLabel = alternative.trustLabel {
                    SearchInlineBadge(
                        title: trustLabel,
                        background: DesignSystem.Colors.accentSoft
                    )
                }

                if let communitySummary = alternative.communitySummary {
                    SearchInlineBadge(
                        title: communitySummary,
                        background: DesignSystem.Colors.cardBackground
                    )
                }
            }

            if isSelected {
                Button("Guidage en cours") {
                    onSelect()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityHint("Réouvre le guidage actif pour cette alternative.")
            } else {
                Button("Choisir cette option") {
                    onSelect()
                }
                .buttonStyle(PrimaryButton())
                .accessibilityHint("Démarre le guidage sur cette alternative.")
            }
        }
        .padding(14)
        .background(DesignSystem.Colors.cardBackground.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

private struct SearchReasonBlock: View {
    let title: String
    let detail: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(DesignSystem.Typography.labelSemibold)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Text(detail)
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct SearchInlineBadge: View {
    let title: String
    let background: Color

    var body: some View {
        Text(title)
            .font(DesignSystem.Typography.labelSemibold)
            .foregroundStyle(DesignSystem.Colors.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(background)
            .clipShape(Capsule())
    }
}
