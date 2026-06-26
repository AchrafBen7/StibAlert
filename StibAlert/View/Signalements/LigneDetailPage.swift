import SwiftUI

@MainActor
final class LigneDetailViewModel: ObservableObject {
    enum DirectionVariant: String, CaseIterable, Identifiable {
        case city = "City"
        case suburb = "Suburb"
        case base = "Base"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .city: return "City"
            case .suburb: return "Suburb"
            case .base: return "Base"
            }
        }
    }

    struct StopSnapshot: Identifiable {
        let id: String
        let backendId: String?
        let stopId: String?
        let name: String
        let waits: [Int]
        let waitsSource: String?
        let disruption: String?
        let incidentType: String?
        let disruptionSeverity: String?
        let reportsCount: Int
        let delayMinutes: Int?
        /// True when a live vehicle of the active direction is currently
        /// reported at (or approaching) this stop — drives the filled
        /// timeline dot + "à quai" indicator.
        let vehiclePresent: Bool
    }

    let line: LineStatusItem

    @Published var cityLine: TransportLineDTO?
    @Published var suburbLine: TransportLineDTO?
    @Published var baseLine: TransportLineDTO?
    @Published var stopCatalog: [ArretDTO] = []
    @Published var selectedVariant: DirectionVariant = .city
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var isFollowed = false
    /// Community reports scoped to this line, filtered to live confidence ≥
    /// 0.18 (matches the rest of the app's expiry threshold). Drives the
    /// warning markers next to affected stops in the timeline.
    @Published var lineSignalements: [SignalementDTO] = []
    /// Global perturbation summary fetched from the overview — used as a
    /// fallback in the "Officiel" sub-tab when a line was flagged in the
    /// grid via `summary.affectedLines` but had no concrete entry in its
    /// own `activeIncidents` array. Without this, the tab said "Pas d'info
    /// officielle" even though the badge in the grid was active.
    @Published var matchingGlobalSummary: TransportPerturbationSummaryDTO?
    /// Live vehicles for this line, fetched from the enriched
    /// `vehicle-positions-map` endpoint (each carries `stopNom` + coords).
    /// Drives the filled "tram is here" dot in the timeline.
    @Published var lineVehicles: [TransportVehicleDTO] = []

    init(line: LineStatusItem) {
        self.line = line
    }

    var activeLine: TransportLineDTO? {
        switch selectedVariant {
        case .city:
            return cityLine ?? suburbLine ?? baseLine
        case .suburb:
            return suburbLine ?? cityLine ?? baseLine
        case .base:
            return baseLine ?? cityLine ?? suburbLine
        }
    }

    var availableVariants: [DirectionVariant] {
        var values: [DirectionVariant] = []
        if cityLine != nil { values.append(.city) }
        if suburbLine != nil { values.append(.suburb) }
        if values.isEmpty, baseLine != nil { values.append(.base) }
        return values.isEmpty ? [.base] : values
    }

    var destinationsLabel: String {
        let labels = availableVariants.compactMap { variantDestination($0) }
        let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? labels
        if unique.count >= 2 {
            return "\(unique[0]) ⇄ \(unique[1])"
        }
        return unique.first ?? activeLine?.line.name ?? line.direction
    }

    var routeSubtitle: String {
        let stopsCount = orderedStops.count
        if orderedStops.contains(where: { $0.disruption != nil }) {
            let count = orderedStops.filter { $0.disruption != nil }.count
            return "\(stopsCount) arrêts · \(count) perturbation\(count > 1 ? "s" : "")"
        }
        return "\(stopsCount) arrêts · temps réel STIB"
    }

    /// Normalised stop keys where a live vehicle of this line is currently
    /// reported, matched via the backend's `stopNom`. STIB's per-vehicle
    /// `directionId` is opaque (the home screen literally has to *learn*
    /// which destination each id maps to), so we don't split City vs Suburb
    /// here — every tram/bus on the line lights up the stop it's at. On a
    /// shared timeline that still answers "où sont les véhicules maintenant".
    var occupiedStopKeys: Set<String> {
        var keys: Set<String> = []
        for vehicle in lineVehicles {
            guard let nom = vehicle.stopNom, !nom.isEmpty else { continue }
            keys.insert(nom.normalizedStopKey)
        }
        return keys
    }

    var orderedStops: [StopSnapshot] {
        if let activeLine {
            let byStopId = stopCatalog.reduce(into: [String: ArretDTO]()) { result, dto in
                guard let stopId = dto.stopId, result[stopId] == nil else { return }
                result[stopId] = dto
            }
            let byBackendId = stopCatalog.reduce(into: [String: ArretDTO]()) { result, dto in
                guard result[dto.id] == nil else { return }
                result[dto.id] = dto
            }
            let byName = stopCatalog.reduce(into: [String: ArretDTO]()) { result, dto in
                let key = dto.nom.normalizedStopKey
                guard result[key] == nil else { return }
                result[key] = dto
            }

            let occupied = occupiedStopKeys
            return activeLine.line.stops.map { stop in
                let catalog = stop.stopId.flatMap { byStopId[$0] }
                    ?? byBackendId[stop.id]
                    ?? byName[stop.name.normalizedStopKey]
                return makeSnapshot(from: stop, catalog: catalog, lineDetail: activeLine, occupiedKeys: occupied)
            }
        }

        return stopCatalog.map { dto in
            StopSnapshot(
                id: dto.stopId ?? dto.id,
                backendId: dto.id,
                stopId: dto.stopId,
                name: dto.nom,
                waits: dto.nextPassages ?? dto.nextPassageMinutes.map { [$0] } ?? [],
                waitsSource: dto.nextPassageSource,
                disruption: nil,
                incidentType: nil,
                disruptionSeverity: nil,
                reportsCount: 0,
                delayMinutes: dto.delayMinutes,
                vehiclePresent: false
            )
        }
    }

    var summaryTitle: String {
        TransportViewAdapters.localizedSeverityLabel(
            severity: activeLine?.severity,
            fallback: activeLine?.label?.fr
        )
    }

    var summaryDetails: String {
        guard let activeLine else { return "Chargement des données de ligne…" }
        let departures = activeLine.nextDepartures.prefix(3).map {
            let minutes = $0.minutes <= 0 ? "Imminent" : "\($0.minutes) min"
            return "\(minutes)\($0.source == "scheduled" ? " · prévu" : " · temps réel")"
        }
        if departures.isEmpty {
            return "Aucun prochain départ fiable pour cette direction."
        }
        return departures.joined(separator: " • ")
    }

    var alternativeSummary: String? {
        activeLine?.recommendedAlternatives.first?.localizedExplanationDetails?.summary
            ?? activeLine?.recommendedAlternatives.first?.explanation
    }

    func load() async {
        await fetch(resetVariant: true)
    }

    /// Manual pull triggered by the header refresh button. Re-fetches every
    /// source (lines, stops, vehicles, signalements) but keeps the direction
    /// the user is currently looking at instead of snapping back to City.
    func refresh() async {
        await fetch(resetVariant: false)
    }

    private func fetch(resetVariant: Bool) async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        let previousVariant = selectedVariant

        async let cityTask: TransportLineDTO? = try? await TransportService.line(id: "\(line.line):City")
        async let suburbTask: TransportLineDTO? = try? await TransportService.line(id: "\(line.line):Suburb")
        async let baseTask: TransportLineDTO? = try? await TransportService.line(id: line.line)
        async let stopsTask: [ArretDTO]? = try? await SignalementService.arretsParLigne(line.line)
        async let signalementsTask: [SignalementDTO]? = try? await SignalementService.liste()
        // Fallback: if the global overview lists this line under
        // `affectedLines`, surface its summary in the "Officiel" tab even
        // when `activeLine.activeIncidents` is empty.
        async let overviewTask: TransportOverviewDTO? = try? await TransportService.overview()
        // Live vehicle snapshot — the enriched map endpoint is the only one
        // that returns `stopNom`, so we use it (not `activeLine.vehicles`).
        async let vehiclesTask: [TransportVehicleDTO] = VehicleTrackingService.snapshot(lines: [line.line])

        // Les perturbations de la ligne sont CE QUE l'utilisateur vient voir
        // dans l'onglet "Infos trafic". On les résout EN PREMIER pour qu'elles
        // s'affichent dès qu'elles arrivent, sans attendre lignes / véhicules /
        // overview : toutes les requêtes tournent déjà en parallèle (async let),
        // on ne fait que lire les résultats dans l'ordre le plus utile. Comme
        // l'onglet Infos trafic n'est pas gated par `isLoading`, l'affectation
        // de `lineSignalements` déclenche l'affichage des cartes immédiatement.
        let normalisedLine = line.line.uppercased()
        lineSignalements = (await signalementsTask ?? []).filter { s in
            guard s.status != "resolved", s.liveConfidence >= 0.18 else { return false }
            return s.ligne.uppercased() == normalisedLine
        }

        cityLine = await cityTask
        suburbLine = await suburbTask
        baseLine = await baseTask
        stopCatalog = await stopsTask ?? []
        lineVehicles = await vehiclesTask

        if let overview = await overviewTask {
            let normalisedLineGlobal = line.line.uppercased()
            if let summary = overview.perturbationSummary,
               summary.affectedLines.contains(where: { $0.uppercased() == normalisedLineGlobal }) {
                matchingGlobalSummary = summary
            } else {
                matchingGlobalSummary = nil
            }
        }

        if resetVariant {
            if cityLine != nil {
                selectedVariant = .city
            } else if suburbLine != nil {
                selectedVariant = .suburb
            } else {
                selectedVariant = .base
            }
        } else if availableVariants.contains(previousVariant) {
            // Keep the user on the direction they were viewing.
            selectedVariant = previousVariant
        }

        if cityLine == nil && suburbLine == nil && baseLine == nil && stopCatalog.isEmpty {
            loadError = "Pas de données disponibles pour cette ligne."
        }
    }

    /// Stop names (normalised, uppercase) that currently host one or more
    /// active community signalements on this line. Drives the "⚠" badge
    /// shown next to the stop name in the timeline.
    var reportedStopNamesByKey: Set<String> {
        var seen: Set<String> = []
        for s in lineSignalements {
            if case .populated(let arret) = s.arretId {
                seen.insert(arret.nom.normalizedStopKey)
            }
        }
        return seen
    }

    /// Number of active community reports for a given stop name. Drives
    /// the badge count.
    func communityReportCount(forStopName name: String) -> Int {
        let key = name.normalizedStopKey
        return lineSignalements.reduce(0) { acc, s in
            if case .populated(let arret) = s.arretId,
               arret.nom.normalizedStopKey == key {
                return acc + 1
            }
            return acc
        }
    }

    func toggleDirection() {
        let values = availableVariants
        guard values.count > 1, let currentIndex = values.firstIndex(of: selectedVariant) else { return }
        selectedVariant = values[(currentIndex + 1) % values.count]
    }

    func selectVariant(_ variant: DirectionVariant) {
        guard availableVariants.contains(variant) else { return }
        selectedVariant = variant
    }

    private func variantDestination(_ variant: DirectionVariant) -> String? {
        let candidate: TransportLineDTO?
        switch variant {
        case .city: candidate = cityLine
        case .suburb: candidate = suburbLine
        case .base: candidate = baseLine
        }
        return candidate?.line.stops.last?.name
    }

    private func makeSnapshot(
        from stop: TransportLineStopDTO,
        catalog: ArretDTO?,
        lineDetail: TransportLineDTO,
        occupiedKeys: Set<String>
    ) -> StopSnapshot {
        let incidents = lineDetail.activeIncidents.filter {
            $0.stop?.id == stop.id
            || $0.stop?.id == catalog?.id
            || $0.stop?.id == catalog?.stopId
            || $0.stop?.name?.normalizedStopKey == stop.name.normalizedStopKey
        }

        let disruption = incidents.first?.description
            ?? incidents.first?.type

        let waits = catalog?.nextPassages ?? catalog?.nextPassageMinutes.map { [$0] } ?? []

        // A live vehicle is "at" this stop when the map endpoint reports a
        // vehicle whose `stopNom` matches this stop (precomputed into
        // `occupiedKeys` so we don't rescan the vehicle list per stop).
        let vehiclePresent = occupiedKeys.contains(stop.name.normalizedStopKey)

        return StopSnapshot(
            id: stop.stopId ?? stop.id,
            backendId: catalog?.id ?? stop.id,
            stopId: catalog?.stopId ?? stop.stopId,
            name: stop.name,
            waits: waits.sorted(),
            waitsSource: catalog?.nextPassageSource,
            disruption: disruption,
            incidentType: incidents.first?.type,
            disruptionSeverity: incidents.first?.severity,
            reportsCount: incidents.count,
            delayMinutes: catalog?.delayMinutes,
            vehiclePresent: vehiclePresent
        )
    }
}

struct LigneDetailPage: View {
    /// Top-level mode: timeline of stops, or the new infos-trafic overview
    /// (status icon + 3 sub-tabs for community / official / social).
    enum DetailTab: Hashable { case stops, traffic }
    /// Filters inside the Infos trafic tab. "Social" is a placeholder until
    /// we wire a Twitter/X search; today it shows a "bientôt" empty state.
    enum TrafficSubtab: Hashable { case live, upcoming, social }

    @StateObject private var viewModel: LigneDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AuthSession

    @State private var selectedStopForDetail: LigneDetailViewModel.StopSnapshot?
    @State private var selectedTab: DetailTab
    @State private var selectedTrafficSubtab: TrafficSubtab = .live
    @Namespace private var tabUnderlineNamespace

    private let onBackOverride: (() -> Void)?
    /// Incidents officiels que la grille Verkeersinfo a utilisés pour BADGER
    /// cette ligne. On les passe au détail pour garantir « badge ⟺ détail
    /// visible » : sans ça, l'overview réseau badgeait (ex. travaux ligne 1)
    /// mais le fetch par ligne renvoyait `activeIncidents` vide → page « Pas
    /// d'info officielle ». On les fusionne avec ce que le fetch ramène.
    private let seedOfficialIncidents: [TransportIncidentDTO]

    init(lineId: String, initialTab: DetailTab = .stops, seedOfficialIncidents: [TransportIncidentDTO] = []) {
        let fallback = LigneDetailPage.makeFallbackLine(lineId: lineId)
        _viewModel = StateObject(wrappedValue: LigneDetailViewModel(line: fallback))
        self.onBackOverride = nil
        self.seedOfficialIncidents = seedOfficialIncidents
        self._selectedTab = State(initialValue: initialTab)
    }

    init(line: LineStatusItem, initialTab: DetailTab = .stops, seedOfficialIncidents: [TransportIncidentDTO] = [], onBack: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: LigneDetailViewModel(line: line))
        self.onBackOverride = onBack
        self.seedOfficialIncidents = seedOfficialIncidents
        self._selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .modifier(PaperGrainBackground())
        .task {
            await viewModel.load()
        }
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedStopForDetail) { stop in
            LigneStopDetailSheet(stop: stop)
                .environmentObject(session)
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.md) {
            HStack {
                Button(action: goBack) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Lignes")
                            .font(DS.Font.bodyBold)
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(height: 40)
                    .background(DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .shadow(DS.Shadow.raised)

                Spacer()

                refreshButton

                Button {
                    viewModel.isFollowed.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isFollowed ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .bold))
                        Text("Suivre")
                            .font(DS.Font.bodySmall.weight(.semibold))
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 36)
                    .background(DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.md)
    }

    /// Circular refresh control — re-pulls live passages + vehicle positions
    /// while keeping the current direction. The icon spins continuously
    /// while a fetch is in flight.
    private var refreshButton: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await viewModel.refresh() }
        } label: {
            Image(systemName: "arrow.clockwise")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 36, height: 36)
                .background(DS.Color.paper)
                .overlay(
                    Circle().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .clipShape(Circle())
                .rotationEffect(.degrees(viewModel.isLoading ? 360 : 0))
                .animation(
                    viewModel.isLoading
                        ? .linear(duration: 0.8).repeatForever(autoreverses: false)
                        : .default,
                    value: viewModel.isLoading
                )
        }
        .buttonStyle(.plain)
        .disabled(viewModel.isLoading)
        .accessibilityLabel("Rafraîchir les horaires")
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            identifierBlock

            primaryTabSwitcher

            switch selectedTab {
            case .stops:
                // Direction toggle only shows on the Arrêts tab — the
                // Infos trafic tab is direction-agnostic (a community
                // signalement applies to the line as a whole, regardless of
                // which direction the user is heading).
                if viewModel.availableVariants.count > 1 {
                    directionToggle
                }
                stopsTabContent
            case .traffic:
                trafficTabContent
            }
        }
    }

    /// Text-with-underline tabs (IDF Mobilités style) instead of the chunky
    /// capsule chips we used before. The chip style was visually
    /// indistinguishable from the `directionToggle` below, which made the
    /// hierarchy confusing. With underline tabs they read clearly as the
    /// primary nav and the direction chips stay as the secondary control.
    private var primaryTabSwitcher: some View {
        HStack(spacing: 0) {
            primaryTabLabel(.stops, label: String(localized: "Arrêts"))
            primaryTabLabel(.traffic, label: "Infos trafic", showsStatusIcon: true)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.ink.opacity(0.10))
                .frame(height: 1)
        }
    }

    private func primaryTabLabel(_ tab: DetailTab, label: String, showsStatusIcon: Bool = false) -> some View {
        let isSelected = selectedTab == tab
        let isIssue = hasActiveTrafficIssue
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTab = tab
            }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                if showsStatusIcon {
                    statusBadgeIcon(isIssue: isIssue)
                }
            }
            .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.inkMute)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(DS.Color.ink)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "primaryTabUnderline", in: tabUnderlineNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    /// Small status pill shown next to "Infos trafic" — green check.seal
    /// when the line is fully nominal, red warning triangle as soon as one
    /// community signalement, official incident, or perturbation summary
    /// exists. Mirrors the IDF Mobilités convention used in photo 2.
    private func statusBadgeIcon(isIssue: Bool) -> some View {
        Image(systemName: isIssue ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
            .font(.system(size: 12, weight: .black))
            .foregroundStyle(.white)
            .frame(width: 18, height: 18)
            .background(Circle().fill(isIssue ? DS.Color.statusMajor : DS.Color.statusOK))
    }

    @ViewBuilder
    private var stopsTabContent: some View {
        summaryCard

        DS.Rule(thick: true)

        if viewModel.isLoading && viewModel.orderedStops.isEmpty {
            ProgressView()
                .tint(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if let loadError = viewModel.loadError, viewModel.orderedStops.isEmpty {
            Text(loadError)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else {
            timeline
        }
    }

    /// Whether the line currently has any active issue — community,
    /// official incident, line-level perturbation summary, or a global
    /// summary that lists this line as affected. Drives the icon used in
    /// the "Infos trafic" tab chip (checkmark.seal.fill when nominal,
    /// exclamationmark.triangle when not).
    /// Nombre d'infos CONCRÈTES sur la ligne = signalements communauté +
    /// incidents officiels propres à la ligne. C'est ce que compte le
    /// sous-titre du bandeau ; le reste de la logique s'y aligne pour éviter
    /// le "Perturbations en cours · 0 infos".
    private var activeInfoCount: Int {
        viewModel.lineSignalements.count + mergedOfficialIncidents.count
    }

    /// Résumé STIB propre à CETTE ligne (≠ résumé réseau global).
    private var hasLineLevelSummary: Bool {
        guard let summary = viewModel.activeLine?.perturbationSummary else { return false }
        return summary.shortText.isEmpty == false || summary.longText.isEmpty == false
    }

    private var hasActiveTrafficIssue: Bool {
        // Bandeau rouge "Perturbations en cours" + ⚠️ sur l'onglet UNIQUEMENT
        // pour un VRAI problème ouvrable : un signalement communauté ou un
        // incident officiel CONCRET propre à la ligne. Un simple résumé (réseau
        // OU ligne) du type "Réseau sous surveillance / signaux faibles /
        // MIXTE" ne déclenche PLUS l'alarme : il n'a ni "quoi" ni "où" concret,
        // donc il est montré comme contexte (carte info bleue) dans l'onglet
        // Officiel, sans faire croire à une perturbation. (cf. hasLineLevelSummary,
        // gardé pour d'éventuels usages mais volontairement hors de l'alarme.)
        activeInfoCount > 0
    }

    private var trafficStatusIcon: String {
        hasActiveTrafficIssue ? "exclamationmark.triangle.fill" : "checkmark.seal.fill"
    }

    @ViewBuilder
    private var trafficTabContent: some View {
        trafficStatusBanner

        trafficSubtabSwitcher

        switch selectedTrafficSubtab {
        case .live:
            communityIncidentsList
        case .upcoming:
            officialIncidentsList
        case .social:
            socialPlaceholder
        }
    }

    /// Top status banner inside the Infos trafic tab: a big colored disc
    /// with either a green checkmark ("Trafic normal") or a warning icon
    /// ("Perturbations en cours").
    private var trafficStatusBanner: some View {
        let isOK = !hasActiveTrafficIssue
        return HStack(spacing: 14) {
            Image(systemName: isOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(isOK ? DS.Color.statusOK : DS.Color.statusMajor))
                .shadow(color: (isOK ? DS.Color.statusOK : DS.Color.statusMajor).opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOK ? "Trafic normal" : "Perturbations en cours")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(isOK
                     ? "Aucun signalement actif sur cette ligne."
                     : (activeInfoCount > 0
                        ? "\(activeInfoCount) infos · communauté + STIB"
                        : "Info trafic STIB sur cette ligne"))
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(2)
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
    }

    /// Three-chip segmented control for the Infos trafic sub-filters.
    /// Mirrors the IDF Mobilités pattern. We renamed "À venir" → "Officiel"
    /// per user feedback (it's about STIB-confirmed entries, not just
    /// scheduled-future ones).
    private var trafficSubtabSwitcher: some View {
        HStack(spacing: 4) {
            trafficSubtabChip(.live, label: String(localized: "En cours"), count: liveCount)
            trafficSubtabChip(.upcoming, label: String(localized: "Officiel"), count: officialCount)
            trafficSubtabChip(.social, label: String(localized: "Twitter / X"), count: 0)
        }
        .padding(4)
        .background(DS.Color.paper2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var liveCount: Int { viewModel.lineSignalements.count }

    /// Count of *line-specific* official entries — STIB incidents tagged to
    /// this line + its own perturbationSummary. We intentionally exclude
    /// `matchingGlobalSummary` (the network-wide advisory) because counting
    /// it as "1" made the badge promise an entry the user couldn't tie to a
    /// specific row underneath. The global advisory is now surfaced as a
    /// contextual footer in the empty state instead.
    private var officialCount: Int {
        // FIX — Le badge "Officiel N" ne compte QUE les incidents officiels
        // CONCRETS liés à la ligne (mêmes éléments que l'en-tête "N infos").
        // Avant, un simple résumé réseau ("Réseau sous surveillance", signaux
        // faibles) ajoutait +1 → le badge disait "Officiel 1" alors que
        // l'en-tête affichait "0 infos" et qu'aucun incident réel n'était
        // listé. Le résumé réseau reste affiché en carte d'info distincte
        // (perturbationSummaryRow / networkAdvisoryRow) mais ne compte plus.
        mergedOfficialIncidents.count
    }

    /// Incidents officiels du fetch par ligne + ceux que la grille a utilisés
    /// pour badger (seed), dédupliqués par id. Garantit que si la grille a mis
    /// un badge, le détail liste bien l'incident correspondant.
    private var mergedOfficialIncidents: [TransportIncidentDTO] {
        let fetched = viewModel.activeLine?.activeIncidents ?? []
        guard !seedOfficialIncidents.isEmpty else { return fetched }
        var result = fetched
        let known = Set(fetched.map(\.id))
        for incident in seedOfficialIncidents where !known.contains(incident.id) {
            result.append(incident)
        }
        return result
    }

    private func trafficSubtabChip(_ tab: TrafficSubtab, label: String, count: Int = 0) -> some View {
        let isSelected = selectedTrafficSubtab == tab
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                selectedTrafficSubtab = tab
            }
        } label: {
            HStack(spacing: 4) {
                Text(label)
                    .font(DS.Font.bodyBold)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(
                            Capsule()
                                .fill(isSelected ? DS.Color.paper.opacity(0.22) : DS.Color.statusMajor.opacity(0.18))
                        )
                        .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.statusMajor)
                }
            }
            .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(isSelected ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.ink.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var communityIncidentsList: some View {
        if viewModel.lineSignalements.isEmpty {
            emptyStateCard(
                icon: "person.2.fill",
                title: String(localized: "Pas de signalement communauté"),
                detail: String(localized: "Aucun usager n'a signalé d'incident actif sur cette ligne.")
            )
        } else {
            VStack(spacing: 8) {
                ForEach(viewModel.lineSignalements) { signalement in
                    communityIncidentRow(signalement)
                }
            }
        }
    }

    @ViewBuilder
    private var officialIncidentsList: some View {
        let incidents = mergedOfficialIncidents
        let lineSummary = viewModel.activeLine?.perturbationSummary
        let hasLineSummary = (lineSummary?.shortText.isEmpty == false) || (lineSummary?.longText.isEmpty == false)
        let globalSummary = viewModel.matchingGlobalSummary

        if incidents.isEmpty {
            // Aucun incident officiel CONCRET sur la ligne → PAS de carte
            // d'alerte orange. Les résumés (ligne ou réseau) du type "Réseau
            // sous surveillance" sont affichés comme CONTEXTE (carte info
            // bleue), cohérent avec le bandeau qui reste vert. Avant, un résumé
            // de ligne vague passait par perturbationSummaryRow (orange ⚠️) et
            // faisait croire à une perturbation.
            VStack(spacing: 8) {
                emptyStateCard(
                    icon: "checkmark.seal.fill",
                    title: String(localized: "Pas d'info officielle sur cette ligne"),
                    detail: String(localized: "La STIB-MIVB n'a publié aucune perturbation propre à cette ligne.")
                )
                // « Vrais problèmes ou rien » : on n'affiche l'avis QUE s'il
                // pointe un quoi + où concret (lignes/arrêts touchés). L'avis
                // vague « Réseau sous surveillance » (signaux faibles, sans
                // ligne ni arrêt) n'apparaît plus du tout → la ligne reste
                // simplement « pas d'info officielle » (bandeau vert).
                if let lineSummary, lineSummary.hasConcreteContent {
                    networkAdvisoryRow(lineSummary)
                } else if let globalSummary, globalSummary.hasConcreteContent {
                    networkAdvisoryRow(globalSummary)
                }
            }
        } else {
            VStack(spacing: 8) {
                // Line-level perturbation summary first (highest specificity).
                if let lineSummary, hasLineSummary {
                    perturbationSummaryRow(lineSummary)
                }
                ForEach(incidents) { incident in
                    officialIncidentRow(incident)
                }
                // Global advisory appended as a clearly-labelled context
                // card — not counted in the badge, kept visually distinct
                // from line-specific entries.
                if let globalSummary {
                    networkAdvisoryRow(globalSummary)
                }
            }
        }
    }

    /// Distinct card for the network-wide advisory: tinted background, "AVIS
    /// RÉSEAU STIB" eyebrow, info icon. Visually different from
    /// `perturbationSummaryRow` so the user reads it as context, not as the
    /// counted entry promised by the "Officiel" badge.
    private func networkAdvisoryRow(_ summary: TransportPerturbationSummaryDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "info.circle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.info)
                .frame(width: 28, height: 28)
                .background(DS.Color.info.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text("AVIS RÉSEAU STIB")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(1.2)
                    .foregroundStyle(DS.Color.info)
                Text(summary.localizedTitle.isEmpty ? String(localized: "Réseau sous surveillance") : summary.localizedTitle)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text(summary.localizedShortText.isEmpty ? summary.localizedLongText : summary.localizedShortText)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(4)
                Text("Cette ligne est mentionnée dans l'avis général — pas d'incident propre à elle pour le moment.")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.top, 2)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(DS.Color.info.opacity(0.06))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.info.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func perturbationSummaryRow(_ summary: TransportPerturbationSummaryDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.statusMinor)
                .frame(width: 28, height: 28)
                .background(DS.Color.statusMinor.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 4) {
                Text(summary.localizedTitle.isEmpty ? String(localized: "Perturbation officielle") : summary.localizedTitle)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text(summary.localizedShortText.isEmpty ? summary.localizedLongText : summary.localizedShortText)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(4)
                if let label = summary.sourceLabel, !label.isEmpty {
                    Text(label.uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(DS.Color.inkMute)
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

    private var socialPlaceholder: some View {
        emptyStateCard(
            icon: "bubble.left.and.text.bubble.right.fill",
            title: "Twitter / X — bientôt",
            detail: "Recherche en temps réel des mentions STIB / MIVB sur les réseaux. Intégration en cours."
        )
    }

    private func emptyStateCard(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(DS.Color.inkMute)
            Text(title)
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
            Text(detail)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(DS.Color.paper2.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func communityIncidentRow(_ signalement: SignalementDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.bubble.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.community)
                .frame(width: 28, height: 28)
                .background(DS.Color.community.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(signalement.displayTypeProbleme)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                if case .populated(let arret) = signalement.arretId {
                    Text(arret.nom.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(DS.Color.inkMute)
                }
                Text(signalement.freshnessLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer(minLength: 0)
            if let confirmations = signalement.community?.confirmations, confirmations > 0 {
                Text("\(confirmations)×")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.community)
            }
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private func officialIncidentRow(_ incident: TransportIncidentDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.statusMinor)
                .frame(width: 28, height: 28)
                .background(DS.Color.statusMinor.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(incident.type ?? "Information STIB")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                if let description = incident.description, !description.isEmpty {
                    Text(description)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(3)
                }
                if let stopName = incident.stop?.name {
                    Text(stopName.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1.0)
                        .foregroundStyle(DS.Color.inkMute)
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

    private var identifierBlock: some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            LineBadge(
                line: viewModel.line.line,
                size: .lg,
                fill: viewModel.line.lineColor,
                foreground: viewModel.line.lineTextColor
            )

            VStack(alignment: .leading, spacing: 4) {
                // Shrunk from displayH2 (Dela Gothic ~26pt) to a compact
                // bold system font — the title "GARE DE L'OUEST ⇄ STOCKEL"
                // used to dominate the screen and push the tabs below the
                // fold. 17pt bold leaves room for the operator row +
                // direction toggle without scrolling.
                Text(viewModel.destinationsLabel)
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)

                Text(viewModel.routeSubtitle)
                    .font(DS.Font.monoSmall)
                    .tracking(1.0)
                    .foregroundStyle(viewModel.orderedStops.contains(where: { $0.disruption != nil }) ? DS.Color.statusMajor : DS.Color.inkMute)
            }
        }
    }

    /// Compact segmented control showing each available direction with its
    /// terminus name. Tapping toggles the line variant. Replaces the older
    /// two-column block where both halves showed the same destination at
    /// loop terminals (which left users confused as to which side served
    /// them at a stop like GARE DU NORD).
    private var directionToggle: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DIRECTION")
                .font(DS.Font.eyebrow)
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)
            HStack(spacing: 4) {
                ForEach(viewModel.availableVariants) { variant in
                    directionChip(variant)
                }
            }
            .padding(4)
            .background(DS.Color.paper2.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private func directionChip(_ variant: LigneDetailViewModel.DirectionVariant) -> some View {
        let isSelected = viewModel.selectedVariant == variant
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                viewModel.selectVariant(variant)
            }
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "arrow.forward")
                    .font(.system(size: 10, weight: .black))
                Text(directionDestination(for: variant))
                    .font(DS.Font.bodyBold)
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .frame(height: 40)
            .background(isSelected ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.ink.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var summaryCard: some View {
        DS.PaperCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("ÉTAT DE LA DIRECTION")
                            .eyebrow()
                        Text(viewModel.summaryTitle)
                            .font(DS.Font.displayH3)
                            .foregroundStyle(DS.Color.ink)
                        Text("Direction \(viewModel.selectedVariant.label) · vers \(activeDestination)")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkSoft)
                            .lineLimit(1)
                    }

                    Spacer()

                    DS.StatusPill(confidenceLabel, level: statusLevel)
                }

                departuresPreview

                if let alternative = viewModel.alternativeSummary, !alternative.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alternative")
                            .sectionTitle()
                        Text(alternative)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkSoft)
                    }
                }
            }
        }
    }

    private var departuresPreview: some View {
        let departures = Array((viewModel.activeLine?.nextDepartures ?? []).prefix(3))

        return VStack(alignment: .leading, spacing: DS.Spacing.sm) {
            Text("Prochains départs")
                .sectionTitle()
            if departures.isEmpty {
                Text(viewModel.summaryDetails)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                ForEach(Array(departures.enumerated()), id: \.offset) { _, departure in
                    departureRow(departure)
                }
            }
        }
    }

    private func departureRow(_ departure: TransportDepartureDTO) -> some View {
        HStack(spacing: DS.Spacing.sm) {
            VStack(alignment: .leading, spacing: 2) {
                Text(departure.destination.map { "vers \($0)" } ?? "Prochain départ")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)

                HStack(spacing: 6) {
                    Text(departure.source == "scheduled" ? "Horaire prévu" : "Temps réel STIB")
                    if let time = departure.realtimeDepartureAt ?? departure.scheduledDepartureAt {
                        Text("· \(Self.departureTimeFormatter.string(from: time))")
                    }
                    if let delay = departure.delayMinutes, delay > 0 {
                        Text("+\(delay) min")
                            .foregroundStyle(DS.Color.statusMajor)
                    }
                }
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.inkMute)
                .lineLimit(1)
            }

            Spacer(minLength: DS.Spacing.sm)

            VStack(alignment: .trailing, spacing: 2) {
                Text(Self.minutesLabel(departure.minutes))
                    .font(DS.Font.displayH3)
                    .foregroundStyle(DS.Color.ink)
                    .monospacedDigit()
                    .lineLimit(1)
                Text(departure.source == "scheduled" ? "prévu" : "live")
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(departure.source == "scheduled" ? DS.Color.inkMute : DS.Color.statusOK)
            }
        }
        .padding(.horizontal, DS.Spacing.sm)
        .padding(.vertical, DS.Spacing.sm)
        .background(DS.Color.paper2.opacity(0.35))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private static let departureTimeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func minutesLabel(_ minutes: Int) -> String {
        minutes <= 0 ? "Imminent" : "\(minutes) min"
    }

    private var timeline: some View {
        let stops = viewModel.orderedStops
        return VStack(spacing: 0) {
            ForEach(Array(stops.enumerated()), id: \.element.id) { index, stop in
                LigneTimelineRow(
                    stop: stop,
                    isFirst: index == 0,
                    isLast: index == stops.count - 1,
                    nextStopDisrupted: index < stops.count - 1 && stops[index + 1].disruption != nil,
                    communityReportCount: viewModel.communityReportCount(forStopName: stop.name),
                    onTap: { selectedStopForDetail = stop }
                )
            }
        }
    }

    private var activeDestination: String {
        viewModel.activeLine?.line.stops.last?.name ?? viewModel.line.destination
    }

    private func directionDestination(for variant: LigneDetailViewModel.DirectionVariant) -> String {
        switch variant {
        case .city:
            return viewModel.cityLine?.line.stops.last?.name ?? "Centre"
        case .suburb:
            return viewModel.suburbLine?.line.stops.last?.name ?? "Retour"
        case .base:
            return viewModel.baseLine?.line.stops.last?.name ?? viewModel.line.destination
        }
    }

    private var confidenceLabel: String {
        let confidence = viewModel.activeLine?.confidence ?? 0
        let value = Int((confidence * 100).rounded())
        return "\(value)% fiable"
    }

    private var statusLevel: DS.StatusLevel {
        switch viewModel.activeLine?.severity {
        case "critical": return .critical
        case "major": return .major
        case "minor": return .minor
        default: return .ok
        }
    }

    private func goBack() {
        if let onBackOverride {
            onBackOverride()
        } else {
            dismiss()
        }
    }

    private static func makeFallbackLine(lineId: String) -> LineStatusItem {
        // Backend ships lineids as "14:Suburb" / "T7:City" etc. Strip the
        // composite suffix + T/B/M prefix so the LineBadge renders just "14",
        // matches `TransitLinePalette`'s official STIB colour, and looks
        // identical to the line cards on the home/horaires screens.
        let shortCode = Self.shortCode(from: lineId)
        let color = palette(for: shortCode)
        return LineStatusItem(
            line: shortCode,
            lineColor: color.fill,
            lineTextColor: color.foreground,
            origin: "Bruxelles",
            destination: "Bruxelles",
            direction: "Bruxelles",
            status: .fluid,
            reportsCount: 0,
            filter: LineFilter.from(line: shortCode),
            confidenceText: nil
        )
    }

    /// Same normalisation we use in `SchedulesView.shortCode(from:)`. Kept
    /// inline rather than imported so this view stays decoupled from the
    /// schedules tab; tweak both together if STIB ever changes its id
    /// convention.
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

    private static func palette(for shortCode: String) -> (fill: Color, foreground: Color) {
        // Try the official STIB palette first (each line has its own colour).
        // Fall back to the mode-tinted default if the line is unrecognised
        // (night buses, special services).
        let fill = TransitLinePalette.fill(for: shortCode)
        let foreground = TransitLinePalette.foreground(for: shortCode)
        if fill != DS.Color.primary {
            return (fill, foreground)
        }
        switch TransitLineMode.mode(for: shortCode) {
        case .metro: return (DS.Color.metro, DS.Color.primaryForeground)
        case .tram:  return (DS.Color.tram, DS.Color.ink)
        case .bus:   return (DS.Color.bus, DS.Color.primaryForeground)
        }
    }
}

private struct LigneTimelineRow: View {
    let stop: LigneDetailViewModel.StopSnapshot
    let isFirst: Bool
    let isLast: Bool
    var nextStopDisrupted: Bool = false
    /// Number of currently-active community reports targeting this stop on
    /// the surrounding line. Non-zero values render a small `⚠ N` badge
    /// next to the stop name so the user instantly sees which stops are
    /// flagged by riders.
    var communityReportCount: Int = 0
    var onTap: (() -> Void)? = nil

    @State private var blinkPhase = false
    @State private var vehiclePulse = false

    private var isTerminus: Bool { isFirst || isLast }

    private var segmentIsFullyDisrupted: Bool {
        stop.disruption != nil && nextStopDisrupted
    }

    private var hasSignificantDelay: Bool {
        (stop.delayMinutes ?? 0) > 10
    }

    private var segmentColor: Color {
        guard stop.disruption != nil || nextStopDisrupted || hasSignificantDelay else {
            return DS.Color.ink.opacity(0.2)
        }
        if segmentIsFullyDisrupted {
            switch stop.disruptionSeverity {
            case "critical": return DS.Color.statusMajor
            case "major":    return DS.Color.statusMajor.opacity(0.85)
            case "minor":    return DS.Color.statusMinor
            default:         return DS.Color.statusMajor.opacity(0.75)
            }
        }
        if stop.disruption != nil {
            return DS.Color.statusMajor.opacity(0.4)
        }
        if nextStopDisrupted {
            return DS.Color.statusMajor.opacity(0.2)
        }
        return DS.Color.statusMinor.opacity(0.45)
    }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(segmentColor)
                        .opacity(segmentIsFullyDisrupted && blinkPhase ? 0.35 : 1.0)
                        .frame(width: 2)
                        .padding(.top, 24)
                        .frame(maxHeight: .infinity, alignment: .top)
                        .onAppear {
                            guard segmentIsFullyDisrupted else { return }
                            withAnimation(
                                .easeInOut(duration: 0.9)
                                .repeatForever(autoreverses: true)
                            ) { blinkPhase = true }
                        }
                }

                ZStack {
                    if stop.vehiclePresent {
                        // Live "vehicle is here" marker: a solid RED disc with a
                        // radar-style pulsing halo, so the empty ○ becomes a
                        // filled ● exactly where the tram/bus currently is. Red
                        // (the app's alert colour) is used regardless of the
                        // line colour so the live marker always stands out. The
                        // halo lives in a `.background` so it never shifts the
                        // dot or the connecting-line junction below.
                        Circle()
                            .fill(DS.Color.statusMajor)
                            .frame(width: 14, height: 14)
                            .overlay(Circle().stroke(DS.Color.ink, lineWidth: 2))
                            .overlay(Circle().fill(.white).frame(width: 4, height: 4))
                            .background(
                                Circle()
                                    .fill(DS.Color.statusMajor.opacity(0.30))
                                    .frame(width: 30, height: 30)
                                    .scaleEffect(vehiclePulse ? 1.0 : 0.45)
                                    .opacity(vehiclePulse ? 0 : 0.9)
                            )
                    } else {
                        Circle()
                            .fill(dotFill)
                            .frame(width: 12, height: 12)
                            .overlay(Circle().stroke(DS.Color.ink, lineWidth: 2))

                        if let icon = incidentIcon {
                            Image(systemName: icon)
                                .font(.system(size: 6, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                }
                .padding(.top, 12)
                .onAppear {
                    guard stop.vehiclePresent else { return }
                    withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) {
                        vehiclePulse = true
                    }
                }
            }
            .frame(width: 24)

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(stop.name)
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)

                        if communityReportCount > 0 {
                            HStack(spacing: 3) {
                                Image(systemName: "exclamationmark.triangle.fill")
                                    .font(.system(size: 9, weight: .black))
                                Text("\(communityReportCount)")
                                    .font(.system(size: 10, weight: .black, design: .rounded))
                            }
                            .foregroundStyle(DS.Color.statusMinor)
                            .padding(.horizontal, 5)
                            .frame(height: 16)
                            .background(DS.Color.statusMinor.opacity(0.14))
                            .overlay(Capsule().stroke(DS.Color.statusMinor.opacity(0.35), lineWidth: 0.8))
                            .clipShape(Capsule())
                            .accessibilityLabel("\(communityReportCount) signalements communauté")
                        }

                        if isTerminus {
                            Text("Terminus")
                                .font(DS.Font.monoSmall)
                                .tracking(1.2)
                                .foregroundStyle(DS.Color.inkMute)
                        }

                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }

                    if let disruption = stop.disruption, !disruption.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: incidentIcon ?? "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(disruptionColor)
                                .padding(.top, 2)
                            Text(disruption)
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(disruptionColor)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(disruptionColor.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(disruptionColor)
                                .frame(width: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                }

                Spacer(minLength: 8)

                if !stop.waits.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(stop.waits[0]) min")
                            .font(DS.Font.monoLarge)
                            .foregroundStyle(DS.Color.ink)
                        if stop.vehiclePresent {
                            // A live vehicle of this direction is here right now.
                            Text("À L'ARRÊT")
                                .font(.system(size: 9, weight: .black, design: .monospaced))
                                .tracking(0.8)
                                .foregroundStyle(DS.Color.statusOK)
                        } else if let delay = stop.delayMinutes, delay > 2 {
                            Text("+\(delay) min")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.statusMajor)
                        } else if stop.waitsSource == "scheduled" {
                            Text("théorique")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        // Second upcoming passage shown as an absolute "puis N
                        // min" rather than the old "+N" which read like a delay
                        // and confused the real next-passage time.
                        if stop.waits.count > 1 {
                            Text("puis \(stop.waits[1]) min")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                } else {
                    Text("--")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.vertical, 10)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap?() }
    }

    private var dotFill: Color {
        guard stop.disruption != nil else {
            return isTerminus ? DS.Color.ink : DS.Color.paper
        }
        switch stop.disruptionSeverity {
        case "critical": return DS.Color.statusMajor
        case "major":    return DS.Color.statusMajor
        case "minor":    return DS.Color.statusMinor
        default:         return DS.Color.statusMajor
        }
    }

    private var disruptionColor: Color {
        switch stop.disruptionSeverity {
        case "minor": return DS.Color.statusMinor
        default:      return DS.Color.statusMajor
        }
    }

    private var incidentIcon: String? {
        switch stop.incidentType?.lowercased() {
        case "accident": return "car.fill"
        case "breakdown", "panne": return "bolt.slash.fill"
        case "works", "travaux", "construction": return "wrench.and.screwdriver.fill"
        case "demonstration", "manifestation", "event": return "person.3.fill"
        case "police", "intervention": return "staroflife.fill"
        case "delay", "retard": return "clock.badge.exclamationmark.fill"
        case let t where t != nil: return "exclamationmark.triangle.fill"
        default: return nil
        }
    }
}

private struct LigneStopDetailSheet: View {
    @EnvironmentObject private var session: AuthSession
    @Environment(\.dismiss) private var dismiss
    let stop: LigneDetailViewModel.StopSnapshot

    @State private var stopDetail: TransportStopDTO?
    @State private var isLoading = false

    private var stopSummary: TransportStopSummaryDTO {
        TransportStopSummaryDTO(
            id: stop.backendId ?? stop.id,
            stopId: stop.stopId,
            name: stop.name,
            latitude: nil,
            longitude: nil,
            lines: []
        )
    }

    var body: some View {
        ArretDetailPage(
            stopSummary: stopSummary,
            stopDetail: stopDetail,
            isLoading: isLoading,
            userCoordinate: nil,
            nearbyStops: [],
            nearbyVilloStations: [],
            communitySignalements: [],
            onDismiss: { dismiss() },
            onOpenLine: { _ in },
            selectedLineRoute: nil,
            onSelectLineRoute: { _ in },
            onOpenStop: { _ in },
            onReport: {}
        )
        .task {
            guard AppConfig.isBackendEnabled else { return }
            isLoading = true
            let lookupId = stop.stopId ?? stop.backendId ?? stop.id
            stopDetail = try? await TransportService.stop(id: lookupId)
            isLoading = false
        }
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LigneDetailPage(lineId: "1")
    }
}
#endif
