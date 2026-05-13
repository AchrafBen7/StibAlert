import SwiftUI

struct InsightsCard: View {
    @State private var insights: InsightsDTO? = nil
    @State private var isLoading = true
    @State private var loadError: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header

            if isLoading {
                loadingState
            } else if let loadError {
                errorView(message: loadError)
            } else if let insights {
                narrativeBlock(insights)
                statsGrid(insights)
                if let disclaimer = insights.disclaimer {
                    Text(disclaimer)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 4)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(backgroundColor)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(borderColor, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await load() }
    }

    private var backgroundColor: Color {
        guard let tone = insights?.narrative.tone else { return DS.Color.paper2 }
        switch tone {
        case "win": return DS.Color.primary.opacity(0.06)
        case "neutral": return DS.Color.paper2.opacity(0.5)
        case "setup": return Color(hex: "#F59E0B").opacity(0.08)
        default: return DS.Color.paper2
        }
    }

    private var borderColor: Color {
        guard let tone = insights?.narrative.tone else { return DS.Color.ink.opacity(0.08) }
        switch tone {
        case "win": return DS.Color.primary.opacity(0.25)
        case "setup": return Color(hex: "#F59E0B").opacity(0.3)
        default: return DS.Color.ink.opacity(0.08)
        }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "chart.line.uptrend.xyaxis")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(DS.Color.primary)
            Text("Tes statistiques · 30 jours")
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
        }
    }

    private var loadingState: some View {
        HStack {
            ProgressView().scaleEffect(0.8)
            Text("Calcul en cours…")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
        }
    }

    private func errorView(message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle")
                .foregroundStyle(Color(hex: "#E94E1B"))
            Text(message)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
            Button("Réessayer") { Task { await load() } }
                .font(DS.Font.body.weight(.semibold))
                .foregroundStyle(DS.Color.primary)
        }
    }

    private func narrativeBlock(_ insights: InsightsDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(insights.narrative.headline)
                .font(.custom("DelaGothicOne-Regular", size: 22))
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(insights.narrative.body)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func statsGrid(_ insights: InsightsDTO) -> some View {
        HStack(spacing: 10) {
            statCell(
                icon: "clock.fill",
                value: formattedTime(insights.estimatedMinutesSaved),
                label: "économisées",
                emphasized: insights.estimatedMinutesSaved > 0
            )
            statCell(
                icon: "person.2.fill",
                value: "\(insights.peopleHelped)",
                label: "aidé\(insights.peopleHelped > 1 ? "es" : "e")",
                emphasized: insights.peopleHelped > 0
            )
            statCell(
                icon: "exclamationmark.triangle.fill",
                value: "\(insights.disruptionsAvoided)",
                label: "perturbations"
            )
        }
    }

    private func statCell(
        icon: String,
        value: String,
        label: String,
        emphasized: Bool = false
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(emphasized ? DS.Color.primary : DS.Color.inkMute)
            Text(value)
                .font(DS.Font.displayH3)
                .foregroundStyle(emphasized ? DS.Color.primary : DS.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .font(DS.Font.monoSmall)
                .tracking(0.3)
                .foregroundStyle(DS.Color.inkMute)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func formattedTime(_ minutes: Int) -> String {
        if minutes <= 0 { return "—" }
        if minutes < 60 { return "\(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        if mins == 0 { return "\(hours)h" }
        return "\(hours)h\(String(format: "%02d", mins))"
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let result = try await InsightsService.mine()
            await MainActor.run {
                self.insights = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Impossible de charger."
                self.isLoading = false
            }
        }
    }
}
