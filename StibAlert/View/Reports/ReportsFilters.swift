import SwiftUI

struct ReportsFilterDock: View {
    let showsReportFilters: Bool
    let selectedSegment: ReportSegment
    let selectedMode: ReportTransportMode
    let selectedLine: String
    let selectedSort: ReportSortMode
    let lineFilters: [String]
    let segmentCounts: [ReportSegment: Int]
    let helperText: String
    let updatedText: String?
    let onSelectSegment: (ReportSegment) -> Void
    let onSelectMode: (ReportTransportMode) -> Void
    let onSelectLine: (String) -> Void
    let onSelectSort: (ReportSortMode) -> Void

    private var totalCount: Int { segmentCounts[.all] ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("SOMMAIRE")
                    .font(.system(size: 11, weight: .bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.ink)

                Spacer()

                Text("\(String(format: "%02d", totalCount)) DÉPÊCHES")
                    .font(DS.Font.monoSmall.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, 14)
            .padding(.bottom, 8)

            Rectangle()
                .fill(DS.Color.ink)
                .frame(height: 2)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, 10)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(visibleSegments, id: \.self) { segment in
                        EditorialSegmentChip(
                            label: segment.label,
                            count: segmentCounts[segment] ?? 0,
                            active: selectedSegment == segment,
                            action: { onSelectSegment(segment) }
                        )
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
            .padding(.bottom, 8)

            HStack(spacing: 8) {
                filterMenuButton(
                    icon: "arrow.up.arrow.down",
                    title: selectedSort.label
                ) {
                    ForEach(ReportSortMode.allCases) { mode in
                        Button(mode.label) { onSelectSort(mode) }
                    }
                }
                filterMenuButton(
                    icon: selectedMode.iconSystemName ?? "square.grid.2x2",
                    title: selectedMode.label
                ) {
                    ForEach(ReportTransportMode.allCases) { mode in
                        Button(mode.label) { onSelectMode(mode) }
                    }
                }
                lineFilterMenuButton
                Spacer(minLength: 0)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, 10)

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(helperText)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if let updatedText {
                    Text(updatedText)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.bottom, 12)
        }
        .background(
            DS.Color.paper
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.10))
                        .frame(height: 1)
                }
        )
        .compositingGroup()
        .clipped()
        .zLayer(.modalDropdown)
    }

    private var visibleSegments: [ReportSegment] {
        showsReportFilters
            ? [.all, .official, .community, .events]
            : [.events]
    }

    private func filterMenuButton<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                Text(title)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .tracking(0.6)
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }

    private var lineFilterMenuButton: some View {
        Menu {
            ForEach(lineFilters, id: \.self) { line in
                Button {
                    onSelectLine(line)
                } label: {
                    if line == "Tout" {
                        Label("Toutes lignes", systemImage: "line.3.horizontal.decrease")
                    } else {
                        HStack(spacing: 10) {
                            LineBadge(line: line, size: .sm)
                            Text("Ligne \(line)")
                        }
                    }
                }
            }
        } label: {
            HStack(spacing: 6) {
                if selectedLine == "Tout" {
                    Image(systemName: "line.3.horizontal.decrease")
                        .font(.system(size: 10, weight: .bold))
                    Text("Toutes lignes")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .lineLimit(1)
                } else {
                    LineBadge(line: selectedLine, size: .sm)
                    Text("L \(selectedLine)")
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .tracking(0.6)
                        .lineLimit(1)
                }
                Image(systemName: "chevron.down")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
    }
}

private struct EditorialSegmentChip: View {
    let label: String
    let count: Int
    let active: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 12, weight: .semibold))
                Text("\(count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? DS.Color.paper.opacity(0.7) : DS.Color.inkMute)
            }
            .padding(.horizontal, 12)
            .frame(height: 30)
            .foregroundStyle(active ? DS.Color.paper : DS.Color.ink)
            .background(active ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
