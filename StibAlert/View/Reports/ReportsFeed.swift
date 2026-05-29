import SwiftUI

struct ReportsFeedView: View {
    let isLoading: Bool
    let hasLoaded: Bool
    let feedItems: [EditorialFeedItem]
    let shouldGroupFeedByLine: Bool
    /// Per-mode feed sections (Métro / Tram / Bus). Built from
    /// `groupedFeedItems` upstream so a long mixed list becomes three
    /// scannable mode bundles.
    let feedSections: [EditorialModeSection]
    let favoriteLines: Set<String>
    @Binding var expandedFeedLineIds: Set<String>
    let votingReportIds: Set<String>
    let locallyUpvotedReportIds: Set<String>
    let notificationLineInFlight: Set<String>
    let onOpenItem: (EditorialFeedItem) -> Void
    let onUpvote: (SignalementDTO) -> Void
    let onNotifyLine: (String) -> Void
    /// Closure triggered when the user has scrolled near the end of the
    /// list. Used to fetch the next page in scroll-to-load (infinite feed).
    /// Default no-op pour rester compat sans casser les call-sites
    /// existants qui ne passent rien.
    var onReachEnd: () -> Void = {}
    /// True quand la fetch "page suivante" est en cours. Affiche un loader
    /// en bas de la liste.
    var isLoadingMore: Bool = false
    /// True quand le backend signale qu'on a tout chargé : on remplace le
    /// loader par un small notice "Fin de la liste".
    var hasReachedEnd: Bool = false

    var body: some View {
        if isLoading && !hasLoaded {
            SkeletonList(count: 5, style: .card)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.top, 12)
        } else if feedItems.isEmpty {
            EmptyStateView(
                iconSystemName: "checkmark.seal.fill",
                title: "Tout est calme",
                body: "Rien à signaler dans cette catégorie pour le moment. On te prévient dès qu'il y a du nouveau.",
                iconTint: DS.Color.statusOK,
                iconWeight: .regular,
                iconSize: 44
            )
            .padding(.top, 32)
        } else {
            LazyVStack(spacing: 18) {
                if shouldGroupFeedByLine {
                    ForEach(feedSections) { section in
                        modeSection(section)
                    }
                } else {
                    ForEach(Array(feedItems.enumerated()), id: \.element.id) { idx, item in
                        feedCard(for: item)
                            .onAppear {
                                // Pagination infinite : dès que la dernière
                                // card (ou avant-dernière) apparaît, on
                                // déclenche le fetch de la page suivante.
                                if idx >= feedItems.count - 2 {
                                    onReachEnd()
                                }
                            }
                    }
                }

                // Footer : loader pendant la fetch suivante OU notice de fin.
                if !shouldGroupFeedByLine {
                    if isLoadingMore {
                        HStack(spacing: 8) {
                            ProgressView()
                                .scaleEffect(0.85)
                            Text("Chargement…")
                                .font(DS.Font.monoSmall.weight(.bold))
                                .tracking(1.2)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 14)
                    } else if hasReachedEnd && feedItems.count > 6 {
                        Text("FIN DU FEED")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(1.5)
                            .foregroundStyle(DS.Color.inkMute.opacity(0.6))
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 14)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, 4)
        }
    }

    /// One Métro / Tram / Bus section: header eyebrow + every line-group
    /// belonging to that mode rendered in sequence.
    private func modeSection(_ section: EditorialModeSection) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionHeader(section.mode, count: section.groups.count)
            VStack(spacing: 10) {
                ForEach(section.groups) { group in
                    EditorialLineGroupCard(
                        group: group,
                        isExpanded: expandedFeedLineIds.contains(group.id),
                        isFavoriteLine: favoriteLines.contains(group.line),
                        onToggle: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                if expandedFeedLineIds.contains(group.id) {
                                    expandedFeedLineIds.remove(group.id)
                                } else {
                                    expandedFeedLineIds.insert(group.id)
                                }
                            }
                        },
                        nestedContent: {
                            VStack(spacing: 8) {
                                ForEach(group.items) { item in
                                    feedCard(for: item)
                                }
                            }
                        }
                    )
                }
            }
        }
    }

    private func sectionHeader(_ mode: TransitLineMode, count: Int) -> some View {
        HStack(spacing: 10) {
            Image(systemName: mode.sfSymbol)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 30, height: 30)
                .background(DS.Color.paper2)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
            Text(mode.label.uppercased())
                .font(DS.Font.eyebrow)
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)
            Text("·")
                .font(DS.Font.eyebrow)
                .foregroundStyle(DS.Color.inkMute)
            Text("\(count) ligne\(count > 1 ? "s" : "")")
                .font(DS.Font.eyebrow)
                .tracking(1.4)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
        }
    }

    private func feedCard(for item: EditorialFeedItem) -> some View {
        EditorialFeedCard(
            item: item,
            isFavoriteLine: item.lines.contains(where: { favoriteLines.contains($0) }),
            isVoting: item.report.map { votingReportIds.contains($0.id) } ?? false,
            hasUpvoted: item.report.map { locallyUpvotedReportIds.contains($0.id) } ?? false,
            isNotificationLoading: item.lines.contains(where: { notificationLineInFlight.contains($0) }),
            isNotificationEnabled: item.lines.contains(where: { favoriteLines.contains($0) }),
            onUpvote: onUpvote,
            onNotifyLine: onNotifyLine
        )
        .contentShape(Rectangle())
        .onTapGesture {
            onOpenItem(item)
        }
    }
}
