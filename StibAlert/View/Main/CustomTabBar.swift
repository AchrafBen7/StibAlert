import SwiftUI

private struct StibTabItem: Identifiable {
    let id = UUID()
    let tab: MainTabView.Tab
    let systemName: String
    let title: String
}

struct CustomTabBar: View {
    @Binding var selection: MainTabView.Tab

    private let items: [StibTabItem] = [
        .init(tab: .map, systemName: "map.fill", title: String(localized: "tab.map", defaultValue: "Map")),
        .init(tab: .reports, systemName: "list.bullet.rectangle.portrait.fill", title: String(localized: "tab.reports", defaultValue: "Reports")),
        .init(tab: .create, systemName: "plus.circle.fill", title: String(localized: "tab.create", defaultValue: "Create")),
        .init(tab: .favorites, systemName: "heart.fill", title: String(localized: "tab.favorites", defaultValue: "Favorites")),
        .init(tab: .profile, systemName: "person.crop.circle.fill", title: String(localized: "tab.profile", defaultValue: "Profile"))
    ]

    private static let barContentHeight: CGFloat = 72
    private static let bottomMargin: CGFloat = 12
    private static let topPadding: CGFloat = 9
    private static let horizontalPadding: CGFloat = 12

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(items) { item in
                    Button {
                        selection = item.tab
                    } label: {
                        VStack(spacing: 4) {
                            Image(systemName: item.systemName)
                                .font(.system(size: 22))
                                .frame(width: 24, height: 24)
                                .foregroundColor(selection == item.tab ? DesignSystem.Colors.tabBarActive : DesignSystem.Colors.tabBarInactive)

                            Text(item.title)
                                .font(DesignSystem.Typography.tabBarLabel)
                                .foregroundColor(selection == item.tab ? DesignSystem.Colors.tabBarActive : DesignSystem.Colors.tabBarInactive)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(item.title)
                }
            }
            .padding(.top, Self.topPadding)
            .padding(.horizontal, Self.horizontalPadding)

            Rectangle()
                .fill(DesignSystem.Colors.cardBackground)
                .frame(height: Self.bottomMargin)
                .frame(maxWidth: .infinity)
        }
        .frame(height: Self.barContentHeight + Self.bottomMargin)
        .frame(maxWidth: .infinity)
        .background(
            DesignSystem.Colors.tabBarBackground
                .clipShape(
                    UnevenRoundedRectangle(
                        topLeadingRadius: 4,
                        bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0,
                        topTrailingRadius: 4,
                        style: .continuous
                    )
                )
                .shadow(color: DesignSystem.Colors.shadowMedium, radius: 8, x: 0, y: -2)
        )
        .ignoresSafeArea(edges: .bottom)
    }
}
