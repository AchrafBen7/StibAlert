import SwiftUI

struct ContributionsCard: View {
    @EnvironmentObject private var session: AuthSession
    var onConfigureRoutine: (() -> Void)? = nil

    @State private var data: ContributionsResponse? = nil
    @State private var isLoading = true
    @State private var loadError: String? = nil

    private var needsRoutineSetup: Bool {
        guard let user = session.currentUser else { return false }
        let hasRoutine = user.routine?.enabled == true
        let hasFavoriteLines = !(user.favoriteLines ?? []).isEmpty
        return !hasRoutine && !hasFavoriteLines
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            if needsRoutineSetup && (data?.summary.totalContributions ?? 0) == 0 {
                coldStartPrompt
            }
            if isLoading {
                loadingState
            } else if let loadError {
                errorView(message: loadError)
            } else if let data {
                statsGrid(data.summary)
                if !data.recent.isEmpty {
                    recentList(data.recent)
                } else if !needsRoutineSetup {
                    emptyHint
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .task { await load() }
    }

    private var header: some View {
        HStack(spacing: 8) {
            Image(systemName: "hands.sparkles.fill")
                .font(.system(size: 14, weight: .heavy))
                .foregroundStyle(DS.Color.primary)
            Text("Tes contributions")
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
        }
    }

    private var loadingState: some View {
        HStack {
            ProgressView()
                .scaleEffect(0.8)
            Text("Chargement…")
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

    private func statsGrid(_ summary: ContributionsSummary) -> some View {
        HStack(spacing: 10) {
            statCell(value: "\(summary.totalContributions)", label: "Signalements")
            statCell(value: "\(summary.peopleHelpedTotal)", label: "Personnes aidées")
            statCell(value: "\(summary.publishedClusters)", label: "Alertes publiées")
            statCell(value: "\(summary.firstReporterCount)", label: "Première alerte", emphasized: summary.firstReporterCount > 0)
        }
    }

    private func statCell(value: String, label: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value)
                .font(DS.Font.displayH3)
                .foregroundStyle(emphasized ? DS.Color.primary : DS.Color.ink)
            Text(label)
                .font(DS.Font.monoSmall)
                .tracking(0.4)
                .foregroundStyle(DS.Color.inkMute)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var coldStartPrompt: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.primary)
                Text("Configure ton trajet régulier")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
            }
            Text("Choisis ta ligne et ton arrêt habituels. Quand un cluster les affecte, StibAlert t'ouvre direct sur un Plan B.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .fixedSize(horizontal: false, vertical: true)
            Button {
                onConfigureRoutine?()
            } label: {
                HStack(spacing: 6) {
                    Image(systemName: "arrow.right.circle.fill")
                    Text("Configurer maintenant")
                        .font(DS.Font.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(DS.Color.primary)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DS.Color.primary.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var emptyHint: some View {
        Text("Tu n'as pas encore signalé. Ouvre la carte et tape « Signaler » pour aider la communauté.")
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.inkMute)
            .fixedSize(horizontal: false, vertical: true)
    }

    private func recentList(_ items: [ContributionItem]) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("RÉCENTS")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 4)

            ForEach(items.prefix(5)) { item in
                HStack(alignment: .center, spacing: 10) {
                    if let ligne = item.ligne {
                        LineBadge(line: ligne, size: .sm)
                    }
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.typeProbleme ?? "Signalement")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.ink)
                        if let helped = item.peopleHelped, helped > 0 {
                            Text("A aidé \(helped) personne\(helped > 1 ? "s" : "")")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(Color(hex: "#10B981"))
                        } else if item.helpedPublishCluster {
                            Text("Cluster publié")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.primary)
                        } else {
                            Text(item.roleLabel)
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                    Spacer()
                    if let date = item.createdAt {
                        Text(date, style: .relative)
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
                .padding(.vertical, 4)
            }
        }
    }

    private func load() async {
        isLoading = true
        loadError = nil
        do {
            let response = try await ContributionsService.mine()
            await MainActor.run {
                self.data = response
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
