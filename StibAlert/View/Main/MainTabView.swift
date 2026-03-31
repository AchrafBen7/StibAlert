import SwiftUI
import UIKit

struct MainTabView: View {
    enum Tab: CaseIterable {
        case map
        case reports
        case create
        case favorites
        case profile
    }

    @EnvironmentObject var mainTabSelection: MainTabSelection
    @EnvironmentObject var tabBarVisibility: TabBarVisibility

    @StateObject private var authViewModel = AuthViewModel()
    @StateObject private var networkMonitor = NetworkMonitor.shared

    init() {
        UITabBar.appearance().isHidden = true
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DesignSystem.Colors.background
                .ignoresSafeArea()

            TabView(selection: $mainTabSelection.currentTab) {
                Home(authViewModel: authViewModel)
                    .environmentObject(tabBarVisibility)
                    .tag(Tab.map)
                    .tabItem { EmptyView() }

                NavigationStack {
                    AllReportsView()
                }
                .environmentObject(tabBarVisibility)
                .tag(Tab.reports)
                .tabItem { EmptyView() }

                NavigationStack {
                    NewMeldingView()
                }
                .environmentObject(tabBarVisibility)
                .tag(Tab.create)
                .tabItem { EmptyView() }

                NavigationStack {
                    FavorisView(authViewModel: authViewModel)
                }
                .environmentObject(tabBarVisibility)
                .tag(Tab.favorites)
                .tabItem { EmptyView() }

                NavigationStack {
                    ProfileTabEntryView(authViewModel: authViewModel)
                }
                .environmentObject(tabBarVisibility)
                .tag(Tab.profile)
                .tabItem { EmptyView() }
            }
            .toolbar(.hidden, for: .tabBar)
            .animation(nil, value: mainTabSelection.currentTab)
            .transaction { transaction in
                transaction.animation = nil
            }

            if !networkMonitor.isConnected {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "wifi.slash")
                            .font(.subheadline)
                        Text(String(localized: "network.offline", defaultValue: "No internet connection"))
                            .font(.subheadline.weight(.medium))
                    }
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .padding(.top, 44)
                    .background(DesignSystem.Colors.error.opacity(0.92))

                    Spacer()
                }
                .ignoresSafeArea(edges: .top)
                .transition(.move(edge: .top).combined(with: .opacity))
            }

            if !tabBarVisibility.isHidden {
                CustomTabBar(selection: $mainTabSelection.currentTab)
            }
        }
    }
}

private struct ProfileTabEntryView: View {
    @ObservedObject var authViewModel: AuthViewModel

    var body: some View {
        Group {
            if authViewModel.isAuthenticated {
                ProfilView(authViewModel: authViewModel)
            } else {
                ConnexionView(authVM: authViewModel)
            }
        }
    }
}
