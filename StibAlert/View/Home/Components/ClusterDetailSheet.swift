import SwiftUI

struct ClusterDetailSheet: View {
    let clusterIndex: Int
    let onClose: () -> Void

    @State private var detail: ClusterDetailDTO? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(DS.Color.ink.opacity(0.1))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(DS.Shadow.overlay)
        .padding(.horizontal, 16)
        .padding(.bottom, 100)
        .task { await loadDetail() }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let cluster = detail {
                    // LineBadge affiche un badge RÉSEAU quand `ligne` est un nom
                    // d'opérateur (perturbation réseau), pas un « STIB » incohérent.
                    LineBadge(line: cluster.ligne, size: .lg)
                    Text(cluster.typeProbleme)
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)
                    confidenceLabel(for: cluster)
                } else {
                    Text(AppLocalizer.string("cluster.community_alert", defaultValue: "Alerte communauté"))
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)
                }
            }
            Spacer(minLength: 8)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 40, height: 40)
                    .background(DS.Color.paper2)
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalizer.string("Fermer le détail", defaultValue: "Fermer le détail"))
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    @State private var showConfidenceExplain = false

    private func confidenceLabel(for cluster: ClusterDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                // A1 — badge de statut unifié (Confirmé/Probable/À vérifier)
                // si le backend le fournit, sinon fallback sur low/med/high.
                if cluster.confidenceStatus != nil {
                    unifiedConfidenceBadge(cluster)
                } else {
                    confidenceBadge(cluster.confidence)
                }
                Text(AppLocalizer.format("plural.reports", defaultValue: "%lld rapports", cluster.reportCount))
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        showConfidenceExplain.toggle()
                    }
                } label: {
                    Image(systemName: showConfidenceExplain ? "chevron.up.circle" : "info.circle")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizer.string("a11y.why_confidence", defaultValue: "Pourquoi cette confiance ?"))
            }

            if showConfidenceExplain {
                confidenceExplanation(for: cluster)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func confidenceExplanation(for cluster: ClusterDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(AppLocalizer.string("cluster.why_confidence", defaultValue: "POURQUOI CETTE CONFIANCE"))
                .font(DS.Font.labelSmall.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(DS.Color.inkMute)
            VStack(alignment: .leading, spacing: 4) {
                bulletPoint(AppLocalizer.format("cluster.reporters_count",
                                                defaultValue: "Signalements indépendants : %lld", cluster.reportCount))
                bulletPoint(AppLocalizer.format("cluster.avg_trust",
                                                defaultValue: "Score de confiance moyen : %lld/100", Int(cluster.aggregateTrust)))
                if cluster.signalements.contains(where: { $0.source == "user" }) {
                    bulletPoint(AppLocalizer.string("cluster.includes_authed",
                                                    defaultValue: "Inclut au moins 1 utilisateur authentifié"))
                }
                if let firstReportedAt = cluster.firstReportedAt {
                    let mins = max(1, Int(Date().timeIntervalSince(firstReportedAt) / 60))
                    bulletPoint(AppLocalizer.format("cluster.first_alert_ago",
                                                    defaultValue: "Première alerte il y a %lld min", mins))
                }
                if cluster.stillBlockedConfirmationCount > 0 {
                    bulletPoint(AppLocalizer.format("plural.confirmations_blocked",
                                                    defaultValue: "%lld confirmations « toujours bloqué »",
                                                    cluster.stillBlockedConfirmationCount))
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
    }

    private func bulletPoint(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 6) {
            Image(systemName: "checkmark")
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Color.success)
                .padding(.top, 2)
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// A1 — Badge du statut de confiance unifié (≥0.80 confirmé / ≥0.50
    /// probable / sinon à vérifier), avec le score 0–100 si disponible.
    private func unifiedConfidenceBadge(_ cluster: ClusterDetailDTO) -> some View {
        let status = cluster.confidenceStatus ?? "unverified"
        let label: String
        let color: Color
        switch status {
        case "confirmed": label = AppLocalizer.string("cluster.status.confirmed", defaultValue: "Confirmé"); color = DS.Color.success
        case "likely": label = AppLocalizer.string("cluster.status.likely", defaultValue: "Probable"); color = DS.Color.warning
        default: label = AppLocalizer.string("cluster.status.unverified", defaultValue: "À vérifier"); color = Color(hex: "#9CA3AF")
        }
        let pct = cluster.confidenceScore.map { " · \(Int(($0 * 100).rounded()))%" } ?? ""
        return Text("\(label)\(pct)")
            .font(DS.Font.labelSmall.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
            .accessibilityLabel(AppLocalizer.format("a11y.reliability", defaultValue: "Fiabilité : %@", label))
    }

    private func confidenceBadge(_ confidence: ClusterConfidence) -> some View {
        let color: Color
        switch confidence {
        case .high: color = DS.Color.danger
        case .medium: color = DS.Color.warning
        case .low: color = Color(hex: "#9CA3AF")
        }
        return Text(AppLocalizer.format("cluster.confidence_label", defaultValue: "Confiance : %@", confidence.displayLabel.lowercased()))
            .font(DS.Font.labelSmall.weight(.bold))
            .tracking(0.8)
            .foregroundStyle(color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    @ViewBuilder
    private var content: some View {
        if isLoading {
            SkeletonList(count: 3, style: .card)
                .padding(.top, 8)
                .frame(maxWidth: .infinity, minHeight: 200, alignment: .top)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(DS.Color.danger)
                Text(errorMessage)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
                Button("Réessayer") {
                    Task { await loadDetail() }
                }
                .buttonStyle(.borderedProminent)
            }
            .padding(20)
        } else if let detail {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    // A6 — Résumé IA "wat/waarom/hoelang/wat nu" en tête.
                    if let summary = detail.summary, !summary.isEmpty {
                        aiSummaryCard(summary)
                    }

                    ForEach(detail.signalements) { report in
                        reportRow(report)
                    }

                    if let expiresAt = detail.expiresAt {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                            Text(expiryText(expiresAt: expiresAt))
                                .font(DS.Font.labelSmall.weight(.bold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        .padding(.top, 8)
                    }

                    if detail.stillBlockedConfirmationCount > 0 {
                        Text(AppLocalizer.format("cluster.still_blocked_count",
                                                 defaultValue: "« Toujours bloqué » confirmé : %lld×",
                                                 detail.stillBlockedConfirmationCount))
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    if detail.resolveConfirmationCount > 0 {
                        Text(AppLocalizer.format("cluster.resolved_count",
                                                 defaultValue: "Résolu confirmé : %lld/3",
                                                 detail.resolveConfirmationCount))
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
                .padding(18)
            }
        }
    }

    /// A6 — Carte du résumé généré par l'IA (synthèse des N signalements).
    private func aiSummaryCard(_ summary: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.primary)
                .padding(.top, 1)
            VStack(alignment: .leading, spacing: 3) {
                Text(AppLocalizer.string("cluster.in_brief", defaultValue: "EN BREF"))
                    .font(DS.Font.labelSmall.weight(.bold))
                    .tracking(1.5)
                    .foregroundStyle(DS.Color.primary)
                Text(summary)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.primary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func reportRow(_ report: ClusterReportDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.source == "user" ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("« \(report.description ?? AppLocalizer.string("cluster.report_fallback", defaultValue: "Signalement")) »")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(3)
                if let timestamp = report.timestamp {
                    Text(timestamp, style: .relative)
                        .font(DS.Font.labelSmall)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(DS.Color.paper2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func expiryText(expiresAt: Date) -> String {
        let minutes = max(0, Int(expiresAt.timeIntervalSinceNow / 60))
        if minutes <= 0 { return AppLocalizer.string("cluster.expires_soon", defaultValue: "Expire bientôt") }
        if minutes < 60 { return AppLocalizer.format("cluster.expires_in_min", defaultValue: "Expire dans %lld min", minutes) }
        let hours = minutes / 60
        let mins = minutes % 60
        let hm = mins > 0 ? "\(hours)h \(mins)min" : "\(hours)h"
        return AppLocalizer.format("cluster.expires_in", defaultValue: "Expire dans %@", hm)
    }

    private func loadDetail() async {
        isLoading = true
        errorMessage = nil
        do {
            let loaded = try await ClusterService.detail(clusterIndex)
            await MainActor.run {
                self.detail = loaded
                self.isLoading = false
            }
        } catch {
            ErrorReporting.capture(error, tag: "cluster.detail.load", context: ["clusterIndex": clusterIndex])
            await MainActor.run {
                self.errorMessage = "Impossible de charger les détails."
                self.isLoading = false
            }
        }
    }

}
