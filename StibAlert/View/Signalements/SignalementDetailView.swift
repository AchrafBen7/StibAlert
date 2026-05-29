import SwiftUI
import UIKit

private enum ReportTimelineSource {
    case official
    case community
    case system
}

private struct ReportTimelineItem: Identifiable {
    let id = UUID()
    let time: String
    let label: String
    let body: String?
    let source: ReportTimelineSource
}

private enum ReportVoteState {
    case none
    case up
    case down
}

struct SignalementDetailView: View {
    let signalement: SignalementDTO
    var onDismiss: () -> Void
    var onOpenOnMap: (() -> Void)? = nil

    @EnvironmentObject private var nav: AppNavigation

    @State private var latest: SignalementDTO
    @State private var voteState: ReportVoteState = .none
    @State private var isVoting = false
    @State private var isFollowing = false
    @State private var isSubmitting = false
    @State private var feedback: String? = nil
    @State private var reportedFake = false

    init(
        signalement: SignalementDTO,
        onDismiss: @escaping () -> Void,
        onOpenOnMap: (() -> Void)? = nil
    ) {
        self.signalement = signalement
        self.onDismiss = onDismiss
        self.onOpenOnMap = onOpenOnMap
        _latest = State(initialValue: signalement)
    }

    private var isOfficial: Bool {
        let label = latest.sourceLabel.lowercased()
        return label.contains("stib") || label.contains("officiel")
    }

    private var sourceEyebrow: String {
        isOfficial ? "Officiel STIB" : "Communauté"
    }

    private var sourceAccent: Color {
        isOfficial ? DS.Color.statusMajor : DS.Color.community
    }

    private var arretName: String {
        if case .populated(let arret) = latest.arretId {
            return arret.nom
        }
        return "Réseau STIB"
    }

    private var score: Int {
        let base = (latest.votesPositifs ?? 0) - (latest.votesNegatifs ?? 0)
        switch voteState {
        case .none: return base
        case .up: return base + 1
        case .down: return base - 1
        }
    }

    private var confirmations: Int {
        latest.community?.confirmations ?? 0
    }

    private var stillBlocked: Int {
        latest.community?.stillBlocked ?? 0
    }

    private var resolvedCount: Int {
        latest.community?.resolved ?? 0
    }

    private var timelineItems: [ReportTimelineItem] {
        var items: [ReportTimelineItem] = [
            ReportTimelineItem(
                time: latest.freshnessLabel,
                label: isOfficial ? "Signalé par STIB" : "Premier signalement",
                body: latest.description,
                source: isOfficial ? .official : .community
            )
        ]

        if confirmations > 0 {
            items.append(
                ReportTimelineItem(
                    time: freshnessStepLabel(offset: 12),
                    label: "\(confirmations) voyageur\(confirmations > 1 ? "s" : "") confirment",
                    body: nil,
                    source: .community
                )
            )
        }

        if stillBlocked > 0 {
            items.append(
                ReportTimelineItem(
                    time: freshnessStepLabel(offset: 6),
                    label: "Toujours bloqué sur le terrain",
                    body: "\(stillBlocked) retour\(stillBlocked > 1 ? "s" : "") signalent que l'incident continue.",
                    source: .community
                )
            )
        } else if resolvedCount > 0 {
            items.append(
                ReportTimelineItem(
                    time: freshnessStepLabel(offset: 6),
                    label: "Reprise partielle signalée",
                    body: "\(resolvedCount) retour\(resolvedCount > 1 ? "s" : "") indiquent une amélioration.",
                    source: .system
                )
            )
        } else if isOfficial {
            items.append(
                ReportTimelineItem(
                    time: freshnessStepLabel(offset: 8),
                    label: "Mise à jour officielle",
                    body: "Le flux STIB maintient l'incident comme actif.",
                    source: .official
                )
            )
        }

        items.append(
            ReportTimelineItem(
                time: "à l'instant",
                label: "Mise à jour temps réel",
                body: nil,
                source: .system
            )
        )

        return items
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    topBar
                    headerBlock
                    DS.Rule(thick: true)
                        .padding(.bottom, 16)

                    Text(latest.description)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.ink)
                        .lineSpacing(4)

                    voteCard
                    timelineSection
                    impactedLineSection
                    actionsSection

                    if let feedback {
                        Text(feedback)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(sourceAccent)
                            .padding(.top, 16)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 100)
            }
            .background(DS.Color.paper.ignoresSafeArea())
            .modifier(PaperGrainBackground())
            .toolbar(.hidden, for: .navigationBar)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            ShareLink(item: SignalementShare.message(for: latest)) {
                Image(systemName: "square.and.arrow.up")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            if let onOpenOnMap {
                Button(action: onOpenOnMap) {
                    Image(systemName: "map")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 36, height: 36)
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md)
                                .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.bottom, 14)
    }

    private var headerBlock: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                if isOfficial {
                    OfficialSourceBadge()
                } else {
                    CommunitySourceBadge()
                }

                // Community polish — pastille colorée selon le decay tier
                // (fresh: vert / recent: orange / stale: gris). Permet à
                // l'utilisateur de jauger la fiabilité d'un coup d'œil sans
                // lire le texte complet.
                HStack(spacing: 5) {
                    Circle()
                        .fill(freshnessTierColor(latest.freshnessTier))
                        .frame(width: 6, height: 6)
                    Text(latest.freshnessLabel.uppercased())
                        .font(DS.Font.monoSmall)
                        .tracking(0.8)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.bottom, 8)

            Text("Ligne \(latest.ligne) · \(latest.displayTypeProbleme.lowercased())")
                .font(DS.Font.displayH2)
                .foregroundStyle(DS.Color.ink)
                .padding(.bottom, 8)

            HStack(spacing: 12) {
                LineBadge(line: latest.ligne, size: .lg)

                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 10, weight: .semibold))
                    Text(arretName)
                        .font(DS.Font.monoSmall)
                }
                .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.bottom, 16)
    }

    private var voteCard: some View {
        VStack(spacing: 0) {
            HStack {
                Text("CONFIRMATIONS TERRAIN")
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("\(confirmations) voyageurs")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.ink)
            }
            .padding(.bottom, 10)

            HStack(spacing: 8) {
                voteButton(
                    label: "Je confirme",
                    icon: "arrow.up",
                    active: voteState == .up,
                    activeBg: DS.Color.statusOK,
                    activeFg: DS.Color.paper
                ) {
                    triggerVote(.up, apiValue: "up")
                }

                voteButton(
                    label: "Plus d'actu",
                    icon: "arrow.down",
                    active: voteState == .down,
                    activeBg: DS.Color.ink,
                    activeFg: DS.Color.paper
                ) {
                    triggerVote(.down, apiValue: "down")
                }
            }

            HStack(spacing: 4) {
                Text("Score ·")
                    .foregroundStyle(DS.Color.inkMute)
                Text("\(score)")
                    .foregroundStyle(DS.Color.ink)
                    .fontWeight(.bold)
            }
            .font(DS.Font.monoSmall)
            .padding(.top, 8)
            .frame(maxWidth: .infinity)
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .padding(.top, 16)
    }

    private func voteButton(
        label: String,
        icon: String,
        active: Bool,
        activeBg: Color,
        activeFg: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isVoting && active {
                    ProgressView()
                        .tint(activeFg)
                        .scaleEffect(0.8)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 14, weight: .bold))
                    Text(label)
                        .font(.system(size: 12.5, weight: .semibold))
                }
            }
            .frame(maxWidth: .infinity, minHeight: 40)
            .foregroundStyle(active ? activeFg : DS.Color.ink)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(active ? activeBg : DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(active ? activeBg : DS.Color.ink.opacity(0.25), lineWidth: 1.5)
                    )
            )
        }
        .buttonStyle(PressableScaleStyle())
        .disabled(isVoting)
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Image(systemName: "clock")
                    .font(.system(size: 10, weight: .bold))
                Text("TIMELINE")
                    .font(DS.Font.sectionTitle)
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.bottom, 12)

            DS.Rule(thick: true)
                .padding(.bottom, 12)

            VStack(alignment: .leading, spacing: 0) {
                ForEach(Array(timelineItems.enumerated()), id: \.element.id) { index, item in
                    SignalementTimelineRow(item: item, isLast: index == timelineItems.count - 1)
                }
            }
        }
        .padding(.top, 24)
    }

    private var impactedLineSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("LIGNE IMPACTÉE")
                .font(DS.Font.sectionTitle)
                .foregroundStyle(DS.Color.ink)
                .padding(.bottom, 8)

            DS.Rule()
                .padding(.bottom, 8)

            Button(action: openLine) {
                HStack(spacing: 12) {
                    LineBadge(line: latest.ligne, size: .lg)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Voir la ligne complète")
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                        Text("TIMELINE TEMPS RÉEL")
                            .font(DS.Font.monoSmall)
                            .tracking(0.6)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    Spacer()
                    Text("→")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.inkMute)
                }
                .padding(.vertical, 12)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 16)
    }

    private var actionsSection: some View {
        VStack(spacing: 10) {
            HStack(spacing: 8) {
                Button(action: { isFollowing.toggle() }) {
                    HStack(spacing: 6) {
                        Image(systemName: "bell")
                            .font(.system(size: 14, weight: .semibold))
                        Text(isFollowing ? "Suivi" : "Suivre")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(isFollowing ? DS.Color.paper : DS.Color.ink)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(isFollowing ? DS.Color.ink : DS.Color.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .stroke(isFollowing ? DS.Color.ink : DS.Color.ink.opacity(0.25), lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(PressableScaleStyle())

                Button(action: openNewReport) {
                    HStack(spacing: 6) {
                        Image(systemName: "bubble.left")
                            .font(.system(size: 14, weight: .semibold))
                        Text("Compléter")
                            .font(.system(size: 13, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundStyle(DS.Color.paper)
                    .background(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .fill(DS.Color.primary)
                            .overlay(
                                RoundedRectangle(cornerRadius: DS.Radius.md)
                                    .stroke(DS.Color.ink, lineWidth: 1.5)
                            )
                    )
                }
                .buttonStyle(PressableScaleStyle())
            }

            Button(action: triggerReportFake) {
                HStack(spacing: 5) {
                    Image(systemName: reportedFake ? "flag.fill" : "flag")
                        .font(.system(size: 11, weight: .semibold))
                    Text(reportedFake ? "Signalé comme faux" : "Signaler comme faux / abus")
                        .font(DS.Font.bodySmall)
                }
                .foregroundStyle(reportedFake ? DS.Color.inkMute : DS.Color.statusCritical.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .center)
            }
            .buttonStyle(.plain)
            .disabled(reportedFake || isSubmitting)
        }
        .padding(.top, 24)
    }

    private func triggerVote(_ state: ReportVoteState, apiValue: String) {
        guard !isVoting else { return }
        let next = voteState == state ? ReportVoteState.none : state
        let previous = voteState
        voteState = next
        isVoting = true
        feedback = nil
        // Community polish — haptic medium au tap pour confirmer
        // l'enregistrement avant le round-trip réseau (l'utilisateur sait
        // immédiatement que son tap est passé, sans attendre le retour
        // serveur qui peut prendre 200-800 ms).
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()

        Task {
            do {
                try await SignalementService.voter(signalementId: latest.id, vote: apiValue)
                // Success notification haptic + texte de confirmation
                // discret qui disparaît après 2.5 s (toast inline géré par
                // le `feedback` state + auto-clear).
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                if next != .none {
                    feedback = next == .up
                        ? "Confirmation enregistrée — merci !"
                        : "Vote enregistré"
                    // Auto-clear discret après 2.5 s, sans bloquer le user.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 2_500_000_000)
                        if feedback?.contains("enregistré") == true {
                            feedback = nil
                        }
                    }
                }
            } catch {
                voteState = previous
                feedback = (error as? APIError)?.errorDescription ?? error.localizedDescription
                UINotificationFeedbackGenerator().notificationOccurred(.error)
            }
            isVoting = false
        }
    }

    private func freshnessTierColor(_ tier: SignalementDTO.FreshnessTier) -> Color {
        switch tier {
        case .fresh:   return DS.Color.statusOK
        case .recent:  return DS.Color.statusMinor
        case .stale:   return DS.Color.inkMute
        case .unknown: return DS.Color.ink.opacity(0.3)
        }
    }

    private func openLine() {
        nav.pendingLineFocus = latest.ligne
        nav.currentPage = .signalements
        onDismiss()
    }

    private func openNewReport() {
        nav.currentPage = .home
        nav.pendingLineFocus = latest.ligne
        onDismiss()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
            nav.showReportSheet = true
        }
    }

    private func triggerReportFake() {
        guard !reportedFake && !isSubmitting else { return }
        isSubmitting = true
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task {
            defer { isSubmitting = false }
            do {
                try await SignalementService.signalerFaux(signalementId: latest.id)
                reportedFake = true
            } catch {
                feedback = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
        }
    }

    private func freshnessStepLabel(offset: Int) -> String {
        guard let minutes = latest.effectiveFreshnessMinutes else { return "il y a quelques min" }
        let shifted = max(1, minutes - offset)
        if shifted < 60 { return "il y a \(shifted) min" }
        return "il y a \(shifted / 60) h"
    }
}

private struct SignalementTimelineRow: View {
    let item: ReportTimelineItem
    let isLast: Bool

    private var dotColor: Color {
        switch item.source {
        case .official:
            return DS.Color.statusMajor
        case .community:
            return DS.Color.community
        case .system:
            return DS.Color.paper
        }
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.3))
                        .frame(width: 2)
                        .padding(.top, 18)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                Circle()
                    .fill(dotColor)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(DS.Color.ink, lineWidth: 2))
                    .padding(.top, 6)
            }
            .frame(width: 20)
            .padding(.trailing, 8)

            VStack(alignment: .leading, spacing: 2) {
                Text(item.time.uppercased())
                    .font(DS.Font.monoSmall)
                    .tracking(0.6)
                    .foregroundStyle(DS.Color.inkMute)
                Text(item.label)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                if let body = item.body {
                    Text(body)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkSoft)
                        .lineSpacing(2)
                        .padding(.top, 2)
                }
            }
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
    }
}

private struct OfficialSourceBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "shield.fill")
                .font(.system(size: 9, weight: .bold))
            Text("OFFICIEL")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundStyle(DS.Color.paper)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(DS.Color.statusMajor)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}

private struct CommunitySourceBadge: View {
    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "person.2.fill")
                .font(.system(size: 9, weight: .bold))
            Text("COMMUNAUTÉ")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(0.8)
        }
        .foregroundStyle(DS.Color.paper)
        .padding(.horizontal, 8)
        .padding(.vertical, 2)
        .background(DS.Color.community)
        .clipShape(RoundedRectangle(cornerRadius: 2))
    }
}
