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
    let onSelectTab: (AppTab) -> Void

    var body: some View {
        VStack(spacing: 8) {
            if shouldShowPulseBar {
                HStack(alignment: .center, spacing: 10) {
                    if totalActiveSignalementsCount > 0 {
                        HomePulseBar(
                            totalActive: totalActiveSignalementsCount,
                            favoriteAffectedCount: favoriteAffectedCount,
                            eventCount: highlightedEventCount,
                            refreshedAt: refreshedAt,
                            onOpenReports: onOpenReports
                        )
                        .transition(.opacity.combined(with: .scale(scale: 0.96)))
                    }
                    Spacer()
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
            }
        }
        .padding(.bottom, 6)
        .zIndex(8)
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

                VStack(alignment: .leading, spacing: 1) {
                    Text(titleText)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    if let refreshedAt {
                        (Text("Actualisé ") + Text(refreshedAt, style: .relative))
                            .font(DS.Font.monoSmall)
                            .tracking(0.8)
                            .textCase(.uppercase)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }
                }

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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 13, weight: .heavy))
                Text("Signaler")
                    .font(DS.Font.bodyBold)
            }
            .foregroundStyle(DS.Color.primaryForeground)
            .padding(.horizontal, 18)
            .frame(height: 58)
            .background(DS.Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(DS.Shadow.overlay)
        }
        .buttonStyle(.plain)
    }
}

struct LocationFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.paper.opacity(0.96))
                .frame(width: 42, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .rotationEffect(.degrees(18))
                )
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recentrer la carte")
        .accessibilityHint("Replace la carte sur votre position")
    }
}
