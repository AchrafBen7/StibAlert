import SwiftUI
import UIKit

struct MainTabView: View {
    enum Tab: CaseIterable {
        case map
        case search
        case create
        case favorites
        case profile
    }

    @EnvironmentObject var mainTabSelection: MainTabSelection
    @EnvironmentObject var tabBarVisibility: TabBarVisibility

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            TabView(selection: $mainTabSelection.currentTab) {
                NavigationStack { HomeView() }
                    .tag(Tab.map)
                    .tabItem { EmptyView() }

                NavigationStack { SearchView() }
                    .tag(Tab.search)
                    .tabItem { EmptyView() }

                NavigationStack { ReportView() }
                    .tag(Tab.create)
                    .tabItem { EmptyView() }

                NavigationStack { FavoritesView() }
                    .tag(Tab.favorites)
                    .tabItem { EmptyView() }

                NavigationStack { ProfileView() }
                    .tag(Tab.profile)
                    .tabItem { EmptyView() }
            }
            .toolbar(.hidden, for: .tabBar)
            .animation(nil, value: mainTabSelection.currentTab)
            .transaction { transaction in
                transaction.animation = nil
            }
            .onAppear {
                tabBarVisibility.isHidden = false
            }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if !tabBarVisibility.isHidden {
                CustomTabBar(selection: $mainTabSelection.currentTab)
            }
        }
    }
}

struct CleanTabScreen: View {
    let tab: MainTabView.Tab

    private var config: CleanTabConfig {
        switch tab {
        case .map:
            .init(
                eyebrow: "STIB Alert",
                title: "Home",
                subtitle: "A clean base for rebuilding the app the right way.",
                cards: [
                    .init(title: "Status", value: "Fresh start", tint: Color(hex: "#4557A1")),
                    .init(title: "Design", value: "Minimal shell", tint: Color(hex: "#CBC1AD")),
                    .init(title: "Runtime", value: "No heavy logic", tint: Color(hex: "#0F9D58"))
                ]
            )
        case .search:
            .init(
                eyebrow: "Explore",
                title: "Search",
                subtitle: "This tab is now a clean placeholder ready for a proper rebuild.",
                cards: [
                    .init(title: "Lines", value: "Mock only", tint: Color(hex: "#4557A1")),
                    .init(title: "Stops", value: "Mock only", tint: Color(hex: "#CBC1AD")),
                    .init(title: "Flow", value: "Instant", tint: Color(hex: "#0F9D58"))
                ]
            )
        case .create:
            .init(
                eyebrow: "Community",
                title: "Report",
                subtitle: "The creation flow has been stripped back to a stable placeholder.",
                cards: [
                    .init(title: "New alert", value: "Coming back", tint: Color(hex: "#D7263D")),
                    .init(title: "Media", value: "Removed", tint: Color(hex: "#CBC1AD")),
                    .init(title: "Latency", value: "Zero", tint: Color(hex: "#0F9D58"))
                ]
            )
        case .favorites:
            .init(
                eyebrow: "Saved",
                title: "Favorites",
                subtitle: "A clean section ready for a simpler favorites model.",
                cards: [
                    .init(title: "Lines", value: "To rebuild", tint: Color(hex: "#4557A1")),
                    .init(title: "Stops", value: "To rebuild", tint: Color(hex: "#CBC1AD")),
                    .init(title: "Storage", value: "Local first", tint: Color(hex: "#0F9D58"))
                ]
            )
        case .profile:
            .init(
                eyebrow: "Account",
                title: "Profile",
                subtitle: "Authentication and profile flows have been cleared for a cleaner restart.",
                cards: [
                    .init(title: "Session", value: "Removed", tint: Color(hex: "#4557A1")),
                    .init(title: "Backend", value: "Disconnected", tint: Color(hex: "#CBC1AD")),
                    .init(title: "Base", value: "Ready", tint: Color(hex: "#0F9D58"))
                ]
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(config.eyebrow.uppercased())
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    Text(config.title)
                        .font(DesignSystem.Typography.pageTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)

                    Text(config.subtitle)
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }

                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12), count: 2), spacing: 12) {
                    ForEach(config.cards) { card in
                        CleanInfoCard(card: card)
                    }
                }

                if tab == .map {
                    VStack(alignment: .leading, spacing: 12) {
                        SectionHeader(
                            title: "Recent reports",
                            subtitle: "Mock incident cards in the NIOS visual style."
                        )
                        .padding(.horizontal, 0)

                        ForEach(mockReports) { report in
                            ReportCard(report: report)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 12) {
                    Text("Next rebuild")
                        .font(DesignSystem.Typography.sectionTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)

                    ForEach([
                        "Rebuild one screen at a time.",
                        "Keep only local mock data until the UX is solid.",
                        "Reconnect the backend only after the new flows are stable."
                    ], id: \.self) { item in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(DesignSystem.Colors.accent.opacity(0.18))
                                .frame(width: 34, height: 34)
                                .overlay(
                                    Image(systemName: "checkmark")
                                        .font(.system(size: 13, weight: .bold))
                                        .foregroundStyle(DesignSystem.Colors.accent)
                                )

                            Text(item)
                                .font(DesignSystem.Typography.body)
                                .foregroundStyle(DesignSystem.Colors.primaryText)

                            Spacer()
                        }
                        .padding(14)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 18, style: .continuous)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                    }
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, DesignSystem.Spacing.lg)
            .padding(.bottom, 120)
        }
        .background(DesignSystem.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
    }

    private var mockReports: [MockReport] {
        [
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
                line: "B95",
                title: "Crowded vehicle on central corridor",
                subtitle: "Passengers reported heavy crowding between Louise and Central Station.",
                status: "Observed",
                statusColor: DesignSystem.Colors.success,
                tint: DesignSystem.Colors.accentSand,
                icon: "person.3.fill",
                time: "Updated 8 min ago"
            )
        ]
    }
}

private struct CleanInfoCard: View {
    let card: CleanInfo

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(card.tint.opacity(0.14))
                .frame(width: 42, height: 42)
                .overlay(
                    Circle()
                        .fill(card.tint)
                        .frame(width: 12, height: 12)
                )

            Text(card.title)
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)

            Text(card.value)
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }
}

private struct CleanTabConfig {
    let eyebrow: String
    let title: String
    let subtitle: String
    let cards: [CleanInfo]
}

private struct CleanInfo: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let tint: Color
}
