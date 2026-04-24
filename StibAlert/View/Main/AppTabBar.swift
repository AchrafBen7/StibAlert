import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case lines
    case favorites
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Carte"
        case .lines: return "Lignes"
        case .favorites: return "Favoris"
        case .profile: return "Profil"
        }
    }

    var icon: String {
        switch self {
        case .home: return "map.fill"
        case .lines: return "tram.fill"
        case .favorites: return "heart.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var page: AppPage {
        switch self {
        case .home: return .home
        case .lines: return .signalements
        case .favorites: return .favorites
        case .profile: return .profileMain
        }
    }

    static func from(page: AppPage) -> AppTab {
        switch page {
        case .home: return .home
        case .signalements: return .lines
        case .favorites: return .favorites
        case .profile, .profileMain: return .profile
        }
    }
}

struct AppTabBar: View {
    @Binding var selection: AppTab
    var onSelect: ((AppTab) -> Void)? = nil

    @Namespace private var indicator

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                tabItem(for: tab)
            }
        }
        .padding(6)
        .frame(height: 68)
        .background(
            Capsule(style: .continuous)
                .fill(AppTheme.Palette.screenElevated.opacity(0.96))
        )
        .overlay(
            Capsule(style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 18, x: 0, y: 10)
        .padding(.horizontal, 18)
    }

    private func tabItem(for tab: AppTab) -> some View {
        let isActive = selection == tab
        return Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            withAnimation(.spring(response: 0.32, dampingFraction: 0.82)) {
                selection = tab
            }
            onSelect?(tab)
        } label: {
            ZStack {
                if isActive {
                    Capsule(style: .continuous)
                        .fill(AppTheme.Palette.surface)
                        .matchedGeometryEffect(id: "activeTab", in: indicator)
                }

                VStack(spacing: 3) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isActive ? AppTheme.Palette.brand : AppTheme.Palette.textMuted)
                    Text(tab.title)
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(isActive ? AppTheme.Palette.textPrimary : AppTheme.Palette.textMuted)
                }
                .padding(.vertical, 6)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
        .accessibilityAddTraits(isActive ? [.isSelected] : [])
    }
}
