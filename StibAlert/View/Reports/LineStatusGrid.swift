import SwiftUI

/// IDF Mobilités-style status grid: lines grouped by mode (Métro / Tram /
/// Bus) and shown as colored badges. A small corner indicator hints at the
/// current incident state on each line (clock = scheduled works, warning =
/// disruption, info = info, none = nominal). Tap a badge to push the
/// `LigneDetailPage` for that line.
struct LineStatusGrid: View {
    let catalog: [LigneCatalogDTO]
    let incidents: [TransportIncidentDTO]
    let onSelectLine: (String) -> Void

    /// One row of the grid: a single physical line displayed once even
    /// though the catalog ships it twice (City + Suburb variants).
    fileprivate struct DisplayLine: Identifiable {
        let id: String          // shortCode = unique key
        let shortCode: String   // "1", "7", "81" — what LineBadge expects
        let lookupId: String    // backend id used for the detail fetch
    }

    /// Strip ":City"/":Suburb" direction suffix and any T/B/M prefix so the
    /// LineBadge renders the official STIB colour. Kept in sync with
    /// `SchedulesView.shortCode(from:)` and the helper in `LigneDetailPage`.
    static func shortCode(from rawLineId: String) -> String {
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

    /// Map shortCode → highest severity badge to display.
    private var statusByLine: [String: LineIncidentBadge] {
        var byLine: [String: LineIncidentBadge] = [:]
        for incident in incidents {
            guard let raw = incident.line else { continue }
            let code = Self.shortCode(from: raw)
            guard !code.isEmpty else { continue }
            let badge = LineIncidentBadge(severity: incident.severity ?? "", type: incident.type ?? "")
            if let existing = byLine[code], existing.priority >= badge.priority {
                continue
            }
            byLine[code] = badge
        }
        return byLine
    }

    private var groupedLines: [(mode: TransitLineMode, lines: [DisplayLine])] {
        // De-dupe the catalog by shortCode (City + Suburb variants merge into
        // a single grid cell) before grouping by mode. Without this the BUS
        // section showed every line twice — once per direction — making it
        // unreasonably long.
        var byShortCode: [String: DisplayLine] = [:]
        for entry in catalog {
            let short = Self.shortCode(from: entry.lineid)
            guard !short.isEmpty, byShortCode[short] == nil else { continue }
            byShortCode[short] = DisplayLine(id: short, shortCode: short, lookupId: entry.lineid)
        }
        let unique = Array(byShortCode.values)
        let groups = Dictionary(grouping: unique) { TransitLineMode.mode(for: $0.shortCode) }
        let orderedModes: [TransitLineMode] = [.metro, .tram, .bus]
        return orderedModes.compactMap { mode -> (mode: TransitLineMode, lines: [DisplayLine])? in
            guard let lines = groups[mode], !lines.isEmpty else { return nil }
            let sorted = lines.sorted { numericRank($0.shortCode) < numericRank($1.shortCode) }
            return (mode, sorted)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            ForEach(Array(groupedLines.enumerated()), id: \.offset) { _, group in
                section(for: group.mode, lines: group.lines)
            }
        }
    }

    private func section(for mode: TransitLineMode, lines: [DisplayLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: mode.sfSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 30, height: 30)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                Text(mode.label)
                    .font(DS.Font.eyebrow)
                    .tracking(2)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Color.inkMute)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                spacing: 10
            ) {
                ForEach(lines) { line in
                    Button {
                        UISelectionFeedbackGenerator().selectionChanged()
                        onSelectLine(line.lookupId)
                    } label: {
                        badgeCell(line)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(DS.Color.paper.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private func badgeCell(_ line: DisplayLine) -> some View {
        ZStack(alignment: .bottomTrailing) {
            // FIX — TOUS les badges en carré identique (50×50) sur toute la
            // grille. Avant, LineBadge imposait sa largeur intrinsèque selon le
            // nombre de chiffres (34 pour "1", 44 pour "18", 52 pour "100"…) →
            // carrés de tailles inégales. squareSide force un carré exact ; le
            // texte se réduit légèrement (minimumScaleFactor) si besoin.
            LineBadge(line: line.shortCode, size: .lg, squareSide: 50)

            if let badge = statusByLine[line.shortCode] {
                Image(systemName: badge.icon)
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(.white)
                    .frame(width: 18, height: 18)
                    .background(badge.color)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(DS.Color.paper, lineWidth: 1.5)
                    )
                    .offset(x: 6, y: 4)
            }
        }
    }

    private func numericRank(_ shortCode: String) -> Int {
        Int(shortCode) ?? Int.max
    }
}

/// Badge representation of the worst incident currently affecting a line.
/// Priority controls which icon wins when a line has multiple incidents.
private struct LineIncidentBadge {
    let icon: String
    let color: Color
    let priority: Int

    init(severity: String, type: String) {
        let sev = severity.lowercased()
        let lowerType = type.lowercased()

        if sev.contains("critical") || sev.contains("major") || lowerType.contains("interrupt") {
            self.icon = "exclamationmark.triangle.fill"
            self.color = DS.Color.statusMajor
            self.priority = 100
        } else if lowerType.contains("travaux") || lowerType.contains("works") || lowerType.contains("construction") {
            // hammer.fill au lieu de cone.fill : le cône de chantier était
            // méconnaissable en 18px (ressemblait à un "cuberdon" orange). Le
            // marteau reste net à petite taille et lit "travaux" sans ambiguïté.
            self.icon = "hammer.fill"
            self.color = DS.Color.statusMinor
            self.priority = 70
        } else if sev.contains("minor") || lowerType.contains("retard") || lowerType.contains("delay") {
            self.icon = "clock.fill"
            self.color = DS.Color.statusMinor
            self.priority = 50
        } else {
            self.icon = "info.fill"
            self.color = DS.Color.community
            self.priority = 20
        }
    }
}
