import SwiftUI

private struct StibTabItem: Identifiable {
    let id = UUID()
    let tab: MainTabView.Tab
    let systemName: String
    let title: String
}

struct CustomTabBar: View {
    @Binding var selection: MainTabView.Tab
    @State private var tabHaptic = UIImpactFeedbackGenerator(style: .light)

    private let items: [StibTabItem] = [
        .init(tab: .map,       systemName: "house.fill",              title: String(localized: "tab.home",      defaultValue: "Home")),
        .init(tab: .search,    systemName: "magnifyingglass",          title: String(localized: "tab.search",    defaultValue: "Search")),
        .init(tab: .create,    systemName: "plus.circle.fill",         title: String(localized: "tab.create",    defaultValue: "Report")),
        .init(tab: .favorites, systemName: "heart.fill",               title: String(localized: "tab.favorites", defaultValue: "Favorites")),
        .init(tab: .profile,   systemName: "person.crop.circle.fill",  title: String(localized: "tab.profile",   defaultValue: "Profile")),
    ]

    private static let barHeight: CGFloat = 82
    private static let topPadding: CGFloat = 10
    private static let bottomPadding: CGFloat = 10
    private static let horizontalPadding: CGFloat = 14

    var body: some View {
        HStack(spacing: 0) {
            ForEach(items) { item in
                Button {
                    withAnimation(DesignSystem.Animation.springSnappy) {
                        tabHaptic.impactOccurred()
                        tabHaptic.prepare()
                        selection = item.tab
                    }
                } label: {
                    VStack(spacing: 5) {
                        Image(systemName: item.systemName)
                            .font(.system(size: 24, weight: .medium))
                            .frame(width: 28, height: 28)
                            .foregroundColor(
                                selection == item.tab
                                    ? DesignSystem.Colors.tabBarActive
                                    : DesignSystem.Colors.tabBarInactive
                            )

                        Text(item.title)
                            .font(DesignSystem.Typography.tabBarLabel)
                            .foregroundColor(
                                selection == item.tab
                                    ? DesignSystem.Colors.tabBarActive
                                    : DesignSystem.Colors.tabBarInactive
                            )
                            .lineLimit(1)
                            .minimumScaleFactor(0.78)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: Self.barHeight)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(item.title)
            }
        }
        .padding(.top, Self.topPadding)
        .padding(.bottom, Self.bottomPadding)
        .padding(.horizontal, Self.horizontalPadding)
        .background(DesignSystem.Colors.tabBarBackground)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(DesignSystem.Colors.border)
                .frame(height: 1)
        }
        .shadow(color: DesignSystem.Colors.shadowMedium, radius: 10, x: 0, y: -2)
        .onAppear {
            tabHaptic.prepare()
        }
    }
}
