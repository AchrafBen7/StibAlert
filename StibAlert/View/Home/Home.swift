import SwiftUI

struct Home: View {
    @ObservedObject var authViewModel: AuthViewModel

    @EnvironmentObject var mainTabSelection: MainTabSelection
    @EnvironmentObject var tabBarVisibility: TabBarVisibility

    @StateObject private var meldingenVM = MeldingenViewModel()
    @State private var navigateToConnexion = false
    @State private var selectedFilter: HomeTransitFilter = .all
    @State private var showLiveMap = false
    private let sectionSpacing: CGFloat = 24

    private var displayedReports: [MeldingenReadModel] {
        let recentReports = meldingenVM.meldingen
            .filter { Date().timeIntervalSince($0.dateSignalement) < 24 * 60 * 60 }
            .sorted { $0.dateSignalement > $1.dateSignalement }

        let filtered = recentReports.filter { report in
            switch selectedFilter {
            case .all:
                return true
            case .metro:
                return ["1", "2", "5", "6"].contains(report.ligne) || report.typeProbleme.lowercased().contains("metro")
            case .tram:
                return !["1", "2", "5", "6"].contains(report.ligne) && report.ligne.count <= 2
            case .bus:
                return report.ligne.count >= 2 && !["1", "2", "5", "6"].contains(report.ligne)
            case .favorites:
                return favoriteLineIDs.contains(report.ligne)
            }
        }

        if filtered.isEmpty {
            return HomeMockData.sampleReports
        }

        return Array(filtered.prefix(6))
    }

    private var favoriteLineIDs: Set<String> {
        Set(["1", "5", "6", "7", "38", "95"])
    }

    private var spotlightLines: [HomeLineSpotlight] {
        let base = HomeMockData.lineSpotlights.filter { item in
            switch selectedFilter {
            case .all:
                return true
            case .metro:
                return item.mode == .metro
            case .tram:
                return item.mode == .tram
            case .bus:
                return item.mode == .bus
            case .favorites:
                return favoriteLineIDs.contains(item.line)
            }
        }

        return base.isEmpty ? HomeMockData.lineSpotlights : base
    }

    private var nearbyStops: [HomeStopRecommendation] {
        HomeMockData.nearbyStops
    }

    var body: some View {
        ZStack {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            NavigationStack {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        HomeHeroSectionStib(
                            userName: authViewModel.user?.nom,
                            onProfileTap: {
                                mainTabSelection.currentTab = .profile
                            },
                            onNotificationsTap: {},
                            onPrimaryAction: {
                                showLiveMap = true
                            },
                            onSecondaryAction: {
                                mainTabSelection.currentTab = .create
                            }
                        )

                        VStack(alignment: .leading, spacing: sectionSpacing) {
                            HomeFiltersStripStib(selectedFilter: $selectedFilter)

                            if authViewModel.isAuthenticated {
                                MobibCardView(authViewModel: authViewModel)
                                    .padding(.horizontal, DesignSystem.Spacing.md)
                            }

                            HomeFeatureCardStib(
                                title: "Live network overview",
                                subtitle: "Open the 3D map, track live vehicles and spot disruptions before you move.",
                                primaryLabel: "Open live map",
                                secondaryLabel: "All reports",
                                onPrimary: { showLiveMap = true },
                                onSecondary: { mainTabSelection.currentTab = .reports }
                            )
                            .padding(.horizontal, DesignSystem.Spacing.md)
                            .padding(.top, 4)

                            HomeHorizontalSectionStib(
                                title: "Lines to watch",
                                subtitle: "Your key corridors, with current status and crowd pressure.",
                                items: spotlightLines
                            )

                            HomeAlertsSectionStib(
                                reports: displayedReports,
                                onShowAll: { mainTabSelection.currentTab = .reports }
                            )

                            HomeQuickActionsSectionStib(
                                actions: [
                                    .init(title: "New alert", subtitle: "Report a disruption in seconds.", icon: "plus.circle.fill") {
                                        mainTabSelection.currentTab = .create
                                    },
                                    .init(title: "Favorites", subtitle: "Review saved lines and stops.", icon: "heart.fill") {
                                        mainTabSelection.currentTab = .favorites
                                    },
                                    .init(title: "My profile", subtitle: "Account, language and settings.", icon: "person.crop.circle.fill") {
                                        mainTabSelection.currentTab = .profile
                                    }
                                ]
                            )

                            HomeNearbyStopsSectionStib(stops: nearbyStops)

                            Color.clear
                                .frame(height: 110)
                        }
                        .padding(.top, 34)
                        .background(DesignSystem.Colors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
                        .offset(y: -10)
                    }
                }
                .background(DesignSystem.Colors.background)
                .toolbar(.hidden, for: .navigationBar)
                .ignoresSafeArea(edges: .top)
                .refreshable {
                    meldingenVM.fetchMeldingen()
                }
                .onAppear {
                    tabBarVisibility.isHidden = false
                    meldingenVM.fetchMeldingen()
                }
            }

            NavigationLink(
                destination: ConnexionView(authVM: authViewModel),
                isActive: $navigateToConnexion
            ) {
                EmptyView()
            }
            .hidden()
        }
        .sheet(isPresented: $showLiveMap) {
            NavigationStack {
                TransitMapView(
                    authViewModel: authViewModel,
                    navigateToConnexion: $navigateToConnexion
                )
            }
        }
    }
}

private enum HomeTransitFilter: String, CaseIterable, Identifiable {
    case all
    case metro
    case tram
    case bus
    case favorites

    var id: String { rawValue }

    var title: String {
        switch self {
        case .all: return "All"
        case .metro: return "Metro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        case .favorites: return "Favorites"
        }
    }

    var icon: String {
        switch self {
        case .all: return "circle.grid.2x2.fill"
        case .metro: return "m.circle.fill"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .favorites: return "heart.fill"
        }
    }
}

private struct HomeHeroSectionStib: View {
    let userName: String?
    var onProfileTap: () -> Void
    var onNotificationsTap: () -> Void
    var onPrimaryAction: () -> Void
    var onSecondaryAction: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    colors: [
                        Color(hex: "#DCE5F7"),
                        Color(hex: "#B9C7E5"),
                        Color(hex: "#7186B4"),
                        Color(hex: "#0B111E")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
                .overlay(
                    LinearGradient(
                        colors: [Color.white.opacity(0.34), Color.clear],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay(alignment: .topTrailing) {
                    Image("logo")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 132, height: 132)
                        .opacity(0.045)
                        .padding(.top, 56)
                        .padding(.trailing, 4)
                }

                VStack(alignment: .leading, spacing: 0) {
                    HStack(spacing: DesignSystem.Spacing.md) {
                        Button(action: onProfileTap) {
                            HStack(spacing: 10) {
                                Circle()
                                    .fill(Color.white.opacity(0.16))
                                    .frame(width: 42, height: 42)
                                    .overlay {
                                        Image(systemName: "person.fill")
                                            .foregroundStyle(.white)
                                    }

                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Brussels network")
                                        .font(DesignSystem.Typography.footnote)
                                        .foregroundStyle(Color.white.opacity(0.9))
                                    Text(userName ?? "Live overview")
                                        .font(DesignSystem.Typography.bodySemibold)
                                        .foregroundStyle(.white)
                                        .lineLimit(1)
                                }
                            }
                        }
                        .buttonStyle(.plain)

                        Spacer()

                        Button(action: onNotificationsTap) {
                            Image(systemName: "bell.fill")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(.white)
                                .frame(width: 42, height: 42)
                                .background(Color.white.opacity(0.14))
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, geo.safeAreaInsets.top + 12)

                    Spacer()

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Move through Brussels with clarity.")
                            .font(.custom("DelaGothicOne-Regular", size: 24))
                            .foregroundStyle(.white)
                            .fixedSize(horizontal: false, vertical: true)
                            .lineSpacing(1)
                            .frame(maxWidth: 224, alignment: .leading)

                        HStack(spacing: 12) {
                            Button("Open live map", action: onPrimaryAction)
                                .buttonStyle(PrimaryButton())
                                .frame(maxWidth: 138)
                            Button("Report issue", action: onSecondaryAction)
                                .buttonStyle(AppleHoverButton(fontSize: 15))
                                .frame(maxWidth: 118)
                        }
                    }
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.bottom, 58)
                }
            }
            .frame(height: geo.size.height)
            .ignoresSafeArea(edges: .top)
        }
        .frame(height: 316)
    }
}

private struct HomeFiltersStripStib: View {
    @Binding var selectedFilter: HomeTransitFilter

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(HomeTransitFilter.allCases) { filter in
                    Button {
                        selectedFilter = filter
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: filter.icon)
                                .font(.system(size: 12, weight: .semibold))
                            Text(filter.title)
                                .font(DesignSystem.Typography.labelMedium)
                        }
                        .foregroundStyle(selectedFilter == filter ? Color.white : DesignSystem.Colors.primaryText)
                        .padding(.horizontal, 14)
                        .padding(.vertical, 10)
                        .background(
                            Capsule()
                                .fill(selectedFilter == filter ? DesignSystem.Colors.primary : DesignSystem.Colors.cardBackground)
                        )
                        .overlay(
                            Capsule()
                                .stroke(selectedFilter == filter ? DesignSystem.Colors.primary : DesignSystem.Colors.borderStrong, lineWidth: 1)
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
            .padding(.top, 2)
            .padding(.bottom, 10)
        }
    }
}

private struct HomeFeatureCardStib: View {
    let title: String
    let subtitle: String
    let primaryLabel: String
    let secondaryLabel: String
    let onPrimary: () -> Void
    let onSecondary: () -> Void

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(hex: "#161B27"), Color(hex: "#2C3A57"), Color(hex: "#4A6296")],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    RadialGradient(
                        colors: [Color.white.opacity(0.16), .clear],
                        center: .topLeading,
                        startRadius: 10,
                        endRadius: 220
                    )
                    .offset(x: -30, y: -30)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                        .stroke(Color.white.opacity(0.08), lineWidth: 1)
                )

            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(title)
                            .font(DesignSystem.Typography.sectionTitle)
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity, alignment: .leading)
                        Text(subtitle)
                            .font(DesignSystem.Typography.description)
                            .foregroundStyle(Color.white.opacity(0.82))
                            .fixedSize(horizontal: false, vertical: true)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }

                    ZStack {
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .fill(Color.white.opacity(0.12))
                            .frame(width: 86, height: 96)
                        VStack(spacing: 8) {
                            Image(systemName: "map.fill")
                                .font(.system(size: 22, weight: .semibold))
                                .foregroundStyle(.white)
                            VStack(spacing: 4) {
                                Rectangle()
                                    .fill(Color.white.opacity(0.85))
                                    .frame(width: 34, height: 3)
                                Rectangle()
                                    .fill(Color(hex: "#CBC1AD"))
                                    .frame(width: 24, height: 3)
                            }
                        }
                    }
                }

                HStack(spacing: 10) {
                    HomeStatChip(title: "Live vehicles", value: "800+")
                    HomeStatChip(title: "Waiting times", value: "Real-time")
                    HomeStatChip(title: "Alerts", value: "Verified")
                }

                HStack(spacing: 10) {
                    Button(primaryLabel, action: onPrimary)
                        .buttonStyle(PrimaryButton())
                    Button(secondaryLabel, action: onSecondary)
                        .buttonStyle(AppleHoverButton(fontSize: 14))
                        .frame(maxWidth: 120)
                }
            }
            .padding(22)
        }
        .frame(height: 220)
        .shadow(color: DesignSystem.Colors.shadowMedium, radius: 12, x: 0, y: 6)
    }
}

private struct HomeStatChip: View {
    let title: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(DesignSystem.Typography.footnote)
                .foregroundStyle(Color.white.opacity(0.68))
            Text(value)
                .font(DesignSystem.Typography.footnoteMedium)
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white.opacity(0.10))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

private struct HomeHorizontalSectionStib: View {
    let title: String
    let subtitle: String
    let items: [HomeLineSpotlight]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DesignSystem.Typography.sectionTitleSmall)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text(subtitle)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(items) { item in
                        HomeLineSpotlightCard(item: item)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, 2)
            }
        }
    }
}

private struct HomeLineSpotlightCard: View {
    let item: HomeLineSpotlight

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(item.line)
                    .font(DesignSystem.Typography.bodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 8)
                    .background(item.color)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                Spacer()

                HStack(spacing: 4) {
                    Circle()
                        .fill(item.statusColor)
                        .frame(width: 8, height: 8)
                    Text(item.status)
                        .font(DesignSystem.Typography.footnoteMedium)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }
            }

            Text(item.title)
                .font(DesignSystem.Typography.cardTitle)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            Text(item.detail)
                .font(DesignSystem.Typography.description)
                .foregroundStyle(DesignSystem.Colors.secondaryText)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()

            HStack {
                Label(item.modeLabel, systemImage: item.modeIcon)
                    .font(DesignSystem.Typography.footnote)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Text(item.waitLabel)
                    .font(DesignSystem.Typography.footnoteMedium)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
            }
        }
        .padding(18)
        .frame(width: 250, height: 180)
        .background(DesignSystem.Colors.cardBackground)
        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
        .shadow(color: DesignSystem.Colors.shadow, radius: 6, x: 0, y: 3)
    }
}

private struct HomeAlertsSectionStib: View {
    let reports: [MeldingenReadModel]
    let onShowAll: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Current disruptions")
                        .font(DesignSystem.Typography.sectionTitleSmall)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text("Community alerts and urgent incidents happening now.")
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                }

                Spacer()

                Button(action: onShowAll) {
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
            .padding(.horizontal, DesignSystem.Spacing.md)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 14) {
                    ForEach(reports.prefix(5)) { report in
                        MeldingenCardView(signalement: report)
                            .frame(width: 260, height: 170)
                    }
                }
                .padding(.horizontal, DesignSystem.Spacing.md)
                .padding(.bottom, 2)
            }
        }
    }
}

private struct HomeQuickActionsSectionStib: View {
    let actions: [HomeQuickAction]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Quick actions")
                    .font(DesignSystem.Typography.sectionTitleSmall)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text("Jump directly into the tasks you use most.")
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)

            LazyVGrid(
                columns: [GridItem(.flexible()), GridItem(.flexible())],
                spacing: 14
            ) {
                ForEach(actions) { action in
                    Button(action: action.action) {
                        VStack(alignment: .leading, spacing: 12) {
                            ZStack {
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .fill(DesignSystem.Colors.accentSoft)
                                    .frame(width: 42, height: 42)
                                Image(systemName: action.icon)
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.accent)
                            }

                            Text(action.title)
                                .font(DesignSystem.Typography.cardTitle)
                                .foregroundStyle(DesignSystem.Colors.primaryText)
                            Text(action.subtitle)
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .frame(maxWidth: .infinity, minHeight: 150, alignment: .topLeading)
                        .padding(18)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                                .stroke(DesignSystem.Colors.border, lineWidth: 1)
                        )
                        .shadow(color: DesignSystem.Colors.shadow, radius: 6, x: 0, y: 3)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct HomeNearbyStopsSectionStib: View {
    let stops: [HomeStopRecommendation]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Nearby stops")
                    .font(DesignSystem.Typography.sectionTitleSmall)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                Text("Practical nearby options when your route changes unexpectedly.")
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
            }
            .padding(.horizontal, DesignSystem.Spacing.md)

            LazyVStack(spacing: 14) {
                ForEach(stops) { stop in
                    HStack(spacing: 14) {
                        ZStack {
                            RoundedRectangle(cornerRadius: 14, style: .continuous)
                                .fill(stop.tint.opacity(0.12))
                                .frame(width: 56, height: 56)
                            Image(systemName: stop.icon)
                                .font(.system(size: 20, weight: .semibold))
                                .foregroundStyle(stop.tint)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            Text(stop.name)
                                .font(DesignSystem.Typography.cardTitle)
                                .foregroundStyle(DesignSystem.Colors.primaryText)
                            Text(stop.detail)
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .fixedSize(horizontal: false, vertical: true)
                            HStack(spacing: 8) {
                                Text(stop.distance)
                                Text("•")
                                Text(stop.nextDepartures)
                            }
                            .font(DesignSystem.Typography.footnote)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                        }

                        Spacer()

                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }
                    .padding(18)
                    .background(DesignSystem.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DesignSystem.CornerRadius.large, style: .continuous)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, DesignSystem.Spacing.md)
        }
    }
}

private struct HomeLineSpotlight: Identifiable {
    enum Mode {
        case metro
        case tram
        case bus
    }

    let id = UUID()
    let line: String
    let title: String
    let detail: String
    let status: String
    let waitLabel: String
    let mode: Mode
    let color: Color
    let statusColor: Color

    var modeLabel: String {
        switch mode {
        case .metro: return "Metro corridor"
        case .tram: return "Tram corridor"
        case .bus: return "Bus corridor"
        }
    }

    var modeIcon: String {
        switch mode {
        case .metro: return "m.circle.fill"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        }
    }
}

private struct HomeStopRecommendation: Identifiable {
    let id = UUID()
    let name: String
    let detail: String
    let distance: String
    let nextDepartures: String
    let icon: String
    let tint: Color
}

private struct HomeQuickAction: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let icon: String
    let action: () -> Void
}

private enum HomeMockData {
    static let lineSpotlights: [HomeLineSpotlight] = [
        .init(
            line: "6",
            title: "Roi Baudouin to Elisabeth",
            detail: "Heavy platform traffic near Heysel, but departures remain stable.",
            status: "Stable",
            waitLabel: "2 min avg",
            mode: .metro,
            color: Color(hex: "#00A651"),
            statusColor: .green
        ),
        .init(
            line: "7",
            title: "Vanderkindere to Heysel",
            detail: "Minor delays reported after peak crowding at Montgomery.",
            status: "Slow",
            waitLabel: "5 min avg",
            mode: .tram,
            color: Color(hex: "#C41E3A"),
            statusColor: .orange
        ),
        .init(
            line: "95",
            title: "Central corridor to Wiener",
            detail: "Roadworks causing bus bunching near Luxembourg.",
            status: "Alert",
            waitLabel: "7 min avg",
            mode: .bus,
            color: Color(hex: "#2F6BFF"),
            statusColor: .red
        )
    ]

    static let nearbyStops: [HomeStopRecommendation] = [
        .init(
            name: "Gare Centrale",
            detail: "Strong interchanges between metro and main tram lines.",
            distance: "4 min walk",
            nextDepartures: "1, 5, 29",
            icon: "tram.fill",
            tint: Color(hex: "#4557A1")
        ),
        .init(
            name: "Arts-Loi",
            detail: "Useful fallback when lines 1 and 6 become crowded.",
            distance: "7 min walk",
            nextDepartures: "2, 6, 12",
            icon: "m.circle.fill",
            tint: Color(hex: "#232323")
        ),
        .init(
            name: "De Brouckère",
            detail: "Dense central hub with good rerouting options across the city.",
            distance: "9 min walk",
            nextDepartures: "3, 4, 5, 71",
            icon: "bus.doubledecker.fill",
            tint: Color(hex: "#CBB99E")
        )
    ]

    static let sampleReports: [MeldingenReadModel] = [
        .init(
            _id: "mock-1",
            utilisateurId: nil,
            arretId: .init(
                _id: "h1",
                stopId: "5710",
                nom: "Arts-Loi",
                latitude: 50.844,
                longitude: 4.369,
                typeTransport: ["metro"],
                lignesDesservies: ["2", "6"],
                etat: "normal",
                signalementsRecents: nil,
                order: nil,
                distanceToUser: nil
            ),
            ligne: "6",
            typeProbleme: "Vertraging",
            description: "Crowding and slower departures near the central interchange.",
            photo: nil,
            dateSignalement: Date().addingTimeInterval(-1200),
            validationIA: true,
            resumeIA: "Delay confirmed near Arts-Loi.",
            votesPositifs: 9,
            votesNegatifs: 1,
            signalements: 3,
            latitude: 50.844,
            longitude: 4.369,
            confiance: "élevée"
        ),
        .init(
            _id: "mock-2",
            utilisateurId: nil,
            arretId: .init(
                _id: "h2",
                stopId: "3982",
                nom: "Louise",
                latitude: 50.835,
                longitude: 4.357,
                typeTransport: ["tram", "metro"],
                lignesDesservies: ["2", "8", "93"],
                etat: "perturbé",
                signalementsRecents: nil,
                order: nil,
                distanceToUser: nil
            ),
            ligne: "8",
            typeProbleme: "Incident",
            description: "Platform access constrained after a vehicle issue.",
            photo: nil,
            dateSignalement: Date().addingTimeInterval(-2200),
            validationIA: true,
            resumeIA: "Incident reported near Louise.",
            votesPositifs: 6,
            votesNegatifs: 0,
            signalements: 2,
            latitude: 50.835,
            longitude: 4.357,
            confiance: "moyenne"
        )
    ]
}

struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Home(authViewModel: AuthViewModel())
            .environmentObject(MainTabSelection())
            .environmentObject(TabBarVisibility())
    }
}
