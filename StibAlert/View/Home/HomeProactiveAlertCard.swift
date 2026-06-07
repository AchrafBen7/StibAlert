import SwiftUI

struct HomeProactiveAlertCard: View {
    let cluster: ClusterDTO
    let onClose: () -> Void
    let onOpenDetails: () -> Void
    let onStillBlocked: () async -> Void
    let onResolved: () async -> Void

    @State private var isSubmittingBlocked = false
    @State private var isSubmittingResolved = false
    // I2 — auto-collapse 3 s sans interaction + swipe-down to dismiss.
    @State private var isCollapsed = false
    @State private var dragOffset: CGFloat = 0
    @State private var collapseTask: Task<Void, Never>?
    // Nom lisible de l'arrêt concerné (résolu depuis le catalogue) — pour
    // qu'on comprenne À QUEL arrêt se situe le problème, pas juste la ligne.
    @State private var affectedStopName: String?

    private var accent: Color {
        cluster.isOfficial ? DS.Color.danger : SignalVisuals.communityColor(for: cluster)
    }

    private var sourceLabel: String {
        cluster.isOfficial
            ? AppLocalizer.string("alert.source.official", defaultValue: "Source officielle")
            : AppLocalizer.string("alert.source.community", defaultValue: "Communauté")
    }

    private var title: String {
        if cluster.isOfficial {
            return AppLocalizer.string("alert.title.official", defaultValue: "Perturbation sur ta ligne")
        }
        // A1 — titre piloté par le statut de confiance unifié.
        switch cluster.confidenceStatus {
        case "confirmed": return AppLocalizer.string("alert.title.confirmed", defaultValue: "Signalement confirmé")
        case "likely": return AppLocalizer.string("alert.title.likely", defaultValue: "Signalement probable")
        default:
            return cluster.reportCount >= 3
                ? AppLocalizer.string("alert.title.confirmed", defaultValue: "Signalement confirmé")
                : AppLocalizer.string("alert.title.nearby", defaultValue: "Alerte autour de toi")
        }
    }

    private var summary: String {
        // A6 — si l'IA a produit un résumé "wat/waarom/hoelang/wat nu", on
        // l'affiche tel quel (plus actionnable que "Ligne X · type").
        if let aiSummary = cluster.summary, !aiSummary.isEmpty {
            return aiSummary
        }
        var parts: [String] = []
        parts.append(AppLocalizer.format("alert.line_prefix", defaultValue: "Ligne %@", cluster.ligne))
        parts.append(SignalementDTO.localizedReportType(cluster.typeProbleme))
        if cluster.reportCount > 1 {
            parts.append(AppLocalizer.format("alert.reports_count", defaultValue: "%lld retours", cluster.reportCount))
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        Group {
            if isCollapsed {
                collapsedBody
            } else {
                expandedBody
            }
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(DS.Shadow.floating)
        .offset(y: dragOffset)
        .opacity(max(0, 1 - Double(dragOffset / 180)))
        .gesture(dismissDragGesture)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(summary)")
        .accessibilityHint("Glisse vers le bas pour fermer. Tape pour étendre ou réduire.")
        .onAppear { scheduleAutoCollapse() }
        .onDisappear { collapseTask?.cancel() }
        .task(id: cluster.arretId) {
            affectedStopName = await NearbyStopService.resolveStopName(arretId: cluster.arretId)
        }
    }

    private var expandedBody: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LineBadge(line: cluster.ligne, size: .lg)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: SignalVisuals.icon(forType: cluster.typeProbleme))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(accent)
                        Text(verbatim: sourceLabel.uppercased())
                            .font(DS.Font.monoSmall.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(DS.Color.inkMute)
                    }

                    Text(verbatim: title)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)

                    Text(verbatim: summary)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(3)

                    if let stop = affectedStopName, !stop.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.circle.fill")
                                .font(.system(size: 11, weight: .bold))
                                .foregroundStyle(accent)
                            Text(verbatim: AppLocalizer.format("alert.at_stop", defaultValue: "Arrêt : %@", stop))
                                .font(DS.Font.monoSmall.weight(.heavy))
                                .foregroundStyle(DS.Color.ink)
                                .lineLimit(1)
                        }
                        .padding(.top, 1)
                    }
                }

                Spacer(minLength: 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 34, height: 34)
                        .background(DS.Color.paper2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer l'alerte")
            }

            HStack(spacing: 8) {
                actionButton(
                    title: AppLocalizer.string("report.action.still_blocked", defaultValue: "Toujours bloqué"),
                    icon: "exclamationmark.circle.fill",
                    isLoading: isSubmittingBlocked,
                    foreground: DS.Color.ink,
                    background: DS.Color.warning.opacity(0.18),
                    border: DS.Color.warning.opacity(0.45)
                ) {
                    guard !isSubmittingBlocked else { return }
                    isSubmittingBlocked = true
                    await onStillBlocked()
                    isSubmittingBlocked = false
                }

                actionButton(
                    title: AppLocalizer.string("report.action.resolved", defaultValue: "Résolu"),
                    icon: "checkmark.circle.fill",
                    isLoading: isSubmittingResolved,
                    foreground: DS.Color.ink,
                    background: DS.Color.success.opacity(0.16),
                    border: DS.Color.success.opacity(0.42)
                ) {
                    guard !isSubmittingResolved else { return }
                    isSubmittingResolved = true
                    await onResolved()
                    isSubmittingResolved = false
                }
            }

            Button(action: onOpenDetails) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(verbatim: AppLocalizer.string("alert.see_on_map", defaultValue: "Voir l’alerte sur la carte"))
                        .font(DS.Font.monoSmall.weight(.heavy))
                        .tracking(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundStyle(DS.Color.primary)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { resetAutoCollapseTimer() }
    }

    private var collapsedBody: some View {
        Button {
            withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                isCollapsed = false
            }
            scheduleAutoCollapse()
        } label: {
            HStack(spacing: 10) {
                Circle()
                    .fill(accent)
                    .frame(width: 8, height: 8)
                Text(verbatim: "\(AppLocalizer.format("alert.line_prefix", defaultValue: "Ligne %@", cluster.ligne)) · \(SignalementDTO.localizedReportType(cluster.typeProbleme))")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .buttonStyle(.plain)
    }

    private var dismissDragGesture: some Gesture {
        DragGesture(minimumDistance: 10)
            .onChanged { value in
                resetAutoCollapseTimer()
                dragOffset = max(0, value.translation.height)
            }
            .onEnded { value in
                if value.translation.height > 80 || value.predictedEndTranslation.height > 140 {
                    withAnimation(.easeIn(duration: 0.18)) {
                        dragOffset = 240
                    }
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    onClose()
                } else {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.85)) {
                        dragOffset = 0
                    }
                }
            }
    }

    private func scheduleAutoCollapse() {
        collapseTask?.cancel()
        guard !isCollapsed else { return }
        collapseTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 3_000_000_000)
            guard !Task.isCancelled else { return }
            withAnimation(.spring(response: 0.34, dampingFraction: 0.85)) {
                isCollapsed = true
            }
        }
    }

    private func resetAutoCollapseTimer() {
        collapseTask?.cancel()
        scheduleAutoCollapse()
    }

    private func actionButton(
        title: String,
        icon: String,
        isLoading: Bool,
        foreground: Color,
        background: Color,
        border: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.74)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .black))
                }
                Text(verbatim: title)
                    .font(DS.Font.bodySmall.weight(.heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmittingBlocked || isSubmittingResolved)
    }
}
