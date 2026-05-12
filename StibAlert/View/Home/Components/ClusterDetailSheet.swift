import SwiftUI

struct ClusterDetailSheet: View {
    let clusterIndex: Int
    let onClose: () -> Void

    @State private var detail: ClusterDetailDTO? = nil
    @State private var isLoading = true
    @State private var errorMessage: String? = nil
    @State private var isConfirmingBlocked = false
    @State private var isConfirmingResolved = false
    @State private var hasVotedBlocked = false
    @State private var hasVotedResolved = false
    @State private var toastMessage: String? = nil

    var body: some View {
        VStack(spacing: 0) {
            headerView

            Divider()
                .background(DS.Color.ink.opacity(0.1))

            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)

            if detail != nil {
                Divider()
                    .background(DS.Color.ink.opacity(0.1))
                actionsView
            }
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
        .overlay(alignment: .bottom) {
            if let toast = toastMessage {
                Text(toast)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.black.opacity(0.85))
                    .clipShape(Capsule())
                    .padding(.bottom, 24)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
            }
        }
    }

    private var headerView: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                if let cluster = detail {
                    Text("Ligne \(cluster.ligne)")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(cluster.typeProbleme)
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)
                    confidenceLabel(for: cluster)
                } else {
                    Text("Alerte communauté")
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
            .accessibilityLabel("Fermer le détail")
        }
        .padding(.horizontal, 18)
        .padding(.top, 14)
        .padding(.bottom, 16)
    }

    @State private var showConfidenceExplain = false

    private func confidenceLabel(for cluster: ClusterDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                confidenceBadge(cluster.confidence)
                Text("\(cluster.reportCount) rapport\(cluster.reportCount > 1 ? "s" : "")")
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
                .accessibilityLabel("Pourquoi cette confiance ?")
            }

            if showConfidenceExplain {
                confidenceExplanation(for: cluster)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }

    private func confidenceExplanation(for cluster: ClusterDetailDTO) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("POURQUOI CETTE CONFIANCE")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.5)
                .foregroundStyle(DS.Color.inkMute)
            VStack(alignment: .leading, spacing: 4) {
                bulletPoint("\(cluster.reportCount) personnes ont signalé indépendamment")
                bulletPoint("Score de confiance moyen: \(Int(cluster.aggregateTrust))/100")
                if cluster.signalements.contains(where: { $0.source == "user" }) {
                    bulletPoint("Inclut au moins 1 utilisateur authentifié")
                }
                if let firstReportedAt = cluster.firstReportedAt {
                    let mins = max(1, Int(Date().timeIntervalSince(firstReportedAt) / 60))
                    bulletPoint("Première alerte il y a \(mins) min")
                }
                if cluster.stillBlockedConfirmationCount > 0 {
                    bulletPoint("\(cluster.stillBlockedConfirmationCount) confirmation\(cluster.stillBlockedConfirmationCount > 1 ? "s" : "") « toujours bloqué »")
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
                .foregroundStyle(Color(hex: "#10B981"))
                .padding(.top, 2)
            Text(text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func confidenceBadge(_ confidence: ClusterConfidence) -> some View {
        let color: Color
        switch confidence {
        case .high: color = Color(hex: "#E94E1B")
        case .medium: color = Color(hex: "#F59E0B")
        case .low: color = Color(hex: "#9CA3AF")
        }
        return Text("Confiance: \(confidence.displayLabel.lowercased())")
            .font(DS.Font.monoSmall.weight(.bold))
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
            VStack(spacing: 12) {
                ProgressView()
                Text("Chargement…")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
            }
            .frame(maxWidth: .infinity, minHeight: 200)
        } else if let errorMessage {
            VStack(spacing: 12) {
                Image(systemName: "exclamationmark.triangle")
                    .font(.system(size: 28, weight: .semibold))
                    .foregroundStyle(Color(hex: "#E94E1B"))
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
                    ForEach(detail.signalements) { report in
                        reportRow(report)
                    }

                    if let expiresAt = detail.expiresAt {
                        HStack(spacing: 6) {
                            Image(systemName: "clock")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                            Text(expiryText(expiresAt: expiresAt))
                                .font(DS.Font.monoSmall.weight(.bold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        .padding(.top, 8)
                    }

                    if detail.stillBlockedConfirmationCount > 0 {
                        Text("\(detail.stillBlockedConfirmationCount) personne\(detail.stillBlockedConfirmationCount > 1 ? "s ont" : " a") confirmé « toujours bloqué »")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    if detail.resolveConfirmationCount > 0 {
                        Text("Résolu confirmé par \(detail.resolveConfirmationCount)/3 personnes")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
                .padding(18)
            }
        }
    }

    private func reportRow(_ report: ClusterReportDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: report.source == "user" ? "person.crop.circle.fill" : "person.crop.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 2) {
                Text("« \(report.description) »")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(3)
                if let timestamp = report.timestamp {
                    Text(timestamp, style: .relative)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            Spacer()
        }
        .padding(10)
        .background(DS.Color.paper2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private var actionsView: some View {
        HStack(spacing: 10) {
            Button {
                Task { await voteStillBlocked() }
            } label: {
                HStack(spacing: 6) {
                    if isConfirmingBlocked {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: hasVotedBlocked ? "checkmark.circle.fill" : "exclamationmark.bubble")
                    }
                    Text("Toujours bloqué")
                        .font(DS.Font.bodyBold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasVotedBlocked ? Color(hex: "#F59E0B").opacity(0.15) : Color(hex: "#F59E0B"))
                .foregroundStyle(hasVotedBlocked ? Color(hex: "#F59E0B") : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(hasVotedBlocked || isConfirmingBlocked || (detail?.resolved ?? false))

            Button {
                Task { await voteResolved() }
            } label: {
                HStack(spacing: 6) {
                    if isConfirmingResolved {
                        ProgressView()
                            .scaleEffect(0.7)
                    } else {
                        Image(systemName: hasVotedResolved ? "checkmark.circle.fill" : "checkmark.circle")
                    }
                    Text("C'est résolu")
                        .font(DS.Font.bodyBold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(hasVotedResolved ? Color(hex: "#10B981").opacity(0.15) : Color(hex: "#10B981"))
                .foregroundStyle(hasVotedResolved ? Color(hex: "#10B981") : .white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(hasVotedResolved || isConfirmingResolved || (detail?.resolved ?? false))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private func expiryText(expiresAt: Date) -> String {
        let minutes = max(0, Int(expiresAt.timeIntervalSinceNow / 60))
        if minutes <= 0 { return "Expire bientôt" }
        if minutes < 60 { return "Expire dans \(minutes) min" }
        let hours = minutes / 60
        let mins = minutes % 60
        return "Expire dans \(hours)h\(mins > 0 ? " \(mins)min" : "")"
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
            await MainActor.run {
                self.errorMessage = "Impossible de charger les détails."
                self.isLoading = false
            }
        }
    }

    private func voteStillBlocked() async {
        isConfirmingBlocked = true
        do {
            _ = try await ClusterService.confirmStillBlocked(clusterIndex)
            await MainActor.run {
                hasVotedBlocked = true
                showToast("Confirmation enregistrée")
            }
            await loadDetail()
        } catch {
            await MainActor.run { showToast("Erreur, réessayez") }
        }
        await MainActor.run { isConfirmingBlocked = false }
    }

    private func voteResolved() async {
        isConfirmingResolved = true
        do {
            let response = try await ClusterService.confirmResolved(clusterIndex)
            await MainActor.run {
                hasVotedResolved = true
                showToast(response.message)
            }
            await loadDetail()
        } catch {
            await MainActor.run { showToast("Erreur, réessayez") }
        }
        await MainActor.run { isConfirmingResolved = false }
    }

    private func showToast(_ message: String) {
        withAnimation { toastMessage = message }
        Task {
            try? await Task.sleep(nanoseconds: 2_500_000_000)
            await MainActor.run {
                withAnimation { toastMessage = nil }
            }
        }
    }
}
