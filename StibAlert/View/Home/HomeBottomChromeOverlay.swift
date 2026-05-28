import SwiftUI

struct HomeBottomChromeOverlay: View {
    let currentPage: AppPage
    let shouldShowPulseBar: Bool
    let shouldShowTabBar: Bool
    let totalActiveSignalementsCount: Int
    let favoriteAffectedCount: Int
    let highlightedEventCount: Int
    let refreshedAt: Date?
    let onOpenReports: () -> Void
    let onOpenReportSheet: () -> Void
    let onOpenVoice: () -> Void
    let onOpenStibAI: () -> Void
    let onRecenter: () -> Void
    let onSelectTab: (AppTab) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if shouldShowPulseBar {
                // Layout: [Mic] far-left  ........  [Location] [AI] [+] right-grouped.
                // Mic stays visually distinct (round red) on the left while the
                // three right-side controls cluster next to the report FAB.
                HStack(alignment: .center, spacing: 10) {
                    MapVoiceFloatingButton(action: onOpenVoice)
                    Spacer(minLength: 8)
                    LocationFloatingButton(action: onRecenter)
                    STIBAIFloatingButton(action: onOpenStibAI)
                    HomeReportFloatingButton(action: onOpenReportSheet)
                }
                .padding(.horizontal, 14)
                .transition(.opacity)
            }

            if shouldShowTabBar {
                AppTabBar(selection: Binding(
                    get: { AppTab.from(page: currentPage) },
                    set: onSelectTab
                ))
                .transition(.opacity)
                .accessibilityElement(children: .contain)
                .accessibilityLabel("Barre de navigation")
            }
        }
        .padding(.bottom, 6)
        .padding(.bottom, 8) // iOS 17.5+ safe area bottom adjustment
        .zLayer(.bottomChrome)
    }
}

private struct HomePulseBar: View {
    let totalActive: Int
    let favoriteAffectedCount: Int
    let eventCount: Int
    let refreshedAt: Date?
    let onOpenReports: () -> Void

    private var titleText: String {
        if favoriteAffectedCount > 0 {
            return favoriteAffectedCount == 1
                ? "1 incident sur tes lignes"
                : "\(favoriteAffectedCount) incidents sur tes lignes"
        }
        return totalActive == 1 ? "1 signalement actif" : "\(totalActive) signalements actifs"
    }

    var body: some View {
        Button(action: onOpenReports) {
            HStack(spacing: 10) {
                Circle()
                    .fill(favoriteAffectedCount > 0 ? DS.Color.statusMajor : DS.Color.statusMinor)
                    .frame(width: 10, height: 10)

                Text(titleText)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)

                Image(systemName: "chevron.up")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.Color.paper.opacity(0.98))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(DS.Shadow.overlay)
        }
        .buttonStyle(.plain)
        .fixedSize(horizontal: true, vertical: false)
    }
}

private struct HomeReportFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            Image(systemName: "plus")
                .font(.system(size: 18, weight: .heavy))
                .foregroundStyle(DS.Color.primaryForeground)
                .frame(width: 58, height: 58)
                .background(DS.Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .shadow(DS.Shadow.overlay)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Signaler")
    }
}

struct LocationFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "location.north.fill")
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
                .rotationEffect(.degrees(18))
                .frame(width: 46, height: 46)
                .background(Circle().fill(DS.Color.paper.opacity(0.96)))
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1))
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recentrer la carte")
        .accessibilityHint("Replace la carte sur votre position")
    }
}
