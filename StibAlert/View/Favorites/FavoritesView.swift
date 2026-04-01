import SwiftUI

struct FavoritesView: View {
    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionBetween) {
                FavoritesHeader()

                FavoritesHighlightsSection(items: FavoritesMockData.highlights)

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Saved lines",
                        subtitle: "Your priority corridors in a simple local model."
                    )

                    VStack(spacing: 12) {
                        ForEach(FavoritesMockData.lines) { line in
                            FavoriteLineCard(line: line)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }

                VStack(alignment: .leading, spacing: 12) {
                    SectionHeader(
                        title: "Saved stops",
                        subtitle: "Quick access to the stops you check most often."
                    )

                    VStack(spacing: 12) {
                        ForEach(FavoritesMockData.stops) { stop in
                            FavoriteStopCard(stop: stop)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }
            }
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, 120)
        }
        .background(DesignSystem.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }
}

private struct FavoritesHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Favorites")
                .font(DesignSystem.Typography.pageTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)

            Text("A lighter favorites base, rebuilt for speed before reconnecting anything real.")
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
        }
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

private struct FavoritesHighlightsSection: View {
    let items: [FavoritesHighlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionHeader(
                title: "Pinned overview",
                subtitle: "A compact summary of what matters most."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(item.tint.opacity(0.14))
                                .frame(width: 46, height: 46)
                                .overlay(
                                    Image(systemName: item.icon)
                                        .font(.system(size: 18, weight: .semibold))
                                        .foregroundStyle(item.tint)
                                )

                            Text(item.title)
                                .font(DesignSystem.Typography.cardTitle)
                                .foregroundStyle(DesignSystem.Colors.primaryText)

                            Text(item.subtitle)
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(width: 200, alignment: .leading)
                        .padding(16)
                        .niosCard()
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }
}

private struct FavoriteLineCard: View {
    let line: FavoriteLine

    var body: some View {
        HStack(spacing: 14) {
            Text(line.code)
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(.white)
                .frame(width: 54, height: 54)
                .background(line.tint)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(line.title)
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                Text(line.subtitle)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }

            Spacer()

            StatusBadge(label: line.status, color: line.statusColor)
        }
        .padding(16)
        .niosCard()
    }
}

private struct FavoriteStopCard: View {
    let stop: FavoriteStop

    var body: some View {
        HStack(alignment: .top, spacing: 14) {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(DesignSystem.Colors.accentSoft)
                .frame(width: 54, height: 54)
                .overlay(
                    Image(systemName: "heart.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.accent)
                )

            VStack(alignment: .leading, spacing: 6) {
                Text(stop.name)
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(DesignSystem.Colors.primaryText)

                Text(stop.subtitle)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                HStack(spacing: 8) {
                    ForEach(stop.lines, id: \.self) { line in
                        Text(line)
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(DesignSystem.Colors.primaryText)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 5)
                            .background(DesignSystem.Colors.accentSoft)
                            .clipShape(Capsule())
                    }
                }
            }

            Spacer()
        }
        .padding(16)
        .niosCard()
    }
}

private struct FavoritesHighlight: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}

private struct FavoriteLine: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let subtitle: String
    let tint: Color
    let status: String
    let statusColor: Color
}

private struct FavoriteStop: Identifiable {
    let id = UUID()
    let name: String
    let subtitle: String
    let lines: [String]
}

private enum FavoritesMockData {
    static let highlights: [FavoritesHighlight] = [
        .init(
            title: "Morning set",
            subtitle: "Your weekday commute bundle kept one tap away.",
            icon: "sun.max.fill",
            tint: DesignSystem.Colors.accent
        ),
        .init(
            title: "Priority alerts",
            subtitle: "Saved places where disruption visibility matters most.",
            icon: "bell.badge.fill",
            tint: DesignSystem.Colors.warning
        ),
        .init(
            title: "Local first",
            subtitle: "No sync, no backend, only a stable rebuilt shell.",
            icon: "internaldrive.fill",
            tint: DesignSystem.Colors.accentSand
        )
    ]

    static let lines: [FavoriteLine] = [
        .init(
            code: "M6",
            title: "Roi Baudouin -> Elisabeth",
            subtitle: "Pinned metro axis for morning travel.",
            tint: Color(hex: "#1AA35F"),
            status: "Stable",
            statusColor: DesignSystem.Colors.success
        ),
        .init(
            code: "T7",
            title: "Vanderkindere -> Heysel",
            subtitle: "Saved tram line with strong daily usage.",
            tint: Color(hex: "#D7263D"),
            status: "Busy",
            statusColor: DesignSystem.Colors.warning
        )
    ]

    static let stops: [FavoriteStop] = [
        .init(
            name: "Arts-Loi",
            subtitle: "Central interchange saved for quick status checks.",
            lines: ["M1", "M5", "M2", "M6"]
        ),
        .init(
            name: "Rogier",
            subtitle: "Retail hub and common transfer point.",
            lines: ["M2", "M6", "T3", "T4"]
        )
    ]
}
