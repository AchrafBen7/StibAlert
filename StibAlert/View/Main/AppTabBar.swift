import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case lines
    case reports
    case favorites
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "Carte"
        case .lines: return "Lignes"
        case .reports: return "Reports"
        case .favorites: return "Favoris"
        case .profile: return "Profil"
        }
    }

    var icon: String {
        switch self {
        case .home: return "map.fill"
        case .lines: return "tram.fill"
        case .reports: return "bubble.left.and.exclamationmark.bubble.right.fill"
        case .favorites: return "heart.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var page: AppPage {
        switch self {
        case .home: return .home
        case .lines: return .signalements
        case .reports: return .reports
        case .favorites: return .favorites
        case .profile: return .profile
        }
    }

    static func from(page: AppPage) -> AppTab {
        switch page {
        case .home: return .home
        case .signalements: return .lines
        case .reports: return .reports
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
        .frame(height: 70)
        .background(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .fill(DS.Color.paper.opacity(0.97))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(DS.Shadow.overlay)
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
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .fill(DS.Color.paper2)
                        .matchedGeometryEffect(id: "activeTab", in: indicator)
                }

                VStack(spacing: 3) {
                    Image(systemName: tab.icon)
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(isActive ? DS.Color.primary : DS.Color.inkMute)
                    Text(tab.title)
                        .font(DS.Font.caption)
                        .foregroundStyle(isActive ? DS.Color.ink : DS.Color.inkMute)
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
