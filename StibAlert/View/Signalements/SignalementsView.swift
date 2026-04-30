import SwiftUI

struct SignalementsView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var stibi: StibiCenter
    @EnvironmentObject private var session: AuthSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var selectedFilter: LineFilter = .all
    @State private var query = ""
    @State private var selectedLine: LineStatusItem?
    @State private var remoteLines: [LineStatusItem] = []
    @State private var isLoadingRemote = false
    @State private var hasLoadedLines = false

    private var displayLines: [LineStatusItem] {
        AppConfig.isBackendEnabled ? remoteLines : (remoteLines.isEmpty ? LineStatusMockData.all : remoteLines)
    }

    private var filteredLines: [LineStatusItem] {
        let base = selectedFilter == .all
            ? displayLines
            : displayLines.filter { $0.filter == selectedFilter }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.line.localizedCaseInsensitiveContains(trimmed)
            || $0.direction.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var availableLinesCount: Int {
        displayLines.count
    }

    private var disruptedLines: [LineStatusItem] {
        filteredLines.filter { $0.status != .fluid }
    }

    private var healthyLines: [LineStatusItem] {
        filteredLines.filter { $0.status == .fluid }
    }

    private var healthyByMode: [(filter: LineFilter, lines: [LineStatusItem])] {
        let groups: [LineFilter] = [.metro, .tram, .bus]
        return groups.compactMap { filter in
            let lines = healthyLines.filter { $0.filter == filter }
            return lines.isEmpty ? nil : (filter, lines)
        }
    }

    private var healthRows: [(filter: LineFilter, ok: Int, ko: Int)] {
        let groups: [LineFilter] = [.metro, .tram, .bus]
        return groups.map { filter in
            let matching = displayLines.filter { $0.filter == filter }
            let ko = matching.filter { $0.status != .fluid }.count
            let ok = max(matching.count - ko, 0)
            return (filter, ok, ko)
        }
    }

    var body: some View {
        ZStack {
            DS.Color.paper
                .ignoresSafeArea()

            if let selectedLine {
                LigneDetailPage(
                    line: selectedLine,
                    onBack: {
                        withAnimation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.35, dampingFraction: 0.86)) {
                            self.selectedLine = nil
                        }
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.horizontal, 20)
                            .padding(.top, 12)

                        VStack(alignment: .leading, spacing: 20) {
                            healthMeterSection
                            DS.Rule(thick: true)
                            searchAndFiltersSection

                            if isLoadingRemote && !hasLoadedLines {
                                ProgressView()
                                    .tint(DS.Color.ink)
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 48)
                            } else if AppConfig.isBackendEnabled && displayLines.isEmpty {
                                linesEmptyState
                            } else if filteredLines.isEmpty {
                                linesSearchEmptyState
                            } else {
                                if !disruptedLines.isEmpty {
                                    disruptedSection
                                }
                                allLinesSection
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 16)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
        .modifier(PaperGrainBackground())
        .toolbar(.hidden, for: .navigationBar)
        .task {
            stibi.setCurrentScreen("signalements")
            await loadRemoteLines()
            applyPendingLineFocusIfPossible()
            await loadStibiContext()
        }
        .onChange(of: displayLines.count) { _, _ in
            applyPendingLineFocusIfPossible()
        }
    }

    private var topBar: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 19) {
                Button {
                    withAnimation(AppMotion.spring(reduceMotion: reduceMotion)) {
                        nav.showSideMenu = true
                    }
                } label: {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.paper)
                        .frame(width: 42, height: 40)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(DS.Color.ink)
                        )
                }
                .buttonStyle(.plain)
                .shadow(DS.Shadow.raised)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(DS.Color.inkSoft)

                    TextField("", text: $query, prompt: Text("Rechercher une ligne, une destination…").foregroundStyle(DS.Color.inkMute))
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.ink)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
                .shadow(DS.Shadow.raised)
            }

            VStack(alignment: .leading, spacing: 6) {
                PageHeader(
                    title: "Lignes",
                    eyebrow: "Réseau STIB · Bruxelles",
                    large: true
                )
            }
        }
    }

    private var healthMeterSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("État par mode")
            VStack(spacing: 10) {
                ForEach(healthRows, id: \.filter.id) { row in
                    EditorialHealthRow(
                        filter: row.filter,
                        ok: row.ok,
                        ko: row.ko,
                        isSelected: selectedFilter == row.filter
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedFilter = selectedFilter == row.filter ? .all : row.filter
                        }
                    }
                }
            }
        }
    }

    private var searchAndFiltersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            filtersRow
        }
    }

    private var filtersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(LineFilter.allCases) { filter in
                    Chip(
                        label: filter.label,
                        active: selectedFilter == filter,
                        icon: {
                            if filter != .all {
                                Image(systemName: filter.iconName)
                            }
                        }
                    ) {
                        withAnimation(.easeOut(duration: 0.15)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }.padding(.horizontal, 0)
    }

    private var disruptedSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundColor(DS.Color.statusMajor)
                SectionTitle("À surveiller · \(disruptedLines.count)")
            }

            VStack(spacing: 0) {
                Rectangle()
                    .fill(DS.Color.ink)
                    .frame(height: 2)
                ForEach(disruptedLines) { line in
                    DisruptedEditorialRow(
                        line: line
                    ) {
                        withAnimation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.35, dampingFraction: 0.86)) {
                            selectedLine = line
                        }
                    }
                }
            }
        }
    }

    private var allLinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionTitle("Toutes les lignes")
            VStack(alignment: .leading, spacing: 20) {
                ForEach(healthyByMode, id: \.filter.id) { group in
                    EditorialModeLineGroup(
                        filter: group.filter,
                        lines: group.lines
                    ) { line in
                        withAnimation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.35, dampingFraction: 0.86)) {
                            selectedLine = line
                        }
                    }
                }
            }
        }
    }

    @MainActor
    private func loadRemoteLines() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingRemote else { return }
        isLoadingRemote = true
        defer {
            isLoadingRemote = false
            hasLoadedLines = true
        }

        async let etatTask: [LigneEtatDTO] = LigneService.etatLignes()
        async let catalogTask: [LigneCatalogDTO] = LigneService.toutesLesLignes()
        async let signalementsTask: SignalementsListResponse = SignalementService.liste(page: 1, limit: 100)

        do {
            let (etats, catalog, signalementsResponse) = try await (etatTask, catalogTask, signalementsTask)
            let mergedStates = buildMergedLineStates(from: etats, catalog: catalog)
            remoteLines = buildLineStatusItems(from: mergedStates, signalements: signalementsResponse.signalements)
        } catch {
            print("SignalementsView remote load failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func applyPendingLineFocusIfPossible() {
        guard let line = nav.pendingLineFocus?.trimmingCharacters(in: .whitespacesAndNewlines), !line.isEmpty else {
            return
        }

        query = line
        selectedFilter = LineFilter.from(line: line)

        if let match = displayLines.first(where: { $0.line == line }) {
            withAnimation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.35, dampingFraction: 0.86)) {
                selectedLine = match
            }
            nav.pendingLineFocus = nil
        }
    }

    private func buildLineStatusItems(from etats: [LigneEtatDTO], signalements: [SignalementDTO]) -> [LineStatusItem] {
        let signalementsByLine = Dictionary(grouping: signalements, by: \.ligne)

        return etats.map { etat in
            let items = signalementsByLine[etat.lineid] ?? []
            let reportsCount = max(etat.incidents, items.count)
            let status: LineHealthStatus = {
                switch etat.statut {
                case "Bloqué": return .critical
                case "Perturbé": return .disrupted
                default:
                    if reportsCount >= 6 { return .critical }
                    if reportsCount >= 3 { return .disrupted }
                    return .fluid
                }
            }()

            let filter = LineFilter.from(typeTransport: etat.typeTransport)
            let (fallbackColor, _) = linePalette(for: etat.lineid, filter: filter)
            let lineColor = etat.couleur.flatMap { hex in hex.hasPrefix("#") ? Color(hex: hex) : Color(hex: "#" + hex) } ?? fallbackColor
            let lineTextColor = lineColor.isDark ? Color.white : Color.black

            let sampleStop = items.compactMap { signalement -> String? in
                if case .populated(let arret) = signalement.arretId { return arret.nom }
                return nil
            }.first ?? etat.nom ?? "Arrêts STIB"

            let destinationFallback = etat.destination?.fr ?? etat.nomRetour ?? "Bruxelles"
            let directionLabel = etat.nom.map { "\($0) → \(destinationFallback)" }
                ?? "\(sampleStop) → \(destinationFallback)"

            return LineStatusItem(
                line: etat.lineid,
                lineColor: lineColor,
                lineTextColor: lineTextColor,
                origin: etat.nom ?? sampleStop,
                destination: destinationFallback,
                direction: directionLabel,
                status: status,
                reportsCount: reportsCount,
                filter: filter,
                confidenceText: items.compactMap { $0.community?.confidence }.max().map {
                    "\(Int(($0 * 100).rounded()))% fiable"
                }
            )
        }
        .sorted {
            if $0.reportsCount == $1.reportsCount {
                return $0.line.compare($1.line, options: .numeric) == .orderedAscending
            }
            return $0.reportsCount > $1.reportsCount
        }
    }

    private func buildMergedLineStates(from etats: [LigneEtatDTO], catalog: [LigneCatalogDTO]) -> [LigneEtatDTO] {
        struct CatalogAccumulator {
            var lineid: String
            var nom: String?
            var nomRetour: String?
            var typeTransport: String?
            var couleur: String?
        }

        struct StateAccumulator {
            var incidents: Int = 0
            var statut: String = "Normal"
            var destination: LigneDestinationDTO?
        }

        var catalogByBase: [String: CatalogAccumulator] = [:]
        for line in catalog {
            let base = baseLineId(line.lineid)
            var current = catalogByBase[base] ?? CatalogAccumulator(
                lineid: base,
                nom: nil,
                nomRetour: nil,
                typeTransport: line.typeTransport,
                couleur: line.couleur
            )

            if current.nom == nil { current.nom = line.nomComplet }
            if current.nomRetour == nil { current.nomRetour = line.nomCompletRetour }
            if current.typeTransport == nil { current.typeTransport = line.typeTransport }
            if current.couleur == nil { current.couleur = line.couleur }

            if line.lineid == base {
                current.nom = line.nomComplet ?? current.nom
                current.nomRetour = line.nomCompletRetour ?? current.nomRetour
                current.typeTransport = line.typeTransport ?? current.typeTransport
                current.couleur = line.couleur ?? current.couleur
            }

            catalogByBase[base] = current
        }

        var statesByBase: [String: StateAccumulator] = [:]
        for state in etats {
            let base = baseLineId(state.lineid)
            var current = statesByBase[base] ?? StateAccumulator()
            current.incidents += state.incidents
            if lineStatusRank(state.statut) > lineStatusRank(current.statut) {
                current.statut = state.statut
            }
            current.destination = current.destination ?? state.destination
            statesByBase[base] = current
        }

        let allBaseIds = catalogByBase.isEmpty
            ? Set(statesByBase.keys)
            : Set(catalogByBase.keys)
        return allBaseIds.map { base in
            let catalogEntry = catalogByBase[base]
            let stateEntry = statesByBase[base]
            return LigneEtatDTO(
                lineid: base,
                nom: catalogEntry?.nom,
                nomRetour: catalogEntry?.nomRetour,
                typeTransport: catalogEntry?.typeTransport,
                couleur: catalogEntry?.couleur,
                direction: nil,
                destination: stateEntry?.destination,
                incidents: stateEntry?.incidents ?? 0,
                statut: stateEntry?.statut ?? "Normal"
            )
        }
        .sorted {
            $0.lineid.compare($1.lineid, options: .numeric) == .orderedAscending
        }
    }

    private func baseLineId(_ rawValue: String) -> String {
        rawValue.split(separator: ":").first.map(String.init) ?? rawValue
    }

    private func lineStatusRank(_ status: String) -> Int {
        switch status {
        case "Bloqué":
            return 3
        case "Perturbé":
            return 2
        default:
            return 1
        }
    }

    private func linePalette(for line: String, filter: LineFilter) -> (Color, Color) {
        switch filter {
        case .metro:
            return (Color(hex: "#8F4199"), .white)
        case .tram:
            return (Color(hex: "#FFDC01"), .black)
        case .bus:
            return (Color(hex: "#ED7807"), .white)
        case .all:
            let numeric = Int(line) ?? 0
            return numeric % 2 == 0 ? (Color(hex: "#0066A3"), .white) : (Color(hex: "#8F4199"), .white)
        }
    }

    @MainActor
    private func loadStibiContext() async {
        guard session.isSignedIn else { return }
        guard AppConfig.isBackendEnabled else { return }
        do {
            let context = try await AssistantService.context()
            stibi.pushContextInsight(for: "signalements", context: context)
        } catch {
            print("Signalements Stibi context failed: \(error.localizedDescription)")
        }
    }

    private var linesEmptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(DS.Color.statusOK)
            Text("Tout roule")
                .font(DS.Font.displayH2)
                .foregroundStyle(DS.Color.ink)
            Text("Aucun incident signalé sur le réseau STIB pour le moment.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }

    private var linesSearchEmptyState: some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: "magnifyingglass")
                .font(.system(size: 36, weight: .light))
                .foregroundStyle(DS.Color.inkMute)
            Text("Aucun résultat pour « \(query) »")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkSoft)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}

private struct EditorialHealthRow: View {
    let filter: LineFilter
    let ok: Int
    let ko: Int
    let isSelected: Bool
    let action: () -> Void

    private var total: Int { ok + ko }
    private var okPct: CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(ok) / CGFloat(total)
    }
    private var level: DS.StatusLevel {
        guard total > 0 else { return .ok }
        let ratio = Double(ko) / Double(total)
        if ko == 0 { return .ok }
        if ratio > 0.4 { return .critical }
        if ratio > 0.2 { return .major }
        return .minor
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Text(filter.label.uppercased())
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(1.4)
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 54, alignment: .leading)

                GeometryReader { geo in
                    HStack(spacing: 0) {
                        Rectangle()
                            .fill(DS.Color.statusOK)
                            .frame(width: geo.size.width * okPct)
                        Rectangle()
                            .fill(DS.Color.statusMajor)
                    }
                }
                .frame(height: 6)
                .background(DS.Color.paper2)
                .overlay(
                    RoundedRectangle(cornerRadius: 2)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 2))

                Text("\(ok)/\(total)")
                    .font(DS.Font.mono)
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 52, alignment: .trailing)

                StatusDot(level: level, size: 8)
            }
            .padding(.vertical, 2)
            .opacity(isSelected ? 0.82 : 1)
        }
        .buttonStyle(.plain)
    }
}

private struct DisruptedEditorialRow: View {
    let line: LineStatusItem
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                LineBadge(
                    line: line.line,
                    size: .lg,
                    fill: line.lineColor,
                    foreground: line.lineTextColor
                )
                .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    Text(line.direction)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)

                    Text(line.confidenceText ?? "\(line.reportsCount) signalements")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.statusMajor)
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.top, 6)
            }
            .padding(.vertical, 12)
            .overlay(
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.15))
                    .frame(height: 1),
                alignment: .bottom
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableRowStyle())
    }
}

private struct EditorialModeLineGroup: View {
    let filter: LineFilter
    let lines: [LineStatusItem]
    let onSelect: (LineStatusItem) -> Void

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 6)

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline) {
                Text(filter.label.uppercased())
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Text("\(lines.count)")
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.bottom, 4)
            .overlay(
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.15))
                    .frame(height: 1),
                alignment: .bottom
            )

            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(lines) { item in
                    Button {
                        onSelect(item)
                    } label: {
                        LineBadge(
                            line: item.line,
                            size: .lg,
                            fill: item.lineColor,
                            foreground: item.lineTextColor
                        )
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
        }
    }
}

private struct LineOverviewView: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private enum DirectionVariant: String, CaseIterable, Identifiable {
        case city = "City"
        case suburb = "Suburb"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .city: return "Aller"
            case .suburb: return "Retour"
            }
        }
    }

    let line: LineStatusItem
    let onBack: () -> Void
    @State private var cityLine: TransportLineDTO?
    @State private var suburbLine: TransportLineDTO?
    @State private var baseLineDetail: TransportLineDTO?
    @State private var selectedVariant: DirectionVariant = .city
    @State private var remoteStops: [LineOverviewStop] = []
    @State private var selectedStopDetail: TransportStopDTO?
    @State private var isLoadingStops = false
    @State private var isLoadingStopDetail = false
    @State private var hasLoadedStops = false

    private var transportLine: TransportLineDTO? {
        switch selectedVariant {
        case .city:
            return cityLine ?? suburbLine ?? baseLineDetail
        case .suburb:
            return suburbLine ?? cityLine ?? baseLineDetail
        }
    }

    private var availableVariants: [DirectionVariant] {
        var values: [DirectionVariant] = []
        if cityLine != nil { values.append(.city) }
        if suburbLine != nil { values.append(.suburb) }
        return values.isEmpty ? [.city] : values
    }

    private var stops: [LineOverviewStop] {
        if let transportLine {
            return Self.stops(from: transportLine, fallbackColor: line.lineColor, fallbackTextColor: line.lineTextColor)
        }
        return remoteStops
    }

    private var lineIncidents: [TransportIncidentDTO] {
        transportLine?.activeIncidents ?? []
    }

    private var lineAlternatives: [TransportAlternativeDTO] {
        Array((transportLine?.recommendedAlternatives ?? []).prefix(2))
    }

    private var routeOriginText: String {
        if let firstStop = transportLine?.line.stops.first?.name, !firstStop.isEmpty {
            return firstStop
        }
        return line.origin
    }

    private var routeDestinationText: String {
        if let lastStop = transportLine?.line.stops.last?.name, !lastStop.isEmpty {
            return lastStop
        }
        return line.destination
    }

    var body: some View {
        ZStack {
            DS.Color.paper
            .ignoresSafeArea()

            Circle()
                .fill(DS.Color.primary.opacity(0.08))
                .frame(width: 220, height: 220)
                .blur(radius: 34)
                .offset(x: 140, y: -220)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 12)

                routeSummary
                    .padding(.horizontal, 21)
                    .padding(.top, 18)

                if let transportLine {
                    TransportLineSnapshotCard(
                        line: transportLine,
                        alternatives: lineAlternatives
                    )
                    .padding(.horizontal, 21)
                    .padding(.top, 16)
                }

                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: 14) {
                        if isLoadingStops {
                            ProgressView()
                                .tint(DS.Color.inkMute)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else if hasLoadedStops && stops.isEmpty {
                            Text("Aucun arrêt disponible")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.inkMute)
                                .frame(maxWidth: .infinity)
                                .padding(.top, 40)
                        } else {
                            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                                Button {
                                    Task { await loadStopDetail(for: stop) }
                                } label: {
                                    LineOverviewStopRow(
                                        stop: stop,
                                        isFirst: index == 0,
                                        isLast: index == stops.count - 1
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }

                        if !lineIncidents.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Confirmations terrain")
                                    .font(DS.Font.displayH3)
                                    .foregroundStyle(DS.Color.ink)

                                ForEach(lineIncidents.prefix(3)) { incident in
                                    TransportIncidentCommunityCard(incident: incident)
                                }
                            }
                            .padding(.top, 8)
                        }
                    }
                    .padding(.horizontal, 21)
                    .padding(.top, 18)
                    .padding(.bottom, 28)
                }
            }
        }
        .modifier(PaperGrainBackground())
        .overlay {
            if let selectedStopDetail {
                TransportStopDetailOverlay(
                    stopDetail: selectedStopDetail,
                    isLoading: isLoadingStopDetail,
                    onDismiss: { self.selectedStopDetail = nil }
                )
            }
        }
        .task {
            await loadTransportLineDetail()
            if transportLine == nil {
                await loadRemoteStops()
            }
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onBack) {
                HStack(spacing: 8) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 18, weight: .semibold))

                    Text("Lignes")
                        .font(DS.Font.bodyBold)
                }
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 16)
                .frame(height: 42)
                .background(DS.Color.paper)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
            .shadow(DS.Shadow.raised)

            Spacer()

            HStack(spacing: 18) {
                Image(systemName: "bell")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(DS.Color.ink)

                Image(systemName: "heart")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(DS.Color.ink)
            }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 18) {
            topBar

            VStack(alignment: .leading, spacing: 12) {
                Text("Desk ligne")
                    .eyebrow()

                HStack(spacing: 16) {
                    LineBadge(
                        line: line.line,
                        size: .lg,
                        fill: line.lineColor,
                        foreground: line.lineTextColor
                    )
                    .frame(width: 54, height: 46)

                    HStack(spacing: 0) {
                        routePill(text: routeOriginText, isLeading: true)

                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.35))
                            .frame(width: 14, height: 1)

                        routePill(text: routeDestinationText, isLeading: false)
                    }
                    .frame(maxWidth: .infinity)
                }

                if availableVariants.count > 1 {
                    HStack(spacing: 10) {
                        ForEach(availableVariants) { variant in
                            Button {
                                withAnimation(DS.Motion.easeIOS) {
                                    selectedVariant = variant
                                }
                            } label: {
                                Text(variant.label)
                                    .font(DS.Font.eyebrow)
                                    .tracking(1.2)
                                    .foregroundStyle(DS.Color.ink)
                                    .padding(.horizontal, 14)
                                    .frame(height: 34)
                                    .background(selectedVariant == variant ? DS.Color.secondary : Color.clear)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(selectedVariant == variant ? DS.Color.ink.opacity(0.28) : DS.Color.border, lineWidth: 1)
                                    )
                            }
                            .buttonStyle(.plain)
                        }

                        Spacer()
                    }
                }
            }
        }
    }

    private func routePill(text: String, isLeading: Bool) -> some View {
        Text(text)
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.ink)
            .lineLimit(2)
            .multilineTextAlignment(isLeading ? .leading : .center)
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity, minHeight: 50, alignment: isLeading ? .leading : .center)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
    }

    private var routeSummary: some View {
        HStack(spacing: 10) {
            overviewMetric(text: "\(stops.count) arrêts", icon: "mappin.and.ellipse")
            overviewMetric(text: "\(line.reportsCount) reports", icon: "exclamationmark.bubble")
            if availableVariants.count > 1 {
                overviewMetric(text: selectedVariant.label, icon: "arrow.left.arrow.right")
            }
        }
    }

    private func overviewMetric(text: String, icon: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
            Text(text)
                .font(DS.Font.eyebrow)
                .tracking(1.0)
        }
        .foregroundStyle(DS.Color.ink)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(DS.Color.secondary)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }

    @MainActor
    private func loadRemoteStops() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingStops else { return }
        isLoadingStops = true
        defer { isLoadingStops = false; hasLoadedStops = true }

        do {
            let arrets = try await SignalementService.arretsParLigne(line.line)
            remoteStops = try await withThrowingTaskGroup(of: LineOverviewStop.self) { group in
                for arret in arrets {
                    group.addTask {
                        let response = try await SignalementService.parLigneEtArret(ligne: line.line, arretId: arret.id, page: 1, limit: 10)
                        let reportsCount = response.signalements.count
                        let status: LineHealthStatus = reportsCount >= 6 ? .critical : (reportsCount >= 3 ? .disrupted : .fluid)
                        return LineOverviewStop(
                            backendId: arret.id,
                            stopId: arret.stopId,
                            name: arret.nom,
                            connections: (arret.lignesDesservies ?? [line.line]).prefix(6).map {
                                LineConnectionBadge(
                                    label: $0,
                                    color: line.lineColor,
                                    textColor: line.lineTextColor,
                                    fontSize: 10
                                )
                            },
                            nextPassages: Self.formattedNextPassages(for: arret),
                            status: status,
                            reportsCount: reportsCount,
                            confidenceText: response.signalements.compactMap { $0.community?.confidence }.max().map {
                                let value = Int(($0 * 100).rounded())
                                return "\(value)% fiable"
                            },
                            fallbackColor: line.lineColor,
                            fallbackTextColor: line.lineTextColor
                        )
                    }
                }

                var mapped: [LineOverviewStop] = []
                for try await stop in group {
                    mapped.append(stop)
                }
                return mapped.sorted(by: { lhs, rhs in
                    lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                })
            }
        } catch {
            print("LineOverview remote stops failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadTransportLineDetail() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingStops else { return }
        isLoadingStops = true
        defer { isLoadingStops = false; hasLoadedStops = true }

        async let cityTask: TransportLineDTO? = try? await TransportService.line(id: "\(line.line):City")
        async let suburbTask: TransportLineDTO? = try? await TransportService.line(id: "\(line.line):Suburb")
        async let baseTask: TransportLineDTO? = try? await TransportService.line(id: line.line)

        let city = await cityTask
        let suburb = await suburbTask
        let base = await baseTask

        cityLine = city
        suburbLine = suburb
        baseLineDetail = base

        if city != nil {
            selectedVariant = .city
        } else if suburb != nil {
            selectedVariant = .suburb
        }

        if city == nil && suburb == nil && base == nil {
            print("Transport line detail failed: no line variant available")
        }
    }

    @MainActor
    private func loadStopDetail(for stop: LineOverviewStop) async {
        guard let stopIdentifier = stop.stopId ?? stop.backendId else { return }
        isLoadingStopDetail = true
        defer { isLoadingStopDetail = false }

        do {
            selectedStopDetail = try await TransportService.stop(id: stopIdentifier)
        } catch {
            print("Transport stop detail failed: \(error.localizedDescription)")
        }
    }

    private static func stops(
        from lineDetail: TransportLineDTO,
        fallbackColor: Color,
        fallbackTextColor: Color
    ) -> [LineOverviewStop] {
        let departureText = lineDetail.nextDepartures
            .prefix(3)
            .map { "\($0.minutes)" }
            .joined(separator: ", ")
        let formattedDeparture = departureText.isEmpty ? "--" : "\(departureText) min"

        return lineDetail.line.stops.map { stop in
            let incidents = lineDetail.activeIncidents.filter {
                $0.stop?.id == stop.id || $0.stop?.name == stop.name
            }
            let severity = incidents
                .compactMap(\.severity)
                .max { severityRank($0) < severityRank($1) } ?? lineDetail.severity

            return LineOverviewStop(
                backendId: stop.id,
                stopId: stop.stopId,
                name: stop.name,
                connections: [
                    LineConnectionBadge(
                        label: lineDetail.line.lineId,
                        color: Color(hex: lineDetail.line.color),
                        textColor: lineDetail.line.color.lowercased() == "#ffdc01" ? .black : .white,
                        fontSize: 10
                    )
                ],
                nextPassages: formattedDeparture,
                status: status(from: severity),
                reportsCount: incidents.count,
                confidenceText: confidenceLabel(lineDetail.confidence),
                fallbackColor: fallbackColor,
                fallbackTextColor: fallbackTextColor
            )
        }
    }

    private static func status(from severity: String) -> LineHealthStatus {
        switch severity {
        case "critical": return .critical
        case "major", "minor": return .disrupted
        default: return .fluid
        }
    }

    private static func severityRank(_ severity: String) -> Int {
        switch severity {
        case "critical": return 4
        case "major": return 3
        case "minor": return 2
        default: return 1
        }
    }

    private static func confidenceLabel(_ confidence: Double) -> String {
        let value = Int((confidence * 100).rounded())
        switch value {
        case 85...: return "Très sûr"
        case 65...: return "Assez sûr"
        default: return "Faible confirmation"
        }
    }

    nonisolated private static func formattedNextPassages(for arret: ArretDTO) -> String {
        if let nextPassages = arret.nextPassages, !nextPassages.isEmpty {
            return nextPassages
                .prefix(3)
                .map { "\($0)" }
                .joined(separator: ", ") + " min"
        }

        if let nextPassageMinutes = arret.nextPassageMinutes {
            return "\(nextPassageMinutes) min"
        }

        return "--"
    }
}

private struct LineOverviewStopRow: View {
    let stop: LineOverviewStop
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            ZStack {
                VStack(spacing: 0) {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.18))
                        .frame(width: 2)
                        .opacity(isFirst ? 0 : 1)

                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.18))
                        .frame(width: 2)
                        .opacity(isLast ? 0 : 1)
                }

                Circle()
                    .fill(isFirst ? DS.Color.paper : DS.Color.ink)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.paper, lineWidth: 3)
                    )
                    .frame(width: 18, height: 18)
            }
            .frame(width: 18)

            LineOverviewStopCard(stop: stop)
        }
    }
}

private struct LineOverviewStopCard: View {
    let stop: LineOverviewStop

    private var statusColor: Color {
        switch stop.status {
        case .fluid: return DS.Color.statusOK
        case .disrupted: return DS.Color.statusMajor
        case .critical: return DS.Color.statusCritical
        }
    }

    var body: some View {
        DS.PaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .top) {
                    Text(stop.name)
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 2) {
                        Text("Prochain passage")
                            .eyebrow()

                        Text(stop.nextPassages)
                            .font(DS.Font.mono)
                            .foregroundStyle(DS.Color.ink)
                            .multilineTextAlignment(.trailing)
                    }
                }

                FlowLayout(horizontalSpacing: 4, verticalSpacing: 4) {
                    ForEach(stop.connections) { connection in
                        Text(connection.label)
                            .font(.system(size: connection.fontSize, weight: .bold, design: .monospaced))
                            .foregroundStyle(connection.textColor)
                            .frame(minWidth: 20, minHeight: 20)
                            .padding(.horizontal, 4)
                            .background(connection.color)
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                }

                HStack(spacing: 6) {
                    Image(systemName: "arrow.turn.down.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)

                    Circle()
                        .fill(statusColor)
                        .frame(width: 12, height: 12)

                    Text("\(stop.status.label) – \(stop.reportsCount) signalements")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkSoft)
                }

                if let confidenceText = stop.confidenceText {
                    Text(confidenceText)
                        .font(DS.Font.eyebrow)
                        .tracking(1.0)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
        }
    }
}

private struct TransportLineSnapshotCard: View {
    let line: TransportLineDTO
    let alternatives: [TransportAlternativeDTO]

    private var confidenceText: String {
        let score = Int((line.confidence * 100).rounded())
        switch score {
        case 85...: return "Très sûr"
        case 65...: return "Assez sûr"
        default: return "Faible confirmation"
        }
    }

    var body: some View {
        DS.PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Synthèse temps réel")
                            .eyebrow()
                        Text(TransportViewAdapters.localizedSeverityLabel(severity: line.severity, fallback: line.label?.fr))
                            .font(DS.Font.displayH3)
                            .foregroundStyle(DS.Color.ink)
                    }

                    Spacer()

                    DS.StatusPill(confidenceText, level: .ok)
                }

                Text("\(line.activeIncidents.count) incidents actifs • \(line.nextDepartures.prefix(2).map { "\($0.line) \($0.minutes) min" }.joined(separator: " • "))")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)

                if let alternative = alternatives.first {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alternative immédiate")
                            .sectionTitle()

                        Text(alternative.explanationDetails?.summary ?? alternative.explanation)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct TransportStopDetailOverlay: View {
    let stopDetail: TransportStopDTO
    let isLoading: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            DS.Color.ink.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack {
                Spacer()

                DS.PaperCard {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(alignment: .top) {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Arrêt")
                                    .eyebrow()
                                Text(stopDetail.stop.name)
                                    .font(DS.Font.displayH3)
                                    .foregroundStyle(DS.Color.ink)

                                Text(TransportViewAdapters.localizedSeverityLabel(severity: stopDetail.severity, fallback: stopDetail.label?.fr))
                                    .font(DS.Font.bodySmall)
                                    .foregroundStyle(DS.Color.inkMute)
                            }

                            Spacer()

                            Button(action: onDismiss) {
                                Image(systemName: "xmark")
                                    .foregroundStyle(DS.Color.ink)
                                    .frame(width: 30, height: 30)
                                    .background(DS.Color.secondary)
                                    .clipShape(Circle())
                            }
                            .buttonStyle(.plain)
                        }

                        if isLoading {
                            ProgressView()
                                .tint(DS.Color.ink)
                        }

                        if !stopDetail.nextDepartures.isEmpty {
                            Text(stopDetail.nextDepartures.prefix(3).map { "\($0.line) \($0.minutes) min" }.joined(separator: " • "))
                                .font(DS.Font.monoLarge)
                                .foregroundStyle(DS.Color.ink)
                        }

                        if !stopDetail.recommendedAlternatives.isEmpty {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Alternative recommandée")
                                    .sectionTitle()
                                Text(stopDetail.recommendedAlternatives[0].explanationDetails?.summary ?? stopDetail.recommendedAlternatives[0].explanation)
                                    .font(DS.Font.bodySmall)
                                    .foregroundStyle(DS.Color.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                        }

                        if !stopDetail.activeIncidents.isEmpty {
                            VStack(alignment: .leading, spacing: 10) {
                                Text("Confirmations terrain")
                                    .font(DS.Font.displayH3)
                                    .foregroundStyle(DS.Color.ink)

                                ForEach(stopDetail.activeIncidents.prefix(3)) { incident in
                                    TransportIncidentCommunityCard(incident: incident)
                                }
                            }
                        }
                    }
                }
                .shadow(DS.Shadow.overlay)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
        }
    }
}

private struct TransportIncidentCommunityCard: View {
    let incident: TransportIncidentDTO
    @State private var community: SignalementCommunityDTO?
    @State private var isSubmitting = false
    @State private var showConfidenceExplanation = false

    private var effectiveCommunity: SignalementCommunityDTO? { community ?? incident.community }
    private var isStale: Bool { (effectiveCommunity?.freshnessMinutes ?? 0) >= 120 }
    private var freshnessLabel: String? {
        guard let freshness = effectiveCommunity?.freshnessMinutes else { return nil }
        if freshness < 1 { return "Signalé à l'instant" }
        if freshness < 60 { return "Signalé il y a \(freshness) min" }
        return "Signalé il y a \(freshness / 60) h"
    }
    private var confirmationsSummary: String? {
        guard let community = effectiveCommunity else { return nil }
        let confirmations = community.confirmations ?? 0
        guard confirmations > 0, let freshness = community.freshnessMinutes else { return nil }
        let window = freshness < 60 ? "\(freshness) min" : "\(freshness / 60) h"
        return "Confirmé \(confirmations)× en \(window)"
    }

    var body: some View {
        DS.PaperCard {
            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .top, spacing: 8) {
                    Text(incident.line ?? "STIB")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.primaryForeground)
                        .frame(minWidth: 34, minHeight: 28)
                        .background(DS.Color.accent)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                    VStack(alignment: .leading, spacing: 4) {
                        Text(incident.type ?? "Signalement")
                            .font(DS.Font.displayH3)
                            .foregroundStyle(DS.Color.ink)

                        Text(incident.description ?? "Incident actif sur cette ligne.")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    communityBadge(incident.sourceLabel, fill: incident.sourceLabel.contains("STIB") ? DS.Color.accent : DS.Color.ink, textColor: incident.sourceLabel.contains("STIB") ? DS.Color.primaryForeground : DS.Color.primaryForeground)
                    if let freshnessLabel {
                        communityBadge(freshnessLabel, fill: DS.Color.secondary, textColor: DS.Color.ink)
                    }
                    if isStale {
                        communityBadge("Plus récent ?", fill: DS.Color.paper2, textColor: DS.Color.ink)
                    }
                }

                if let community = effectiveCommunity {
                    HStack(spacing: 8) {
                        communityBadge("\(community.confirmations ?? 0) confirm.", fill: DS.Color.ink)
                        communityBadge("\(community.stillBlocked ?? 0) bloqué", fill: DS.Color.statusMajor)
                        communityBadge("\(community.resolved ?? 0) résolu", fill: DS.Color.statusOK, textColor: DS.Color.primaryForeground)
                        if let confirmationsSummary {
                            communityBadge(confirmationsSummary, fill: DS.Color.secondary, textColor: DS.Color.ink)
                        }
                    }

                    if let confidenceLabel = incident.confidenceLabel {
                        Button {
                            showConfidenceExplanation = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(confidenceLabel)
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(DS.Font.bodySmall.weight(.semibold))
                            .foregroundStyle(DS.Color.inkMute)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if incident.id != "unknown" {
                    HStack(spacing: 8) {
                        actionButton("Je confirme", action: { await apply(.confirm) })
                        actionButton("Toujours bloqué", fill: DS.Color.statusMajor, action: { await apply(.stillBlocked) })
                        actionButton("C'est résolu", fill: DS.Color.statusOK, textColor: DS.Color.primaryForeground, action: { await apply(.resolved) })
                    }
                    .opacity(isSubmitting ? 0.6 : 1)
                }
            }
        }
        .opacity(isStale ? 0.72 : 1)
        .alert("Pourquoi cette confiance ?", isPresented: $showConfidenceExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(incident.confidenceExplanation)
        }
        .task { community = incident.community }
    }

    private func communityBadge(_ text: String, fill: Color, textColor: Color = .white) -> some View {
        Text(text)
            .font(DS.Font.bodySmall.weight(.semibold))
            .foregroundStyle(textColor)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(fill)
            .clipShape(Capsule())
    }

    private func actionButton(
        _ title: String,
        fill: Color = DS.Color.ink,
        textColor: Color = .white,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(DS.Font.bodySmall.weight(.semibold))
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
    private func apply(_ action: CommunityAction) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response: SignalementCommunityActionResponse
            switch action {
            case .confirm:
                response = try await SignalementService.confirmer(signalementId: incident.id)
            case .stillBlocked:
                response = try await SignalementService.toujoursBloque(signalementId: incident.id)
            case .resolved:
                response = try await SignalementService.resoudre(signalementId: incident.id)
            }
            community = response.community ?? community
        } catch {
            print("Incident community action failed: \(error.localizedDescription)")
        }
    }

    private enum CommunityAction {
        case confirm
        case stillBlocked
        case resolved
    }
}

private struct LineOverviewMetricLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 6) {
            configuration.icon
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.white)

            configuration.title
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
        }
    }
}

private struct FlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

enum LineFilter: CaseIterable, Identifiable {
    case all
    case tram
    case bus
    case metro

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "Toutes"
        case .tram: return "Tram"
        case .bus: return "Bus"
        case .metro: return "Métro"
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .metro: return "tram.fill.tunnel"
        }
    }

    static func from(line: String) -> LineFilter {
        if ["1", "2", "5", "6"].contains(line) { return .metro }
        if let numeric = Int(line), numeric >= 90 { return .bus }
        return .tram
    }

    static func from(typeTransport: String?) -> LineFilter {
        switch typeTransport?.lowercased() {
        case "métro", "metro": return .metro
        case "tram": return .tram
        case "bus": return .bus
        default: return .all
        }
    }
}

enum LineHealthStatus {
    case fluid
    case disrupted
    case critical

    var label: String {
        switch self {
        case .fluid: return "Fluide"
        case .disrupted: return "Perturbé"
        case .critical: return "Critique"
        }
    }
}

struct LineStatusItem: Identifiable {
    let id = UUID()
    let line: String
    let lineColor: Color
    let lineTextColor: Color
    let origin: String
    let destination: String
    let direction: String
    let status: LineHealthStatus
    let reportsCount: Int
    let filter: LineFilter
    let confidenceText: String?
}

struct LineOverviewStop: Identifiable {
    let id = UUID()
    let backendId: String?
    let stopId: String?
    let name: String
    let connections: [LineConnectionBadge]
    let nextPassages: String
    let status: LineHealthStatus
    let reportsCount: Int
    let confidenceText: String?
    let fallbackColor: Color?
    let fallbackTextColor: Color?
}

struct LineConnectionBadge: Identifiable {
    let id = UUID()
    let label: String
    let color: Color
    let textColor: Color
    let fontSize: CGFloat
}

enum LineStatusMockData {
    static let availableCount = 82

    static let all: [LineStatusItem] = [
        .init(line: "1", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, origin: "Gare de l'ouest", destination: "Stokkel", direction: "Gare de l’ouest → Stokkel", status: .fluid, reportsCount: 2, filter: .metro, confidenceText: "92% fiable"),
        .init(line: "2", lineColor: Color(hex: "#ED7807"), lineTextColor: .white, origin: "Simonis", destination: "Elisabeth", direction: "Simonis → Elisabeth", status: .disrupted, reportsCount: 9, filter: .metro, confidenceText: "78% fiable"),
        .init(line: "4", lineColor: Color(hex: "#EA4F80"), lineTextColor: .white, origin: "Gare du Nord", destination: "Stalle", direction: "Gare du Nord → Stalle", status: .fluid, reportsCount: 2, filter: .tram, confidenceText: "88% fiable"),
        .init(line: "5", lineColor: Color(hex: "#F9A611"), lineTextColor: .white, origin: "Erasme", destination: "Herrmann-Debroux", direction: "Erasme → Herrmann-Debroux", status: .disrupted, reportsCount: 17, filter: .metro, confidenceText: "71% fiable"),
        .init(line: "6", lineColor: Color(hex: "#0066A3"), lineTextColor: .white, origin: "Roi Baudouin", destination: "Elisabeth", direction: "Roi Baudouin → Elisabeth", status: .disrupted, reportsCount: 9, filter: .metro, confidenceText: "74% fiable"),
        .init(line: "7", lineColor: Color(hex: "#EFE048"), lineTextColor: .black, origin: "Vanderkindere", destination: "Heysel", direction: "Vanderkindere → Heysel", status: .critical, reportsCount: 53, filter: .tram, confidenceText: "58% fiable"),
        .init(line: "8", lineColor: Color(hex: "#378BFF"), lineTextColor: .white, origin: "Louise", destination: "Roodebeek", direction: "Louise → Roodebeek", status: .critical, reportsCount: 22, filter: .bus, confidenceText: "63% fiable"),
        .init(line: "9", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, origin: "Montgomery", destination: "Simonis", direction: "Montgomery → Simonis", status: .fluid, reportsCount: 4, filter: .tram, confidenceText: "90% fiable"),
        .init(line: "10", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, origin: "Rogier", destination: "Churchill", direction: "Rogier → Churchill", status: .fluid, reportsCount: 1, filter: .tram, confidenceText: "94% fiable")
    ]
}
