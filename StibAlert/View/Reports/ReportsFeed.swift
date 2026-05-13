import SwiftUI

struct ReportsFeedView: View {
    let isLoading: Bool
    let hasLoaded: Bool
    let feedItems: [EditorialFeedItem]
    let shouldGroupFeedByLine: Bool
    let groupedFeedItems: [EditorialLineGroup]
    let favoriteLines: Set<String>
    @Binding var expandedFeedLineIds: Set<String>
    let votingReportIds: Set<String>
    let locallyUpvotedReportIds: Set<String>
    let notificationLineInFlight: Set<String>
    let onOpenItem: (EditorialFeedItem) -> Void
    let onUpvote: (SignalementDTO) -> Void
    let onNotifyLine: (String) -> Void

    var body: some View {
        if isLoading && !hasLoaded {
            ProgressView()
                .tint(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
        } else if feedItems.isEmpty {
            Text("Rien à signaler dans cette catégorie.")
                .font(DS.Font.body)
                .italic()
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            LazyVStack(spacing: 10) {
                if shouldGroupFeedByLine {
                    ForEach(groupedFeedItems) { group in
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
                } else {
                    ForEach(feedItems) { item in
                        feedCard(for: item)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, 4)
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
