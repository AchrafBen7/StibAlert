import SwiftUI
import CoreLocation

/// Searchable, mode-grouped line catalog for De Lijn / TEC (Horaires tab).
/// These networks are line-based (no per-gare model like SNCB), so Horaires
/// shows the full line directory pulled from the GTFS routes.
struct OperatorLineDirectory: View {
    let op: TransitOperator
    @Binding var searchQuery: String

    @State private var lines: [OperatorLine] = []
    @State private var disruptions: [OperatorDisruption] = []
    @State private var selectedLine: OperatorLine?
    @State private var selectedZone: String = OperatorLineZone.allKey
    @State private var isLoading = true

    private static let modeOrder = ["tram", "metro", "trolleybus", "bus"]

    private var zones: [OperatorLineZone] {
        var counts: [String: Int] = [:]
        for line in lines {
            counts[line.zoneKey(for: op), default: 0] += 1
        }

        let concreteZones = counts
            .map { OperatorLineZone(key: $0.key, label: OperatorLine.zoneLabel(for: op, key: $0.key), count: $0.value) }
            .sorted { lhs, rhs in
                let left = OperatorLine.zoneSortIndex(for: op, key: lhs.key)
                let right = OperatorLine.zoneSortIndex(for: op, key: rhs.key)
                if left != right { return left < right }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }

        return [OperatorLineZone(key: OperatorLineZone.allKey, label: "Toutes zones", count: lines.count)] + concreteZones
    }

    private var groups: [(mode: String, lines: [OperatorLine])] {
        let needle = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        let zoneFiltered = selectedZone == OperatorLineZone.allKey
            ? lines
            : lines.filter { $0.zoneKey(for: op) == selectedZone }

        let scopedLines = needle.isEmpty ? zoneFiltered : lines
        let filtered = needle.isEmpty ? scopedLines : scopedLines.filter {
            "\($0.shortName) \($0.longName) \($0.zoneLabel(for: op))"
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
            if let selectedLine {
                // Détail d'une ligne (cliquable comme STIB/SNCB) : en-tête +
                // perturbations live de la ligne, ou « rien à signaler ».
                OperatorLineDisruptionDetail(
                    op: op,
                    issue: issue(for: selectedLine),
                    onBack: { withAnimation(.easeInOut(duration: 0.2)) { self.selectedLine = nil } }
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 18)
            } else if isLoading && lines.isEmpty {
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
                    zoneFilter
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
            selectedLine = nil
            async let linesTask = OperatorCatalogService.lines(operator: op)
            async let disruptionsTask = OperatorCatalogService.disruptions(operator: op)
            lines = await linesTask
            disruptions = await disruptionsTask
            if selectedZone == OperatorLineZone.allKey || !lines.contains(where: { $0.zoneKey(for: op) == selectedZone }) {
                selectedZone = OperatorLine.preferredZoneKey(for: op, in: lines)
            }
            isLoading = false
        }
        .onChange(of: op) { _, newOperator in
            selectedZone = OperatorLine.preferredZoneKey(for: newOperator, in: lines)
        }
    }

    /// Construit l'« issue » d'une ligne = la ligne + ses perturbations
    /// (matchées par routeId : id GTFS complet OU short_name brut, selon
    /// l'opérateur). Vide = aucune perturbation connue → état « rijdt normaal ».
    private func issue(for line: OperatorLine) -> OperatorLineIssue {
        var seen = Set<String>()
        let matched = disruptions.filter { d in
            (d.routeIds.contains(line.id) || d.routeIds.contains(line.shortName)) && seen.insert(d.id).inserted
        }
        return OperatorLineIssue(line: line, disruptions: matched)
    }

    private var zoneFilter: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: "scope")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(op.brandColor)
                    .frame(width: 26, height: 26)
                    .background(op.brandColor.opacity(0.12))
                    .clipShape(Circle())
                Text(zoneHeaderTitle)
                    .font(DS.Font.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("\(visibleLineCount) / \(lines.count)")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.inkMute)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(zones) { zone in
                        zoneChip(zone)
                    }
                }
                .padding(.vertical, 1)
            }
        }
    }

    private var zoneHeaderTitle: String {
        if searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return op == .tec ? "FILTRER PAR RÉGION TEC" : "FILTRER PAR ZONE"
        }
        return "RECHERCHE SUR TOUT LE RÉSEAU"
    }

    private var visibleLineCount: Int {
        groups.reduce(0) { $0 + $1.lines.count }
    }

    private func zoneChip(_ zone: OperatorLineZone) -> some View {
        let active = selectedZone == zone.key
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedZone = zone.key
            }
        } label: {
            HStack(spacing: 7) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
                Text(zone.label)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text("\(zone.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? DS.Color.paper.opacity(0.72) : DS.Color.inkMute)
            }
            .foregroundStyle(active ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(active ? DS.Color.ink : DS.Color.paper)
            .overlay(
                Capsule()
                    .stroke(active ? DS.Color.ink : DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
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
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) { selectedLine = line }
        } label: {
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
                if selectedZone == OperatorLineZone.allKey || !searchQuery.isEmpty {
                    Text(line.zoneLabel(for: op))
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(0.7)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.horizontal, 7)
                        .frame(height: 22)
                        .background(DS.Color.paper2)
                        .clipShape(Capsule())
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
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

/// Annuaire d'arrêts pour De Lijn dans l'onglet Horaires. Le temps réel De Lijn
/// est PAR ARRÊT (l'API donne les prochains passages d'une halte, pas la liste
/// des arrêts d'une ligne) → comme SNCB, on liste les arrêts proches + une
/// recherche, et un tap ouvre les VRAIS passages temps réel (HomeOperatorStopSheet).
struct OperatorStopDirectory: View {
    let op: TransitOperator
    @Binding var searchQuery: String

    @StateObject private var locator = OneShotLocationManager()
    @State private var stops: [OperatorMapStop] = []
    @State private var isLoading = true
    @State private var selectedStop: OperatorMapStop?

    private var filteredStops: [OperatorMapStop] {
        let q = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return stops }
        return stops.filter { $0.name.localizedCaseInsensitiveContains(q) }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            if isLoading && stops.isEmpty {
                VStack(spacing: 14) {
                    Spacer().frame(height: 60)
                    ProgressView().tint(DS.Color.ink)
                    Text("Arrêts \(op.mapLabel) à proximité…")
                        .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
                }
                .frame(maxWidth: .infinity)
            } else if stops.isEmpty {
                stopEmptyState(title: "Aucun arrêt \(op.mapLabel) à proximité",
                               subtitle: "Active la localisation et réessaie.")
            } else if filteredStops.isEmpty {
                stopEmptyState(title: "Aucun arrêt trouvé",
                               subtitle: "Essaie un autre nom d'arrêt.")
            } else {
                VStack(alignment: .leading, spacing: 12) {
                    HStack(spacing: 8) {
                        Image(systemName: "location.fill")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(op.brandColor)
                        Text(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "ARRÊTS PROCHES" : "RÉSULTATS")
                            .font(DS.Font.eyebrow).tracking(1.6).foregroundStyle(DS.Color.inkMute)
                        Spacer()
                        Text("\(filteredStops.count)")
                            .font(DS.Font.monoSmall.weight(.bold)).foregroundStyle(DS.Color.inkMute)
                    }
                    VStack(spacing: 0) {
                        ForEach(filteredStops) { stopRow($0) }
                    }
                    .background(DS.Color.paper.opacity(0.95))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
        }
        .task(id: op) { await load() }
        .sheet(item: $selectedStop) { stop in
            // Réutilise la fiche temps réel De Lijn qui marche déjà sur la carte.
            HomeOperatorStopSheet(stop: stop, onReport: { selectedStop = nil })
        }
    }

    private func stopRow(_ stop: OperatorMapStop) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedStop = stop
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(op.brandColor).frame(width: 30, height: 30)
                    Image(systemName: "bus.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(op.brandTextColor)
                }
                Text(stop.name)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.vertical, 12)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }

    private func stopEmptyState(title: String, subtitle: String) -> some View {
        VStack(spacing: 8) {
            Spacer().frame(height: 60)
            Image(systemName: "mappin.slash").font(.system(size: 22)).foregroundStyle(DS.Color.inkMute)
            Text(title).font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink)
            Text(subtitle).font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let loc = await locator.getCurrentLocation()
        let origin = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
        func fetch(_ d: Double) async -> [OperatorMapStop] {
            await OperatorStopService.stops(
                operator: op,
                minLat: origin.latitude - d, maxLat: origin.latitude + d,
                minLng: origin.longitude - d, maxLng: origin.longitude + d,
                limit: 120
            )
        }
        var found = await fetch(0.02)
        if found.isEmpty { found = await fetch(0.06) }
        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        stops = found
            .sorted {
                originLoc.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))
                    < originLoc.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lng))
            }
            .prefix(50)
            .map { $0 }
    }
}

/// Official De Lijn / TEC disruptions list (Infos trafic tab).
struct OperatorDisruptionsList: View {
    let op: TransitOperator
    var userCoordinate: CLLocationCoordinate2D? = nil

    @State private var lines: [OperatorLine] = []
    @State private var disruptions: [OperatorDisruption] = []
    @State private var lineIssues: [OperatorLineIssue] = []
    @State private var selectedIssue: OperatorLineIssue?
    @State private var searchQuery = ""
    @State private var selectedZone: String = OperatorLineZone.allKey
    @State private var isLoading = true

    private static let modeOrder = ["tram", "metro", "trolleybus", "bus"]

    private var zones: [OperatorLineZone] {
        var counts: [String: Int] = [:]
        for issue in lineIssues {
            counts[issue.line.zoneKey(for: op), default: 0] += 1
        }

        let concreteZones = counts
            .map { OperatorLineZone(key: $0.key, label: OperatorLine.zoneLabel(for: op, key: $0.key), count: $0.value) }
            .sorted { lhs, rhs in
                let left = OperatorLine.zoneSortIndex(for: op, key: lhs.key)
                let right = OperatorLine.zoneSortIndex(for: op, key: rhs.key)
                if left != right { return left < right }
                return lhs.label.localizedCaseInsensitiveCompare(rhs.label) == .orderedAscending
            }

        return [OperatorLineZone(key: OperatorLineZone.allKey, label: "Toutes zones", count: lineIssues.count)] + concreteZones
    }

    private var filteredIssues: [OperatorLineIssue] {
        let needle = searchQuery
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        let zoneFiltered = selectedZone == OperatorLineZone.allKey
            ? lineIssues
            : lineIssues.filter { $0.line.zoneKey(for: op) == selectedZone }

        let scopedIssues = needle.isEmpty ? zoneFiltered : lineIssues
        guard !needle.isEmpty else { return scopedIssues }

        return scopedIssues.filter { issue in
            let disruptionText = issue.disruptions
                .map { "\($0.header) \($0.description)" }
                .joined(separator: " ")
            return "\(issue.line.shortName) \(issue.line.longName) \(issue.line.zoneLabel(for: op)) \(issue.previewText) \(disruptionText)"
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
                .contains(needle)
        }
    }

    private var groups: [(mode: String, issues: [OperatorLineIssue])] {
        let grouped = Dictionary(grouping: filteredIssues, by: { $0.line.mode })
        return grouped.keys
            .sorted { (Self.modeOrder.firstIndex(of: $0) ?? 9) < (Self.modeOrder.firstIndex(of: $1) ?? 9) }
            .map { mode in
                (
                    mode: mode,
                    issues: grouped[mode, default: []].sorted { lhs, rhs in
                        lhs.line.shortName.compare(rhs.line.shortName, options: .numeric) == .orderedAscending
                    }
                )
            }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let selectedIssue {
                OperatorLineDisruptionDetail(
                    op: op,
                    issue: selectedIssue,
                    onBack: {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            self.selectedIssue = nil
                        }
                    }
                )
            } else {
            networkHeader
                searchAndZoneFilters
                content
            }
        }
        .task(id: op) {
            selectedIssue = nil
            isLoading = true
            async let linesTask = OperatorCatalogService.lines(operator: op)
            async let disruptionsTask = OperatorCatalogService.disruptions(operator: op)
            let loadedLines = await linesTask
            let loadedDisruptions = await disruptionsTask
            lines = loadedLines
            disruptions = loadedDisruptions
            lineIssues = Self.buildLineIssues(lines: loadedLines, disruptions: loadedDisruptions)
            selectedZone = OperatorLine.preferredZoneKey(for: op, userCoordinate: userCoordinate, in: loadedLines)
            isLoading = false
        }
    }

    private var networkHeader: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: disruptions.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(disruptions.isEmpty ? DS.Color.statusOK : DS.Color.statusMajor)
                    .frame(width: 28, height: 28)
                    .background((disruptions.isEmpty ? DS.Color.statusOK : DS.Color.statusMajor).opacity(0.14))
                    .clipShape(Circle())
                Text("RÉSEAU \(op.mapLabel.uppercased())")
                    .font(DS.Font.eyebrow)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("\(disruptions.count) dépêches")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.inkMute)
            }

            HStack(spacing: 0) {
                operatorMetric(title: "ÉTAT", value: disruptions.isEmpty ? "NORMAL" : "PERTURBÉ", tint: disruptions.isEmpty ? DS.Color.statusOK : DS.Color.statusMajor)
                Rectangle().fill(DS.Color.ink.opacity(0.12)).frame(width: 1)
                operatorMetric(title: "LIGNES TOUCHÉES", value: "\(filteredIssues.count)", tint: DS.Color.ink)
                Rectangle().fill(DS.Color.ink.opacity(0.12)).frame(width: 1)
                operatorMetric(title: "SOURCE", value: "OFFICIEL", tint: op.brandColor)
            }
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private var searchAndZoneFilters: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
                TextField("Chercher une ligne \(op.mapLabel)", text: $searchQuery)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.ink)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                if !searchQuery.isEmpty {
                    Button {
                        searchQuery = ""
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 46)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(op.brandColor)
                    Text(zoneHeaderTitle)
                        .font(DS.Font.eyebrow)
                        .tracking(1.5)
                        .foregroundStyle(DS.Color.inkMute)
                    Spacer()
                    Text("\(filteredIssues.count) / \(lineIssues.count)")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundStyle(DS.Color.inkMute)
                }

                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(zones) { zone in
                            zoneChip(zone)
                        }
                    }
                    .padding(.vertical, 1)
                }
            }
        }
    }

    private var zoneHeaderTitle: String {
        if !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return "RECHERCHE SUR TOUT LE RÉSEAU"
        }
        return userCoordinate == nil ? "ZONE PRIORITAIRE" : "PLUS PROCHE DE TOI"
    }

    private func zoneChip(_ zone: OperatorLineZone) -> some View {
        let active = selectedZone == zone.key
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedZone = zone.key
            }
        } label: {
            HStack(spacing: 7) {
                if active {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
                Text(zone.label)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                Text("\(zone.count)")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(active ? DS.Color.paper.opacity(0.72) : DS.Color.inkMute)
            }
            .foregroundStyle(active ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(active ? DS.Color.ink : DS.Color.paper)
            .overlay(
                Capsule()
                    .stroke(active ? DS.Color.ink : DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var content: some View {
        if isLoading && lineIssues.isEmpty {
            ProgressView()
                .tint(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 24)
        } else if lineIssues.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.statusOK)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Réseau \(op.mapLabel) OK")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                    Text("Aucune perturbation officielle liée à une ligne.")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.statusOK.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.statusOK.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        } else if filteredIssues.isEmpty {
            HStack(spacing: 12) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Aucune ligne trouvée")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                    Text("Essaie un numéro de ligne ou une autre zone.")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        } else {
            VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                ForEach(groups, id: \.mode) { group in
                    operatorModeSection(group)
                }
            }
        }
    }

    private func operatorModeSection(_ group: (mode: String, issues: [OperatorLineIssue])) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: group.mode == "tram" ? "tram.fill" : "bus.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 30, height: 30)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                Text((group.issues.first?.line.modeLabel ?? group.mode).uppercased())
                    .font(DS.Font.eyebrow)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text("\(group.issues.count)")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.inkMute)
            }

            VStack(spacing: 0) {
                ForEach(group.issues) { issue in
                    operatorLineIssueRow(issue)
                }
            }
            .background(DS.Color.paper.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private func operatorLineIssueRow(_ issue: OperatorLineIssue) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedIssue = issue
            }
        } label: {
            HStack(spacing: 12) {
                OperatorRouteBadge(op: op, line: issue.line)
                VStack(alignment: .leading, spacing: 3) {
                    Text(issue.line.longName.isEmpty ? "Ligne \(issue.line.shortName)" : issue.line.longName)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Text(issue.previewText)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                HStack(spacing: 5) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 10, weight: .black))
                    Text("\(issue.disruptions.count)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                }
                .foregroundStyle(DS.Color.statusMajor)
                .padding(.horizontal, 7)
                .frame(height: 22)
                .background(Capsule().fill(DS.Color.statusMajor.opacity(0.12)))
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .contentShape(Rectangle())
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
        }
        .buttonStyle(.plain)
    }

    private func operatorMetric(title: String, value: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(DS.Font.eyebrow)
                .tracking(1.4)
                .foregroundStyle(DS.Color.inkMute)
            Text(value)
                .font(.system(size: 15, weight: .black, design: .rounded))
                .foregroundStyle(tint)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private static func buildLineIssues(
        lines: [OperatorLine],
        disruptions: [OperatorDisruption]
    ) -> [OperatorLineIssue] {
        // Indexation par DEUX clés possibles : l'id GTFS complet
        // ("gr:tec:L0076-23207") ET le short_name brut ("128"). Le backend
        // émet l'un OU l'autre selon l'opérateur :
        //   - TEC : routeIds = id GTFS complet (match direct sur line.id)
        //   - De Lijn : routeIds = short_name brut (impossible de
        //     reconstruire l'id GTFS depuis l'API De Lijn)
        // Sans ce double-index, De Lijn affichait "Réseau OK" alors qu'il y
        // a 300+ alertes actives.
        var disruptionsByRoute: [String: [OperatorDisruption]] = [:]
        for disruption in disruptions {
            for routeId in disruption.routeIds {
                disruptionsByRoute[routeId, default: []].append(disruption)
            }
        }

        return lines.compactMap { line in
            var related: [OperatorDisruption] = []
            if let byId = disruptionsByRoute[line.id] { related.append(contentsOf: byId) }
            if let byShort = disruptionsByRoute[line.shortName] { related.append(contentsOf: byShort) }
            let unique = related.deduplicatedById()
            guard !unique.isEmpty else { return nil }
            return OperatorLineIssue(line: line, disruptions: unique)
        }
        .sorted { lhs, rhs in
            if lhs.line.mode != rhs.line.mode {
                let leftMode = Self.modeOrder.firstIndex(of: lhs.line.mode) ?? 9
                let rightMode = Self.modeOrder.firstIndex(of: rhs.line.mode) ?? 9
                return leftMode < rightMode
            }
            return lhs.line.shortName.compare(rhs.line.shortName, options: .numeric) == .orderedAscending
        }
    }
}

private struct OperatorLineZone: Identifiable {
    static let allKey = "all"

    let key: String
    let label: String
    let count: Int

    var id: String { key }
}

private extension OperatorLine {
    static func preferredZoneKey(for op: TransitOperator, in lines: [OperatorLine]) -> String {
        let preferred = op == .tec ? "brabant" : "brussels"
        return lines.contains { $0.zoneKey(for: op) == preferred } ? preferred : OperatorLineZone.allKey
    }

    static func preferredZoneKey(
        for op: TransitOperator,
        userCoordinate: CLLocationCoordinate2D?,
        in lines: [OperatorLine]
    ) -> String {
        let candidates = Set(lines.map { $0.zoneKey(for: op) })
        guard let userCoordinate else {
            return preferredZoneKey(for: op, in: lines)
        }

        let rankedZones = nearbyZoneCandidates(for: op, userCoordinate: userCoordinate)
        if let match = rankedZones.first(where: { candidates.contains($0) }) {
            return match
        }
        return preferredZoneKey(for: op, in: lines)
    }

    func zoneLabel(for op: TransitOperator) -> String {
        Self.zoneLabel(for: op, key: zoneKey(for: op))
    }

    func zoneKey(for op: TransitOperator) -> String {
        switch op {
        case .tec:
            return tecZoneKey
        case .delijn:
            return deLijnZoneKey
        case .stib, .sncb:
            return OperatorLineZone.allKey
        }
    }

    static func zoneLabel(for op: TransitOperator, key: String) -> String {
        switch op {
        case .tec:
            switch key {
            case "brabant": return "Brabant / Bruxelles"
            case "charleroi": return "Charleroi"
            case "hainaut": return "Hainaut"
            case "liege": return "Liège"
            case "namur": return "Namur"
            case "luxembourg": return "Luxembourg"
            default: return "Autres"
            }
        case .delijn:
            switch key {
            case "brussels": return "Bruxelles / Rand"
            case "vlaamsbrabant": return "Vlaams-Brabant"
            case "antwerpen": return "Anvers"
            case "limburg": return "Limbourg"
            case "oostvlaanderen": return "Flandre orientale"
            case "westvlaanderen": return "Flandre occidentale"
            default: return "Autres"
            }
        case .stib, .sncb:
            return "Toutes zones"
        }
    }

    static func zoneSortIndex(for op: TransitOperator, key: String) -> Int {
        let order: [String]
        switch op {
        case .tec:
            order = ["brabant", "charleroi", "hainaut", "liege", "namur", "luxembourg", "other"]
        case .delijn:
            order = ["brussels", "vlaamsbrabant", "antwerpen", "limburg", "oostvlaanderen", "westvlaanderen", "other"]
        case .stib, .sncb:
            order = [OperatorLineZone.allKey]
        }
        return order.firstIndex(of: key) ?? 99
    }

    private static func nearbyZoneCandidates(for op: TransitOperator, userCoordinate: CLLocationCoordinate2D) -> [String] {
        switch op {
        case .tec:
            return rankedZones(from: userCoordinate, anchors: [
                ("brabant", 50.8503, 4.3517),
                ("charleroi", 50.4108, 4.4446),
                ("namur", 50.4674, 4.8718),
                ("liege", 50.6326, 5.5797),
                ("hainaut", 50.4542, 3.9523),
                ("luxembourg", 49.6833, 5.8167),
                ("other", 50.8503, 4.3517)
            ])
        case .delijn:
            return rankedZones(from: userCoordinate, anchors: [
                ("brussels", 50.8503, 4.3517),
                ("vlaamsbrabant", 50.8798, 4.7005),
                ("antwerpen", 51.2194, 4.4025),
                ("oostvlaanderen", 51.0543, 3.7174),
                ("limburg", 50.9307, 5.3325),
                ("westvlaanderen", 51.2093, 3.2247),
                ("other", 50.8503, 4.3517)
            ])
        case .stib, .sncb:
            return [OperatorLineZone.allKey]
        }
    }

    private static func rankedZones(
        from userCoordinate: CLLocationCoordinate2D,
        anchors: [(key: String, lat: Double, lng: Double)]
    ) -> [String] {
        let userLocation = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        return anchors
            .sorted {
                let left = CLLocation(latitude: $0.lat, longitude: $0.lng)
                let right = CLLocation(latitude: $1.lat, longitude: $1.lng)
                return userLocation.distance(from: left) < userLocation.distance(from: right)
            }
            .map(\.key)
    }

    private var tecZoneKey: String {
        let token = id.split(separator: ":").last.map(String.init) ?? id
        if token.hasPrefix("B") { return "brabant" }
        if token.hasPrefix("C") { return "charleroi" }
        if token.hasPrefix("H") { return "hainaut" }
        if token.hasPrefix("L") { return "liege" }
        if token.hasPrefix("N") { return "namur" }
        if token.hasPrefix("X") { return "luxembourg" }
        return "other"
    }

    private var deLijnZoneKey: String {
        let haystack = longName
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        if containsAny(haystack, [
            "brussel", "brussels", "zaventem", "vilvoorde", "jette", "anderlecht",
            "dilbeek", "halle", "tervuren", "kraainem", "roodebeek", "groot-bijgaarden",
            "asse", "grimbergen", "overijse", "oudergem", "etterbeek", "woluwe",
            "alsemberg", "drogenbos", "beersel", "sint-genesius-rode", "ruisbroek",
            "sint-pieters-leeuw", "humbeek", "bordet", "wezembeek", "hoeilaart"
        ]) {
            return "brussels"
        }

        if containsAny(haystack, [
            "leuven", "aarschot", "tienen", "diest", "haacht", "herent", "kortenberg",
            "roosdaal", "ninove", "ternat", "liedekerke", "affligem", "tremelo",
            "lubbeek", "bierbeek", "rotselaar", "kampenhout"
        ]) {
            return "vlaamsbrabant"
        }

        if containsAny(haystack, [
            "antwerpen", "mechelen", "turnhout", "lier", "boom", "willebroek",
            "puurs", "beveren", "sint-niklaas", "kapellen", "ekeren", "schoten"
        ]) {
            return "antwerpen"
        }

        if containsAny(haystack, [
            "hasselt", "genk", "bilzen", "tongeren", "lommel", "bocholt", "bree",
            "maaseik", "heers", "wellen"
        ]) {
            return "limburg"
        }

        if containsAny(haystack, [
            "gent", "oudenaarde", "deinze", "lokeren", "eeklo", "aalst", "dendermonde",
            "merelbeke", "zelzate", "wetteren"
        ]) {
            return "oostvlaanderen"
        }

        if containsAny(haystack, [
            "brugge", "kortrijk", "oostende", "roeselare", "ieper", "poperinge",
            "knokke", "torhout", "veurne"
        ]) {
            return "westvlaanderen"
        }

        return "other"
    }

    private func containsAny(_ text: String, _ needles: [String]) -> Bool {
        needles.contains { text.contains($0) }
    }
}

private struct OperatorLineIssue: Identifiable {
    var id: String { line.id }
    let line: OperatorLine
    let disruptions: [OperatorDisruption]

    var previewText: String {
        disruptions.first?.header.nonEmpty ?? "\(disruptions.count) perturbation\(disruptions.count > 1 ? "s" : "") officielle\(disruptions.count > 1 ? "s" : "")"
    }
}

private struct OperatorLineDisruptionDetail: View {
    let op: TransitOperator
    let issue: OperatorLineIssue
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 12, weight: .bold))
                    Text("Lignes \(op.mapLabel)")
                        .font(DS.Font.bodyBold)
                }
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 12)
                .frame(height: 36)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
            }
            .buttonStyle(.plain)

            HStack(alignment: .top, spacing: 12) {
                OperatorRouteBadge(op: op, line: issue.line, height: 46)
                VStack(alignment: .leading, spacing: 5) {
                    Text(issue.line.longName.isEmpty ? "Ligne \(issue.line.shortName)" : issue.line.longName)
                        .font(.system(size: 19, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(2)
                    Text(issue.disruptions.isEmpty
                         ? "\(op.mapLabel) · \(issue.line.modeLabel)"
                         : "\(issue.disruptions.count) perturbation\(issue.disruptions.count > 1 ? "s" : "") officielle\(issue.disruptions.count > 1 ? "s" : "") · \(op.mapLabel)")
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                }
                Spacer(minLength: 0)
            }
            .padding(14)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            if issue.disruptions.isEmpty {
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(DS.Color.statusOK)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Aucune perturbation connue")
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                        Text("Cette ligne circule normalement selon les données disponibles.")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    Spacer(minLength: 0)
                }
                .padding(14)
                .background(DS.Color.statusOK.opacity(0.08))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.statusOK.opacity(0.25), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text("DÉTAIL DES PROBLÈMES")
                            .font(DS.Font.eyebrow)
                            .tracking(1.6)
                            .foregroundStyle(DS.Color.inkMute)
                        Spacer()
                        Text("\(issue.disruptions.count)")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .foregroundStyle(DS.Color.inkMute)
                    }

                    VStack(spacing: 8) {
                        ForEach(issue.disruptions) { disruptionCard($0) }
                    }
                }
            }
        }
    }

    private func disruptionCard(_ disruption: OperatorDisruption) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: disruption.header.lowercased().contains("werken") || disruption.header.lowercased().contains("travaux") ? "wrench.and.screwdriver.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.statusMinor)
                .frame(width: 28, height: 28)
                .background(DS.Color.statusMinor.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(disruption.header.isEmpty ? "Perturbation \(op.mapLabel)" : disruption.header)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(3)
                if !disruption.description.isEmpty {
                    Text(disruption.description)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(6)
                }
                if let url = URL(string: disruption.url), !disruption.url.isEmpty {
                    Link(destination: url) {
                        Text("Plus d'infos")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.Color.info)
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

private struct OperatorRouteBadge: View {
    let op: TransitOperator
    let line: OperatorLine
    var height: CGFloat = 34

    var body: some View {
        Text(line.shortName)
            .font(.system(size: max(11, height * 0.36), weight: .black, design: .rounded))
            .foregroundStyle(badgeTextColor)
            .lineLimit(1)
            .minimumScaleFactor(0.72)
            .padding(.horizontal, 8)
            .frame(minWidth: max(42, height * 1.15), minHeight: height)
            .background(badgeColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
    }

    private var badgeColor: Color {
        let hex = line.color.trimmingCharacters(in: .whitespaces)
        if hex.isEmpty || hex.uppercased() == "FFFFFF" { return op.brandColor }
        return Color(hex: "#\(hex)")
    }

    private var badgeTextColor: Color {
        let hex = line.color.trimmingCharacters(in: .whitespaces)
        if hex.isEmpty || hex.uppercased() == "FFFFFF" { return op.brandTextColor }
        return Color(hex: "#\(line.textColor.isEmpty ? "000000" : line.textColor)")
    }
}

private extension Array where Element == OperatorDisruption {
    func deduplicatedById() -> [OperatorDisruption] {
        var seen = Set<String>()
        return filter { disruption in
            seen.insert(disruption.id).inserted
        }
    }
}

private extension String {
    var nonEmpty: String? {
        let trimmed = trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }
}
