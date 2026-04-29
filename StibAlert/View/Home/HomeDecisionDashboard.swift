import SwiftUI

struct HomeDashboardData {
    let commuteBrief: AssistantBriefDTO?
    let decision: TransportHomeDecisionData?
    let recommendedAlternative: HomeRecommendedAlternativeItem?
    let recommendedAlternativeDetail: TransportAlternativeDTO?
    let monitoredLines: [HomeMonitoredLineItem]
    let nearbyAlerts: [HomeNearbyAlertItem]
    let favoriteLines: [HomeFavoriteLineItem]
}

struct HomeMonitoredLineItem: Identifiable {
    let id: String
    let line: String
    let statusText: String
    let departureText: String
}

struct HomeNearbyAlertItem: Identifiable {
    let id: String
    let line: String
    let title: String
    let detail: String
    let confirmationText: String
}

struct HomeDecisionDashboard: View {
    let data: HomeDashboardData
    let isLoadingDecision: Bool
    let onOpenStibi: () -> Void
    let onPrimaryCommuteAction: () -> Void
    let onOpenLine: (String) -> Void
    let onOpenAlert: (String) -> Void
    let onOpenAlternative: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                if !data.monitoredLines.isEmpty {
                    HomeDecisionSectionCard(title: "Mes lignes surveillées") {
                        VStack(spacing: 10) {
                            ForEach(Array(data.monitoredLines.prefix(3))) { line in
                                HomeMonitoredLineRow(item: line) {
                                    onOpenLine(line.line)
                                }
                            }
                        }
                    }
                }

                if !data.favoriteLines.isEmpty {
                    HomeDecisionSectionCard(title: "Lignes favorites") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 10)], spacing: 10) {
                            ForEach(Array(data.favoriteLines.prefix(4))) { line in
                                HomeFavoriteLinePill(item: line) {
                                    onOpenLine(line.line)
                                }
                            }
                        }
                    }
                }

                if !data.nearbyAlerts.isEmpty {
                    HomeDecisionSectionCard(title: "Alertes confirmées près de moi") {
                        VStack(spacing: 10) {
                            ForEach(Array(data.nearbyAlerts.prefix(2))) { alert in
                                HomeNearbyAlertRow(item: alert) {
                                    onOpenAlert(alert.id)
                                }
                            }
                        }
                    }
                }

            }
            .padding(14)
            .background(AppTheme.Palette.screenElevated.opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(AppTheme.Palette.border, lineWidth: 1)
            )
        }
    }
}

private struct HomeFavoriteLinePill: View {
    let item: HomeFavoriteLineItem
    let onTap: () -> Void

    private var tint: Color {
        let lowered = item.statusText.lowercased()
        if lowered.contains("critique") || lowered.contains("bloqué") { return Color(hex: "#FF7A7A") }
        if lowered.contains("perturb") || lowered.contains("mineur") { return Color(hex: "#FFB15A") }
        return Color(hex: "#57E3B6")
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(item.line)
                        .font(AppTheme.Fonts.clash(14))
                        .foregroundStyle(AppTheme.Palette.textPrimary)

                    Text(item.statusText)
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                        .lineLimit(1)
                }

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(tint)
                        .frame(width: 8, height: 8)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textMuted)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.surface.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
        .buttonStyle(.plain)
    }
}

private struct HomeRecommendedAlternativeCard: View {
    let item: HomeRecommendedAlternativeItem
    let isInteractive: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: {
            guard isInteractive else { return }
            onTap()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(item.title)
                            .font(.custom("Montserrat-SemiBold", size: 14))
                            .foregroundStyle(.white)

                        Text(item.reason)
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(Color.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    VStack(alignment: .trailing, spacing: 4) {
                        Text(item.etaText)
                            .font(.custom("DelaGothicOne-Regular", size: 18))
                            .foregroundStyle(Color(hex: "#B5CFF8"))

                        Text(item.reliabilityText)
                            .font(.custom("Montserrat-SemiBold", size: 11))
                            .foregroundStyle(Color.white.opacity(0.72))
                    }
                }

                if isInteractive {
                    HStack(spacing: 8) {
                        Text("Voir les étapes")
                            .font(.custom("Montserrat-SemiBold", size: 11))
                            .foregroundStyle(Color(hex: "#B5CFF8"))

                        Spacer()

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.34))
                    }
                }
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: "#1A2231"), Color.white.opacity(0.04)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "#B5CFF8").opacity(0.18), lineWidth: 1)
        )
        .buttonStyle(.plain)
    }
}

private struct HomeDecisionSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.custom("Montserrat-SemiBold", size: 12))
                .textCase(.uppercase)
                .foregroundStyle(Color.white.opacity(0.66))

            content
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#10151F").opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct HomeMonitoredLineRow: View {
    let item: HomeMonitoredLineItem
    let onTap: () -> Void

    private var toneColor: Color {
        switch item.statusText.lowercased() {
        case let text where text.contains("bloqué"), let text where text.contains("critique"):
            return Color(hex: "#FF7A7A")
        case let text where text.contains("perturb"), let text where text.contains("surveillance"):
            return Color(hex: "#FFB15A")
        default:
            return Color(hex: "#57E3B6")
        }
    }

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Text(item.line)
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 32)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(item.statusText)
                        .font(.custom("Montserrat-SemiBold", size: 13))
                        .foregroundStyle(.white)

                    Text(item.departureText)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(Color.white.opacity(0.72))
                }

                Spacer()

                HStack(spacing: 8) {
                    Circle()
                        .fill(toneColor)
                        .frame(width: 10, height: 10)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.34))
                }
            }
        }
        .buttonStyle(.plain)
    }
}

private struct HomeNearbyAlertRow: View {
    let item: HomeNearbyAlertItem
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 10) {
                    Text(item.line)
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(Color(hex: "#0C121D"))
                        .padding(.horizontal, 10)
                        .frame(height: 26)
                        .background(Color.white.opacity(0.7))
                        .clipShape(Capsule())

                    Text(item.title)
                        .font(.custom("Montserrat-SemiBold", size: 13))
                        .foregroundStyle(.white)
                        .lineLimit(1)

                    Spacer()

                    HStack(spacing: 8) {
                        Text(item.confirmationText)
                            .font(.custom("Montserrat-SemiBold", size: 11))
                            .foregroundStyle(Color.white.opacity(0.54))

                        Image(systemName: "chevron.right")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.34))
                    }
                }

                Text(item.detail)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.76))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.04))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.06), lineWidth: 1)
        )
        .buttonStyle(.plain)
    }
}
