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
        VStack(alignment: .leading, spacing: 8) {
            // Compact header: just the dépêches count aligned right. The old
            // "SOMMAIRE" eyebrow + 2-pixel rule has been dropped — the
            // 3-tab top control (En cours / Officiel / Events) already
            // signals the section.
            HStack {
                Spacer()
                Text("\(String(format: "%02d", totalCount)) dépêches")
                    .font(DS.Font.monoSmall.weight(.semibold))
                    .tracking(1.4)
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, 12)

            // Horizontal scroll of real line badges — tappable to filter by
            // line. Replaces the truncated "Plus r…" / "Tous mo…" / "Toutes…"
            // dropdown trio that used to crowd this row.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    allLinesChip
                    ForEach(visibleLineCodes, id: \.self) { code in
                        lineFilterChip(code)
                    }
                }
                .padding(.horizontal, DS.Spacing.xl)
            }
            .padding(.bottom, 8)
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

    /// Line codes the user can pick to filter the feed. We strip the "Tout"
    /// catch-all (its own chip rendered before) and any composite ":City"
    /// suffix so each badge shows the real STIB colour.
    private var visibleLineCodes: [String] {
        lineFilters
            .filter { $0 != "Tout" }
            .map { Self.shortCode(from: $0) }
            .filter { !$0.isEmpty }
            .reduce(into: [String]()) { acc, code in
                if !acc.contains(code) { acc.append(code) }
            }
    }

    private var allLinesChip: some View {
        let isActive = selectedLine == "Tout"
        return Button {
            onSelectLine("Tout")
        } label: {
            Text("TOUT")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(isActive ? DS.Color.paper : DS.Color.ink)
                .frame(width: 44, height: 34)
                .background(isActive ? DS.Color.ink : DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.Color.ink.opacity(isActive ? 0 : 0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func lineFilterChip(_ code: String) -> some View {
        let isActive = Self.shortCode(from: selectedLine) == code
        return Button {
            // Re-emit the original (possibly composite) line filter when
            // possible so the upstream filter logic still matches.
            let raw = lineFilters.first(where: { Self.shortCode(from: $0) == code }) ?? code
            onSelectLine(raw)
        } label: {
            LineBadge(line: code, size: .sm)
                .padding(3)
                .background(
                    Circle().stroke(
                        isActive ? DS.Color.ink : DS.Color.ink.opacity(0),
                        lineWidth: 2
                    )
                )
                .opacity(isActive || selectedLine == "Tout" ? 1 : 0.5)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Filtrer sur la ligne \(code)")
    }

    /// Same normalisation as SchedulesView / LigneDetailPage — strips
    /// `:City`/`:Suburb` suffixes and T/B/M prefixes.
    private static func shortCode(from rawLineId: String) -> String {
        var token = rawLineId
        if let colonRange = token.range(of: ":") {
            token = String(token[..<colonRange.lowerBound])
        }
        token = token.trimmingCharacters(in: .whitespaces).uppercased()
        if let first = token.first, "TBM".contains(first), token.dropFirst().allSatisfy(\.isNumber) {
            token = String(token.dropFirst())
        }
        return token
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
