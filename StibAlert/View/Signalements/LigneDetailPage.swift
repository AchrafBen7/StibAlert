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
        /// Les AUTRES lignes qui desservent cet arrêt, ligne courante exclue.
        /// C'est la correspondance : savoir qu'on peut sauter sur un 25 ici
        /// vaut souvent plus que l'attente de la ligne qu'on regarde.
        let connectingLines: [String]
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
        // Plus de retombée sur `line.direction` (« Bruxelles ») : quand le fetch
        // des variantes a échoué, ce libellé générique se faisait passer pour un
        // vrai tracé. Vide → l'en-tête n'affiche rien et l'état d'erreur parle.
        return unique.first ?? activeLine?.line.name ?? ""
    }

    var routeSubtitle: String {
        // Pas de tracé chargé → pas de « 0 arrêts · temps réel STIB » inventé.
        guard activeLine != nil else { return "" }
        let stopsCount = orderedStops.count
        if orderedStops.contains(where: { $0.disruption != nil }) {
            let count = orderedStops.filter { $0.disruption != nil }.count
            // Le pluriel est porté par la traduction, pas par un `count > 1 ? "s" : ""`
            // codé en dur : le néerlandais ne forme pas ses pluriels comme le français.
            return count > 1
                ? AppLocalizer.format("line.subtitle.disruptions", defaultValue: "%lld arrêts · %lld perturbations", stopsCount, count)
                : AppLocalizer.format("line.subtitle.disruption_one", defaultValue: "%lld arrêts · %lld perturbation", stopsCount, count)
        }
        return AppLocalizer.format("line.subtitle.realtime", defaultValue: "%lld arrêts · temps réel STIB", stopsCount)
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

        // FIX — plus de fallback sur `stopCatalog` brut quand les variantes
        // city/suburb/base ont toutes échoué : ce catalogue n'est PAS ordonné,
        // mélange les deux directions et contient des doublons (EENENS deux
        // fois, « Terminus » au milieu du tracé, « Bruxelles · 38 arrêts » sans
        // toggle direction). Le fallback se déguisait en données réelles. Sans
        // tracé chargé, la vue affiche un état d'erreur honnête + Réessayer.
        return []
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

        // L'état global du réseau ne sert QU'À un repli d'affichage dans
        // l'onglet Officiel, mais c'est l'appel le plus lourd de l'écran
        // (il agrège six arrêts). Lancé en parallèle des trois variantes de
        // tracé, il leur disputait la bande passante : sur une connexion
        // instable les six requêtes simultanées se bloquaient mutuellement,
        // les trois variantes expiraient à 8 s, et la page affichait
        // « Impossible de charger le tracé » alors que le serveur répondait
        // en moins d'une seconde. On l'exécute donc APRÈS, hors chemin critique.
        if let overview = try? await TransportService.overview() {
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

        // L'erreur se déclenche dès que le TRACÉ manque (les 3 variantes nil),
        // même si `stopCatalog` est revenu : on ne rend plus de timeline depuis
        // ce catalogue non ordonné (cf. orderedStops).
        if cityLine == nil && suburbLine == nil && baseLine == nil {
            loadError = AppLocalizer.string("line.load_error",
                                            defaultValue: "Impossible de charger le tracé de la ligne.")
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

        // Texte de perturbation sur la timeline : version LOCALISÉE (NL quand l'app
        // est en NL — avant on lisait `.description`, le champ plat FRANÇAIS, d'où du
        // français dans une app en néerlandais) et DÉCOMPOSÉE via DisruptionDigest
        // pour n'afficher que l'EFFET (« tram 4 dévié ») au lieu du paragraphe brut
        // tronqué (« Interruption trams 4 10: Tram 4 STALLE (P) à… »).
        let disruption = incidents.first.map {
            DisruptionDigest.parse($0.localizedDescription ?? $0.localizedType ?? "").effect
        }

        let waits = catalog?.nextPassages ?? catalog?.nextPassageMinutes.map { [$0] } ?? []

        // A live vehicle is "at" this stop when the map endpoint reports a
        // vehicle whose `stopNom` matches this stop (precomputed into
        // `occupiedKeys` so we don't rescan the vehicle list per stop).
        let vehiclePresent = occupiedKeys.contains(stop.name.normalizedStopKey)

        // Correspondances : les autres lignes de l'arrêt. La ligne qu'on
        // consulte est retirée — l'app STIB fait pareil, elle est implicite.
        let currentLine = lineDetail.line.lineId.uppercased()
        let connectingLines = (catalog?.lignesDesservies ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty && $0.uppercased() != currentLine }

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
            vehiclePresent: vehiclePresent,
            connectingLines: connectingLines
        )
    }
}

struct LigneDetailPage: View {
    /// Top-level mode: timeline of stops, or the new infos-trafic overview
    /// (status icon + 3 sub-tabs for community / official / social).
    enum DetailTab: Hashable { case stops, traffic }
    /// Filtres de l'onglet Infos trafic. L'ancien sous-onglet « Twitter / X »
    /// a été retiré : c'était une source technique promue en onglet, qui
    /// n'affichait qu'un état vide « bientôt ».
    enum TrafficSubtab: Hashable { case live, upcoming }

    @StateObject private var viewModel: LigneDetailViewModel
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var session: AuthSession

    @State private var selectedStopForDetail: LigneDetailViewModel.StopSnapshot?
    @State private var selectedTab: DetailTab
    /// On ouvre sur « Officiel », pas sur « En cours ».
    ///
    /// « En cours » ne contient que les signalements de la communauté : tant
    /// qu'il y a peu d'utilisateurs, il est vide la plupart du temps, et la page
    /// s'ouvrait donc sur « Aucun signalement de la communauté » alors que
    /// l'onglet d'à côté annonçait huit perturbations officielles. On montre
    /// d'abord ce qui a de l'information.
    @State private var selectedTrafficSubtab: TrafficSubtab = .upcoming
    @State private var favoriteInFlight = false
    @Namespace private var tabUnderlineNamespace

    /// La ligne est-elle dans les favoris de l'utilisateur ? Même source que la
    /// section « lignes suivies » de l'onglet Favoris (`favoriteLines` du profil).
    private var isLineFavorite: Bool {
        guard let fav = session.currentUser?.favoriteLines else { return viewModel.isFollowed }
        return fav.contains { $0.caseInsensitiveCompare(viewModel.line.line) == .orderedSame }
    }

    /// Ajoute / retire la ligne des favoris — et la fait donc apparaître dans
    /// l'onglet Favoris. Avant, le bouton « Suivre » ne faisait qu'un toggle LOCAL
    /// (`isFollowed`) sans rien persister : la ligne « suivie » n'apparaissait nulle
    /// part. On câble désormais le même `favoriteLines` que le reste de l'app.
    private func toggleLineFavorite() async {
        let lineNumber = viewModel.line.line
        guard let user = session.currentUser else {
            // Invité : pas de favoris serveur → retour visuel local en attendant un compte.
            viewModel.isFollowed.toggle()
            return
        }
        guard !favoriteInFlight else { return }
        favoriteInFlight = true
        defer { favoriteInFlight = false }

        let current = Set(user.favoriteLines ?? [])
        let alreadyFav = current.contains { $0.caseInsensitiveCompare(lineNumber) == .orderedSame }
        let updatedLines = (alreadyFav
            ? current.filter { $0.caseInsensitiveCompare(lineNumber) != .orderedSame }
            : current.union([lineNumber]))
            .sorted { $0.compare($1, options: .numeric) == .orderedAscending }

        do {
            let updated = try await UtilisateurService.mettreAJourProfil(userId: user.id, favoriteLines: updatedLines)
            session.applyCurrentUserUpdate(updated)
            // Funnel : on ne compte que l'AJOUT (pas le retrait). `kind: line`,
            // pendant du `kind: stop` — sans révéler quelle ligne.
            if !alreadyFav { Analytics.track(.favoriteAdded, ["kind": "line"]) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            // Silencieux : un favori qui échoue ne doit pas casser la page.
        }
    }

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
                    Task { await toggleLineFavorite() }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: isLineFavorite ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(isLineFavorite ? DS.Color.primary : DS.Color.ink)
                        Text("Suivre")
                            .font(DS.Font.bodySmall.weight(.semibold))
                            .foregroundStyle(DS.Color.ink)
                    }
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 36)
                    .background(isLineFavorite ? DS.Color.primary.opacity(0.10) : DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(isLineFavorite ? DS.Color.primary.opacity(0.4) : DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(favoriteInFlight)
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
        .accessibilityLabel(AppLocalizer.string("Rafraîchir les horaires", defaultValue: "Rafraîchir les horaires"))
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
            primaryTabLabel(.stops, label: AppLocalizer.string("Arrêts"))
            primaryTabLabel(.traffic, label: AppLocalizer.string("Infos trafic"), showsStatusIcon: true)
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
        // La carte « État de la direction » a été retirée : elle répétait le statut
        // (déjà dans l'en-tête et sur l'onglet Infos trafic), la direction (déjà dans
        // le sélecteur juste au-dessus) et un « % fiable » constant. Surtout, elle
        // annonçait « Aucun prochain départ fiable » — lisant le temps réel — pendant
        // que la liste d'arrêts affichait les horaires théoriques juste en dessous.
        // Seule l'alternative d'itinéraire portait une information unique : on la garde.
        if let alternative = viewModel.alternativeSummary, !alternative.isEmpty {
            AdviceStrip(text: alternative)
                .padding(.bottom, DS.Spacing.sm)
        }

        DS.Rule(thick: true)

        if viewModel.isLoading && viewModel.orderedStops.isEmpty {
            ProgressView()
                .tint(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 40)
        } else if viewModel.activeLine == nil || viewModel.orderedStops.isEmpty {
            // Tracé indisponible APRÈS chargement → état d'erreur honnête au
            // lieu d'une timeline fabriquée depuis le catalogue brut.
            lineLoadErrorState
        } else {
            timeline
        }
    }

    /// État d'erreur du tracé : icône + message + Réessayer (relance le même
    /// `refresh()` que le bouton du header, en gardant la direction courante).
    private var lineLoadErrorState: some View {
        VStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 24, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
            Text(viewModel.loadError ?? AppLocalizer.string("line.load_error",
                                                            defaultValue: "Impossible de charger le tracé de la ligne."))
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
                .multilineTextAlignment(.center)
            Button {
                Task { await viewModel.refresh() }
            } label: {
                Text(AppLocalizer.string("Réessayer", defaultValue: "Réessayer"))
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.paper)
                    .padding(.horizontal, 18)
                    .frame(height: 38)
                    .background(DS.Color.ink)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .padding(.top, 2)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 34)
        .frame(maxWidth: .infinity)
        .background(DS.Color.paper2.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
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
        // Bandeau « Perturbations en cours · N infos » retiré : il répétait ce que
        // disent déjà l'onglet Verkeersinfo (⚠️) et les sous-onglets Lopend/Officieel
        // juste en dessous. Une seule vérité par écran.
        trafficSubtabSwitcher

        // Pendant le chargement on montre un SQUELETTE, pas l'état vide.
        // Avant, l'écran affichait « Aucun signalement de la communauté »
        // AVANT même d'avoir reçu la réponse : un verdict affirmé sur des
        // données qu'on n'avait pas encore. L'utilisateur voyait du vide, puis
        // le contenu apparaissait — impression d'app cassée.
        if viewModel.isLoading && viewModel.lineSignalements.isEmpty && mergedOfficialIncidents.isEmpty {
            trafficLoadingSkeleton
        } else {
            switch selectedTrafficSubtab {
            case .live:
                communityIncidentsList
            case .upcoming:
                officialIncidentsList
            }
        }
    }

    /// Cartes grises pulsées qui préfigurent la mise en page à venir : l'œil
    /// comprend « ça arrive » au lieu de lire un verdict prématuré.
    private var trafficLoadingSkeleton: some View {
        VStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { _ in
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .fill(DS.Color.ink.opacity(0.06))
                    .frame(height: 74)
            }
        }
        .modifier(SkeletonPulse())
        .accessibilityLabel(AppLocalizer.string("common.loading", defaultValue: "Chargement…"))
    }

    /// Three-chip segmented control for the Infos trafic sub-filters.
    /// Mirrors the IDF Mobilités pattern. We renamed "À venir" → "Officiel"
    /// per user feedback (it's about STIB-confirmed entries, not just
    /// scheduled-future ones).
    private var trafficSubtabSwitcher: some View {
        HStack(spacing: 4) {
            trafficSubtabChip(.live, label: AppLocalizer.string("En cours"), count: liveCount)
            trafficSubtabChip(.upcoming, label: AppLocalizer.string("Officiel"), count: officialCount)
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
                title: AppLocalizer.string("Pas de signalement communauté"),
                detail: AppLocalizer.string("Aucun usager n'a signalé d'incident actif sur cette ligne.")
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
                    title: AppLocalizer.string("Pas d'info officielle sur cette ligne"),
                    detail: AppLocalizer.string("La STIB-MIVB n'a publié aucune perturbation propre à cette ligne.")
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
                // Résumé de ligne (perturbationSummaryRow) retiré : quand des
                // incidents CONCRETS sont listés juste en dessous, ce résumé vague
                // (« Réseau perturbé sur 14 ») ne fait que répéter la carte
                // d'incident. On garde les incidents, on supprime le doublon.
                // La STIB publie un communiqué PAR CONSEIL, pas par perturbation :
                // « tram 92 interrompu, prends le T-bus vers SCHAERBEEK » et « tram 92
                // interrompu, T-bus vers PARC » sont UNE interruption avec DEUX
                // alternatives. Une carte chacun, ça se lit comme un copié-collé.
                ForEach(GroupedDisruption.group(incidents)) { group in
                    DisruptionCard(
                        digest: group.digest,
                        line: group.line,
                        stopName: group.stopNames.first,
                        alternatives: group.alternatives,
                        sourceCount: group.sourceCount
                    )
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
                    .font(.system(size: 9, weight: .bold))
                    .tracking(1.2)
                    .foregroundStyle(DS.Color.info)
                Text(summary.localizedTitle.isEmpty ? AppLocalizer.string("Réseau sous surveillance") : summary.localizedTitle)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text(summary.localizedShortText.isEmpty ? summary.localizedLongText : summary.localizedShortText)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(4)
                Text(AppLocalizer.string("Cette ligne est mentionnée dans l'avis général — pas d'incident propre à elle pour le moment.", defaultValue: "Cette ligne est mentionnée dans l'avis général — pas d'incident propre à elle pour le moment."))
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

    /// Carte « En cours » alignée sur la densité des cartes officielles :
    /// bandeau de source (STIB vs communauté — indispensable car le backend
    /// convertit les communiqués STIB en signalements), titre, lieu, ligne,
    /// description, et compteur de confirmations pour les vrais signalements.
    private func communityIncidentRow(_ signalement: SignalementDTO) -> some View {
        let isOfficial = signalement.isFromOfficialSource
        let accent = isOfficial ? DS.Color.statusMajor : DS.Color.community

        return VStack(alignment: .leading, spacing: 8) {
            // En-tête : source explicite + fraîcheur
            HStack(spacing: 6) {
                Image(systemName: isOfficial ? "checkmark.seal.fill" : "exclamationmark.bubble.fill")
                    .font(.system(size: 10, weight: .bold))
                Text(isOfficial
                     ? AppLocalizer.string("source.stib", defaultValue: "SOURCE OFFICIELLE")
                     : AppLocalizer.string("source.community", defaultValue: "COMMUNAUTÉ"))
                    .font(.system(size: 9.5, weight: .black))
                    .tracking(1.3)
                Spacer(minLength: 0)
                Text(signalement.freshnessLabel)
                    .font(.system(size: 10.5))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }
            .foregroundStyle(accent)

            // Titre + ligne concernée
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(signalement.displayTypeProbleme)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                if !signalement.ligne.isEmpty {
                    LineBadge(line: signalement.ligne, size: .sm)
                }
                Spacer(minLength: 0)
            }

            if case .populated(let arret) = signalement.arretId {
                HStack(spacing: 4) {
                    Image(systemName: "mappin")
                        .font(.system(size: 9.5))
                    Text(arret.nom.uppercased())
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .lineLimit(1)
                }
                .foregroundStyle(DS.Color.inkMute)
            }

            if !signalement.description.isEmpty {
                Text(signalement.description)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // Confirmations : n'a de sens que pour un VRAI signalement humain
            // (un communiqué officiel n'est pas « confirmé » par la communauté).
            if !isOfficial, let confirmations = signalement.community?.confirmations, confirmations > 0 {
                HStack(spacing: 5) {
                    Image(systemName: "person.2.fill")
                        .font(.system(size: 10, weight: .bold))
                    Text(AppLocalizer.format("report.confirmed_by",
                                             defaultValue: "Confirmé par %lld personne(s)",
                                             confirmations))
                        .font(.system(size: 11, weight: .semibold))
                }
                .foregroundStyle(DS.Color.community)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(accent.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    /// Le texte officiel est décomposé (cause / effet / période / conseil) au lieu
    /// d'être affiché brut. `DisruptionCard` met en avant CE QU'IL FAUT FAIRE, qui
    /// était jusqu'ici noyé en fin de paragraphe et tronqué à trois lignes.
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
                // Vides quand le tracé n'a pas chargé (état d'erreur en
                // dessous) : on n'affiche pas un faux « Bruxelles · 0 arrêts ».
                if !viewModel.destinationsLabel.isEmpty {
                    Text(viewModel.destinationsLabel)
                        .font(.system(size: 17, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(2)
                }

                if !viewModel.routeSubtitle.isEmpty {
                    Text(viewModel.routeSubtitle)
                        .font(DS.Font.labelSmall)
                        .tracking(1.0)
                        .foregroundStyle(viewModel.orderedStops.contains(where: { $0.disruption != nil }) ? DS.Color.statusMajor : DS.Color.inkMute)
                }
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

    /// Correspondances de l'arrêt, groupées par mode (métro, tram, bus) comme
    /// dans l'app STIB : une pastille de mode, puis les numéros de ligne.
    ///
    /// C'est souvent l'information la plus utile de la liste — savoir qu'on
    /// peut sauter sur un 25 à Gare du Nord vaut plus que l'attente de la
    /// ligne qu'on est en train de regarder.
    @ViewBuilder
    private var connectionsView: some View {
        let grouped = Self.groupedByMode(stop.connectingLines)
        if !grouped.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                ForEach(grouped, id: \.mode) { group in
                    HStack(spacing: 5) {
                        Image(systemName: group.mode.sfSymbol)
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(DS.Color.paper)
                            .frame(width: 17, height: 17)
                            .background(Circle().fill(DS.Color.statusMajor))

                        ForEach(group.lines, id: \.self) { line in
                            LineBadge(line: line, size: .sm)
                        }
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.top, 1)
        }
    }

    /// Métro d'abord, puis tram, puis bus — l'ordre de l'app STIB. Les numéros
    /// sont triés numériquement (2, 10, 25 et non 10, 2, 25).
    private static func groupedByMode(_ lines: [String]) -> [(mode: TransitLineMode, lines: [String])] {
        var buckets: [TransitLineMode: [String]] = [:]
        for line in lines {
            buckets[TransitLineMode.mode(for: line), default: []].append(line)
        }
        let order: [TransitLineMode] = [.metro, .tram, .bus]
        var result: [(mode: TransitLineMode, lines: [String])] = []
        for mode in order {
            guard let bucket = buckets[mode], !bucket.isEmpty else { continue }
            let sorted = bucket.sorted { left, right in
                let leftNumber = Int(left.filter(\.isNumber))
                let rightNumber = Int(right.filter(\.isNumber))
                if let leftNumber, let rightNumber, leftNumber != rightNumber {
                    return leftNumber < rightNumber
                }
                return left.localizedStandardCompare(right) == .orderedAscending
            }
            result.append((mode, sorted))
        }
        return result
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
                            .accessibilityLabel(AppLocalizer.format("a11y.community_reports", defaultValue: "%lld signalements communauté", communityReportCount))
                        }

                        if isTerminus {
                            Text("Terminus")
                                .font(DS.Font.labelSmall)
                                .tracking(1.2)
                                .foregroundStyle(DS.Color.inkMute)
                        }

                        if onTap != nil {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }

                    connectionsView

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
                            .font(DS.Font.labelLarge)
                            .foregroundStyle(DS.Color.ink)
                        if stop.vehiclePresent {
                            // A live vehicle of this direction is here right now.
                            Text("À L'ARRÊT")
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.8)
                                .foregroundStyle(DS.Color.statusOK)
                        } else if let delay = stop.delayMinutes, delay > 2 {
                            Text("+\(delay) min")
                                .font(DS.Font.labelSmall)
                                .foregroundStyle(DS.Color.statusMajor)
                        } else if stop.waitsSource == "scheduled" {
                            Text(AppLocalizer.string("théorique", defaultValue: "théorique"))
                                .font(DS.Font.labelSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        // Second upcoming passage shown as an absolute "puis N
                        // min" rather than the old "+N" which read like a delay
                        // and confused the real next-passage time.
                        if stop.waits.count > 1 {
                            Text("puis \(stop.waits[1]) min")
                                .font(DS.Font.labelSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                } else {
                    Text("--")
                        .font(DS.Font.label)
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

/// Pulsation douce des blocs de chargement (skeleton). Volontairement lente
/// (1,1 s) : une pulsation rapide donne une impression de nervosité alors
/// qu'on veut juste dire « patiente, ça arrive ».
private struct SkeletonPulse: ViewModifier {
    @State private var dim = false

    func body(content: Content) -> some View {
        content
            .opacity(dim ? 0.55 : 1)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.1).repeatForever(autoreverses: true)) {
                    dim = true
                }
            }
    }
}
