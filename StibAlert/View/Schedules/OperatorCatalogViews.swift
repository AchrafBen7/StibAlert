import SwiftUI

/// Searchable, mode-grouped line catalog for De Lijn / TEC (Horaires tab).
/// These networks are line-based (no per-gare model like SNCB), so Horaires
/// shows the full line directory pulled from the GTFS routes.
struct OperatorLineDirectory: View {
    let op: TransitOperator
    @Binding var searchQuery: String

    @State private var lines: [OperatorLine] = []
    @State private var isLoading = true

    private static let modeOrder = ["tram", "metro", "trolleybus", "bus"]

    private var groups: [(mode: String, lines: [OperatorLine])] {
        let needle = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        let filtered = needle.isEmpty ? lines : lines.filter {
            "\($0.shortName) \($0.longName)"
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
                .contains(needle)
        }
        let grouped = Dictionary(grouping: filtered, by: { $0.mode })
        return grouped.keys
            .sorted { (Self.modeOrder.firstIndex(of: $0) ?? 9) < (Self.modeOrder.firstIndex(of: $1) ?? 9) }
            .map { mode in
                (mode: mode, lines: grouped[mode]!.sorted {
                    $0.shortName.compare($1.shortName, options: .numeric) == .orderedAscending
                })
            }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if isLoading && lines.isEmpty {
                VStack(spacing: 14) {
                    Spacer().frame(height: 60)
                    ProgressView().tint(DS.Color.ink)
                    Text("Chargement des lignes \(op.mapLabel)…")
                        .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
                }
                .frame(maxWidth: .infinity)
            } else if groups.isEmpty {
                VStack(spacing: 8) {
                    Spacer().frame(height: 60)
                    Image(systemName: "magnifyingglass").font(.system(size: 22)).foregroundStyle(DS.Color.inkMute)
                    Text("Aucune ligne trouvée").font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink)
                }
                .frame(maxWidth: .infinity)
            } else {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    ForEach(groups, id: \.mode) { group in
                        section(group)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .task(id: op) {
            isLoading = true
            lines = await OperatorCatalogService.lines(operator: op)
            isLoading = false
        }
    }

    private func section(_ group: (mode: String, lines: [OperatorLine])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: group.mode == "tram" ? "tram.fill" : "bus.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 30, height: 30)
                    .background(DS.Color.paper2).clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                Text((group.lines.first?.modeLabel ?? group.mode).uppercased())
                    .font(DS.Font.eyebrow).tracking(2).foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("\(group.lines.count)")
                    .font(DS.Font.monoSmall.weight(.bold)).foregroundStyle(DS.Color.inkMute)
            }
            VStack(spacing: 0) {
                ForEach(group.lines) { lineRow($0) }
            }
            .background(DS.Color.paper.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private func lineRow(_ line: OperatorLine) -> some View {
        HStack(spacing: 12) {
            Text(line.shortName)
                .font(.system(size: 13, weight: .black, design: .rounded))
                .foregroundStyle(badgeTextColor(line))
                .frame(minWidth: 38, minHeight: 30)
                .padding(.horizontal, 6)
                .background(badgeColor(line))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            Text(line.longName)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .overlay(Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
    }

    private func badgeColor(_ line: OperatorLine) -> Color {
        let hex = line.color.trimmingCharacters(in: .whitespaces)
        if hex.isEmpty || hex.uppercased() == "FFFFFF" { return op.brandColor }
        return Color(hex: "#\(hex)")
    }

    private func badgeTextColor(_ line: OperatorLine) -> Color {
        let hex = line.color.trimmingCharacters(in: .whitespaces)
        if hex.isEmpty || hex.uppercased() == "FFFFFF" { return op.brandTextColor }
        return Color(hex: "#\(line.textColor.isEmpty ? "000000" : line.textColor)")
    }
}

/// Official De Lijn / TEC disruptions list (Infos trafic tab).
struct OperatorDisruptionsList: View {
    let op: TransitOperator

    @State private var disruptions: [OperatorDisruption] = []
    @State private var isLoading = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: disruptions.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(disruptions.isEmpty ? DS.Color.statusOK : DS.Color.statusMajor)
                    .frame(width: 28, height: 28)
                    .background((disruptions.isEmpty ? DS.Color.statusOK : DS.Color.statusMajor).opacity(0.14))
                    .clipShape(Circle())
                Text("PERTURBATIONS \(op.mapLabel.uppercased())")
                    .font(DS.Font.eyebrow).tracking(2).foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("\(disruptions.count)")
                    .font(DS.Font.monoSmall.weight(.bold)).foregroundStyle(DS.Color.inkMute)
            }

            if isLoading && disruptions.isEmpty {
                ProgressView().tint(DS.Color.ink).frame(maxWidth: .infinity).padding(.vertical, 24)
            } else if disruptions.isEmpty {
                HStack(spacing: 12) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold)).foregroundStyle(DS.Color.statusOK)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Réseau \(op.mapLabel) OK").font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink)
                        Text("Aucune perturbation officielle en cours.").font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(DS.Color.statusOK.opacity(0.08))
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous).stroke(DS.Color.statusOK.opacity(0.25), lineWidth: 1))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            } else {
                VStack(spacing: 8) {
                    ForEach(disruptions) { disruptionCard($0) }
                }
            }
        }
        .task(id: op) {
            isLoading = true
            disruptions = await OperatorCatalogService.disruptions(operator: op)
            isLoading = false
        }
    }

    private func disruptionCard(_ d: OperatorDisruption) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.statusMinor)
                .frame(width: 28, height: 28)
                .background(DS.Color.statusMinor.opacity(0.14)).clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                if !d.header.isEmpty {
                    Text(d.header).font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink).lineLimit(3)
                }
                if !d.description.isEmpty {
                    Text(d.description).font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute).lineLimit(5)
                }
                if let url = URL(string: d.url), !d.url.isEmpty {
                    Link(destination: url) {
                        Text("Plus d'infos").font(.system(size: 11, weight: .bold)).foregroundStyle(DS.Color.info)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous).stroke(DS.Color.ink.opacity(0.10), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}
