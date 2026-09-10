import SwiftUI

struct RecentReportItem: Identifiable {
    let id: String
    let line: String
    let title: String
    let time: String
    let details: String
    let signalementId: String?
    let status: String?
    let source: String?
    let confidence: String?
    let community: SignalementCommunityDTO?
}


struct RecentReportCard: View {
    let item: RecentReportItem
    @State private var community: SignalementCommunityDTO?
    @State private var status: String?
    @State private var isSubmitting = false
    @State private var showConfidenceExplanation = false
    @State private var actionError: String? = nil

    private var effectiveCommunity: SignalementCommunityDTO? { community ?? item.community }
    private var effectiveStatus: String? { status ?? item.status }

    private var statusColor: Color {
        switch effectiveStatus {
        case "resolved":
            return AppTheme.Palette.success
        case "active":
            return AppTheme.Palette.warning
        default:
            return AppTheme.Palette.info
        }
    }

    private var confidenceText: String? { item.confidence }
    private var isStale: Bool { (effectiveCommunity?.freshnessMinutes ?? 0) >= 120 }
    private var freshnessSummary: String { item.time }
    private var confirmationsSummary: String? {
        guard let community = effectiveCommunity else { return nil }
        let confirmations = community.confirmations ?? 0
        guard confirmations > 0, let freshness = community.freshnessMinutes else { return nil }
        let window = freshness < 60
            ? AppLocalizer.format("window.minutes", defaultValue: "%lld min", freshness)
            : AppLocalizer.format("window.hours", defaultValue: "%lld h", freshness / 60)
        return AppLocalizer.format("confirmations.summary",
                                   defaultValue: "Confirmé %lld× en %@", confirmations, window)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.line)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .frame(width: 30, height: 28)
                    .background(AppTheme.Palette.brandStrong)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                (
                    Text(DisruptionTranslator.shared.display(item.title) + " ")
                        .font(AppTheme.Fonts.title3)
                    + Text(item.time)
                        .font(AppTheme.Fonts.captionStrong)
                )
                .foregroundStyle(AppTheme.Palette.textOnBrand)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
            }

            Text(item.details)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                communityPill(freshnessSummary, background: AppTheme.Palette.screen)
                if let confirmationsSummary {
                    communityPill(confirmationsSummary, background: AppTheme.Palette.screen)
                }
            }

            if let community = effectiveCommunity {
                HStack(spacing: 10) {
                    communityPill("\(community.confirmations ?? 0) confirm.", background: AppTheme.Palette.screen)
                    communityPill(AppLocalizer.format("community.n_blocked", defaultValue: "%lld bloqué", community.stillBlocked ?? 0), background: AppTheme.Palette.warning, textColor: AppTheme.Palette.textOnBrand)
                    communityPill(AppLocalizer.format("community.n_resolved", defaultValue: "%lld résolu", community.resolved ?? 0), background: AppTheme.Palette.success, textColor: AppTheme.Palette.textOnBrand)

                    if let confidenceText {
                        Button {
                            showConfidenceExplanation = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(confidenceText)
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(AppTheme.Fonts.captionStrong)
                            .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                communityPill(
                    item.source ?? "Communauté",
                    background: (item.source?.contains("STIB") == true) ? Color(hex: "#0055A4") : AppTheme.Palette.brandStrong,
                    textColor: AppTheme.Palette.textOnBrand
                )
                if isStale {
                    communityPill(AppLocalizer.string("community.more_recent", defaultValue: "Plus récent ?"), background: AppTheme.Palette.surfaceMuted, textColor: AppTheme.Palette.textPrimary)
                }
            }

            if let signalementId = item.signalementId {
                HStack(spacing: 8) {
                    actionButton(AppLocalizer.string("community.action.confirm"), fill: AppTheme.Palette.screen) {
                        await applyCommunityAction(.confirm, signalementId: signalementId)
                    }
                    actionButton(AppLocalizer.string("community.action.still_blocked"), fill: AppTheme.Palette.warning) {
                        await applyCommunityAction(.stillBlocked, signalementId: signalementId)
                    }
                    actionButton(AppLocalizer.string("community.action.resolved_sentence"), fill: AppTheme.Palette.success, textColor: AppTheme.Palette.textOnBrand) {
                        await applyCommunityAction(.resolved, signalementId: signalementId)
                    }
                }
                .opacity(isSubmitting ? 0.6 : 1)
            }
            if let actionError {
                Text(actionError)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.alert)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(AppTheme.Palette.brand)
        .opacity(isStale ? 0.7 : 1)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .alert("Pourquoi cette confiance ?", isPresented: $showConfidenceExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(confidenceExplanation)
        }
        .task {
            community = item.community
            status = item.status
        }
    }

    private func communityPill(_ text: String, background: Color, textColor: Color? = nil) -> some View {
        Text(text)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(textColor ?? AppTheme.Palette.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(background)
            .clipShape(Capsule())
    }

    /// Mêmes clés que `SignalementDTO.confidenceExplanation` : une seule traduction
    /// pour un même texte, quel que soit l'écran qui l'affiche.
    private var confidenceExplanation: String {
        switch item.confidence?.lowercased() {   // "haute"/"moyenne" = valeurs backend
        case let value? where value.contains("haute"):
            return AppLocalizer.string("confidence.explain.high",
                                       defaultValue: "Basée sur une position GPS très proche de l'arrêt signalé.")
        case let value? where value.contains("moyenne"):
            return AppLocalizer.string("confidence.explain.medium",
                                       defaultValue: "Basée sur une position GPS cohérente, mais moins précise autour de l'arrêt.")
        case let value? where value.contains("basse"):
            return AppLocalizer.string("confidence.explain.low",
                                       defaultValue: "Basée sur une position GPS absente ou trop éloignée de l'arrêt signalé.")
        default:
            return AppLocalizer.string("confidence.explain.default",
                                       defaultValue: "Basée sur la proximité GPS observée au moment du signalement.")
        }
    }

    private func actionButton(
        _ title: String,
        fill: Color,
        textColor: Color = AppTheme.Palette.textPrimary,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(AppTheme.Fonts.captionStrong)
                .foregroundStyle(textColor)
                .frame(maxWidth: .infinity)
                .frame(height: 30)
                .background(fill)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }

    @MainActor
    private func applyCommunityAction(_ action: CommunityAction, signalementId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response: SignalementCommunityActionResponse
            switch action {
            case .confirm:
                response = try await SignalementService.confirmer(signalementId: signalementId)
            case .stillBlocked:
                response = try await SignalementService.toujoursBloque(signalementId: signalementId)
            case .resolved:
                response = try await SignalementService.resoudre(signalementId: signalementId)
            }
            community = response.community ?? community
            status = response.status ?? status
            actionError = nil
        } catch {
            actionError = AppLocalizer.string("error.action_not_sent", defaultValue: "Action non envoyée. Réessaie.")
        }
    }

    private enum CommunityAction {
        case confirm
        case stillBlocked
        case resolved
    }
}
