import SwiftUI

struct HomeView: View {
    @State private var selectedFilter: HomeFilter = .all
    @State private var showsGoogle3DMapTest = false

    private var reports: [MockReport] {
        let base = HomeMockData.reports

        switch selectedFilter {
        case .all:
            return base
        case .metro:
            return base.filter { $0.line.hasPrefix("M") }
        case .tram:
            return base.filter { $0.line.hasPrefix("T") }
        case .bus:
            return base.filter { $0.line.hasPrefix("B") }
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionBetween) {
                HomeHeroSection {
                    showsGoogle3DMapTest = true
                }

                HomeFiltersView(selectedFilter: $selectedFilter)

                HomeHighlightsSection(items: HomeMockData.highlights)

                VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionTitleToCards + 8) {
                    SectionHeader(
                        title: "Recent reports",
                        subtitle: "Community alerts styled on the new base."
                    )

                    VStack(spacing: 12) {
                        ForEach(reports) { report in
                            ReportCard(report: report)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                }

                HomeWatchSection(lines: HomeMockData.watchLines)
            }
            .padding(.top, DesignSystem.Spacing.md)
            .padding(.bottom, 120)
        }
        .background(DesignSystem.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
        .fullScreenCover(isPresented: $showsGoogle3DMapTest) {
            GoogleMaps3DTestView()
        }
    }
}

private struct HomeHeroSection: View {
    let onOpenMap: () -> Void

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color(hex: "#E7ECF8"),
                    Color(hex: "#B9C5E5"),
                    Color(hex: "#6D80AE")
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .overlay(
                RadialGradient(
                    colors: [Color.white.opacity(0.55), .clear],
                    center: .topLeading,
                    startRadius: 30,
                    endRadius: 260
                )
                .offset(x: -40, y: -40)
            )

            VStack(alignment: .leading, spacing: 10) {
                Text("STIB Alert")
                    .font(DesignSystem.Typography.labelSemibold)
                    .foregroundStyle(Color.white.opacity(0.85))

                Text("Move through Brussels with clarity.")
                    .font(DesignSystem.Typography.heroTitleLarge)
                    .foregroundStyle(.white)
                    .frame(maxWidth: 260, alignment: .leading)

                Text("A clean home rebuilt on the NIOS structure, ready for the real data later.")
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(Color.white.opacity(0.9))
                    .frame(maxWidth: 270, alignment: .leading)

                HStack(spacing: 10) {
                    Button("Test 3D map", action: onOpenMap)
                        .buttonStyle(PrimaryButton())

                    Button("Report") {}
                        .buttonStyle(AppleHoverButton(fontSize: 15))
                }
                .frame(maxWidth: 300)
            }
            .padding(DesignSystem.Spacing.md)
        }
        .frame(height: 250)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.homeWhiteSection, style: .continuous))
        .padding(.horizontal, DesignSystem.Spacing.md)
    }
}

private struct HomeFiltersView: View {
    @Binding var selectedFilter: HomeFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: DesignSystem.Spacing.homeFilterChipsSpacing) {
                ForEach(HomeFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        Text(filter.title)
                            .font(DesignSystem.Typography.homeFilterChip)
                            .foregroundStyle(
                                selectedFilter == filter
                                    ? Color.white
                                    : DesignSystem.Colors.homeFilterUnselected
                            )
                            .padding(.horizontal, DesignSystem.Spacing.homeFilterChipHorizontalPadding)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(
                                        selectedFilter == filter
                                            ? DesignSystem.Colors.homeFilterSelectedBg
                                            : DesignSystem.Colors.cardBackground
                                    )
                            )
                            .overlay(
                                Capsule()
                                    .stroke(
                                        selectedFilter == filter
                                            ? DesignSystem.Colors.homeFilterSelectedBg
                                            : DesignSystem.Colors.homeFilterUnselected,
                                        lineWidth: 1
                                    )
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.vertical, DesignSystem.Spacing.homeFiltersVerticalPadding)
        }
    }
}

private struct HomeHighlightsSection: View {
    let items: [HomeHighlight]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionTitleToCards + 8) {
            SectionHeader(
                title: "Overview",
                subtitle: "The most important blocks, reduced to a cleaner structure."
            )

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(items) { item in
                        VStack(alignment: .leading, spacing: 12) {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(item.tint.opacity(0.14))
                                .frame(width: 48, height: 48)
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
                        .frame(width: 220, alignment: .leading)
                        .padding(16)
                        .niosCard()
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
            }
        }
    }
}

private struct HomeWatchSection: View {
    let lines: [WatchLine]

    var body: some View {
        VStack(alignment: .leading, spacing: DesignSystem.Spacing.homeSectionTitleToCards + 8) {
            SectionHeader(
                title: "Lines to watch",
                subtitle: "A first vertical section in the NIOS layout rhythm."
            )

            VStack(spacing: 12) {
                ForEach(lines) { line in
                    HStack(spacing: 14) {
                        Text(line.code)
                            .font(DesignSystem.Typography.cardTitle)
                            .foregroundStyle(.white)
                            .frame(width: 52, height: 52)
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
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private enum HomeFilter: CaseIterable, Identifiable {
    case all
    case metro
    case tram
    case bus

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .metro: return "Metro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        }
    }
}

private enum HomeMockData {
    static let reports: [MockReport] = [
        .init(
            line: "M6",
            title: "Delay reported near Simonis",
            subtitle: "Traffic slowed down on the outbound platform. Community signal pending verification.",
            status: "Pending",
            statusColor: DesignSystem.Colors.warning,
            tint: DesignSystem.Colors.accent,
            icon: "tram.fill",
            time: "Updated 3 min ago"
        ),
        .init(
            line: "T7",
            title: "Short disruption on tram corridor",
            subtitle: "Passengers flagged a temporary block near Vanderkindere.",
            status: "Observed",
            statusColor: DesignSystem.Colors.success,
            tint: Color(hex: "#D7263D"),
            icon: "tram.fill",
            time: "Updated 5 min ago"
        ),
        .init(
            line: "B95",
            title: "Crowded vehicle on central corridor",
            subtitle: "Heavy crowding reported between Louise and Central Station.",
            status: "Busy",
            statusColor: DesignSystem.Colors.warning,
            tint: DesignSystem.Colors.accentSand,
            icon: "person.3.fill",
            time: "Updated 8 min ago"
        )
    ]

    static let highlights: [HomeHighlight] = [
        .init(title: "Live map", subtitle: "Reserved for the rebuilt map module.", icon: "map.fill", tint: DesignSystem.Colors.accent),
        .init(title: "Verified alerts", subtitle: "A cleaner report feed starts here.", icon: "checkmark.seal.fill", tint: Color(hex: "#0F9D58")),
        .init(title: "Favorite stops", subtitle: "This block will come back with a simpler model.", icon: "heart.fill", tint: DesignSystem.Colors.accentSand)
    ]

    static let watchLines: [WatchLine] = [
        .init(code: "M1", title: "Metro 1", subtitle: "West-east core axis", status: "Stable", statusColor: DesignSystem.Colors.success, tint: DesignSystem.Colors.accent),
        .init(code: "T7", title: "Tram 7", subtitle: "Outer ring corridor", status: "Watch", statusColor: DesignSystem.Colors.warning, tint: Color(hex: "#D7263D")),
        .init(code: "B95", title: "Bus 95", subtitle: "City center and Ixelles", status: "Busy", statusColor: DesignSystem.Colors.warning, tint: DesignSystem.Colors.accentSand)
    ]
}

private struct HomeHighlight: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
}

private struct WatchLine: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let subtitle: String
    let status: String
    let statusColor: Color
    let tint: Color
}
