import SwiftUI
import UIKit

enum AppTab: String, CaseIterable, Identifiable {
    case home
    case schedules
    case live           // renamed "Live" → "Infos trafic" in the UI
    case favorites
    case profile

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return AppLocalizer.string("tab.map", defaultValue: "Carte")
        case .schedules: return AppLocalizer.string("tab.schedules", defaultValue: "Horaires")
        case .live: return AppLocalizer.string("tab.traffic", defaultValue: "Infos trafic")
        case .favorites: return AppLocalizer.string("tab.favorites", defaultValue: "Favoris")
        case .profile: return AppLocalizer.string("tab.profile", defaultValue: "Profil")
        }
    }

    var icon: String {
        switch self {
        case .home: return "map.fill"
        case .schedules: return "clock.fill"
        case .live: return "exclamationmark.triangle.fill"
        case .favorites: return "heart.fill"
        case .profile: return "person.crop.circle.fill"
        }
    }

    var page: AppPage {
        switch self {
        case .home: return .home
        case .schedules: return .schedules
        case .live: return .reports
        case .favorites: return .favorites
        case .profile: return .profile
        }
    }

    static func from(page: AppPage) -> AppTab {
        switch page {
        case .home: return .home
        case .schedules: return .schedules
        case .signalements, .reports: return .live
        case .favorites: return .favorites
        case .profile: return .profile
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
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(tab.title)
        .accessibilityHint(isActive
            ? AppLocalizer.string("tab.accessibility.selected", defaultValue: "Onglet sélectionné")
            : AppLocalizer.string("tab.accessibility.select_hint", defaultValue: "Double-tap pour sélectionner cet onglet")
        )
        .accessibilityAddTraits(isActive ? [.isSelected, .isButton] : [.isButton])
    }
}
