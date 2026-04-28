import SwiftUI

struct HomeDashboardData {
    let commuteBrief: AssistantBriefDTO?
    let decision: TransportHomeDecisionData?
    let recommendedAlternative: HomeRecommendedAlternativeItem?
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

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Décision maintenant")
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                        .foregroundStyle(.white)

                    Text("Stibi priorise le départ, la fiabilité et les alertes confirmées.")
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer()

                Button(action: onOpenStibi) {
                    Text("Stibi")
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 12)
                        .frame(height: 32)
                        .background(Color(hex: "#B5CFF8"))
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 10) {
                if let commuteBrief = data.commuteBrief {
                    MorningCommuteStatusCard(
                        brief: commuteBrief,
                        onOpenStibi: onOpenStibi,
                        onPrimaryAction: onPrimaryCommuteAction
                    )
                }

            if let decision = data.decision {
                HomeDecisionCard(data: decision, isLoading: isLoadingDecision)
            }

            if let recommendedAlternative = data.recommendedAlternative {
                HomeDecisionSectionCard(title: "Meilleure alternative maintenant") {
                    HomeRecommendedAlternativeCard(item: recommendedAlternative)
                }
            }

                if !data.monitoredLines.isEmpty {
                    HomeDecisionSectionCard(title: "Mes lignes surveillées") {
                        VStack(spacing: 10) {
                            ForEach(data.monitoredLines) { line in
                                HomeMonitoredLineRow(item: line)
                            }
                        }
                    }
                }

                if !data.favoriteLines.isEmpty {
                    HomeDecisionSectionCard(title: "Lignes favorites") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 10)], spacing: 10) {
                            ForEach(data.favoriteLines) { line in
                                HomeFavoriteLinePill(item: line)
                            }
                        }
                    }
                }

                if !data.nearbyAlerts.isEmpty {
                    HomeDecisionSectionCard(title: "Alertes confirmées près de moi") {
                        VStack(spacing: 10) {
                            ForEach(data.nearbyAlerts) { alert in
                                HomeNearbyAlertRow(item: alert)
                            }
                        }
                    }
                }

            }
            .padding(14)
            .background(Color(hex: "#0C121D").opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
        }
    }
}

private struct HomeFavoriteLinePill: View {
    let item: HomeFavoriteLineItem

    private var tint: Color {
        let lowered = item.statusText.lowercased()
        if lowered.contains("critique") || lowered.contains("bloqué") { return Color(hex: "#FF7A7A") }
        if lowered.contains("perturb") || lowered.contains("mineur") { return Color(hex: "#FFB15A") }
        return Color(hex: "#57E3B6")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(item.line)
                    .font(.custom("DelaGothicOne-Regular", size: 15))
                    .foregroundStyle(.white)
                Spacer()
                Circle()
                    .fill(tint)
                    .frame(width: 8, height: 8)
            }

            Text(item.statusText)
                .font(.custom("Montserrat-SemiBold", size: 11))
                .foregroundStyle(Color.white.opacity(0.74))
                .lineLimit(1)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HomeRecommendedAlternativeCard: View {
    let item: HomeRecommendedAlternativeItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
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
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}

private struct HomeDecisionSectionCard<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.custom("DelaGothicOne-Regular", size: 15))
                .foregroundStyle(.white)

            content
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#10151F").opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct HomeMonitoredLineRow: View {
    let item: HomeMonitoredLineItem

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

            Circle()
                .fill(toneColor)
                .frame(width: 10, height: 10)
        }
    }
}

private struct HomeNearbyAlertRow: View {
    let item: HomeNearbyAlertItem

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text(item.line)
                    .font(.custom("Montserrat-SemiBold", size: 14))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 28)
                    .background(Color(hex: "#F29DC3"))
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                Text(item.title)
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.black)

                Spacer()

                Text(item.confirmationText)
                    .font(.custom("Montserrat-SemiBold", size: 11))
                    .foregroundStyle(.black.opacity(0.76))
            }

            Text(item.detail)
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.black.opacity(0.84))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#BBDCFF"))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
