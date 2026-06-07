import CoreLocation
import SwiftUI
import UIKit

/// Onboarding step that lets the user pick favourite stops across all four
/// operators (STIB, SNCB, De Lijn, TEC) — so the app feels populated as soon
/// as they finish signing up. STIB stops are queued in `OnboardingPreferenceStore`
/// (applied to the backend favourites post sign-in); SNCB / De Lijn / TEC are
/// saved instantly to their local stores.
struct OnboardingFavoritesStep: View {
    let onContinue: () -> Void
    let onSkip: () -> Void

    @StateObject private var locator = OneShotLocationManager()
    @ObservedObject private var gareFavorites = SNCBGareFavorites.shared
    @ObservedObject private var operatorFavorites = OperatorStopFavorites.shared

    @State private var selectedOperator: TransitOperator = .stib
    @State private var stibStops: [NearbyStop] = []
    @State private var stibSelectedIds: Set<String> = Set(OnboardingPreferenceStore.load().stibFavoriteStopIds)
    @State private var isLoadingStib = true

    @State private var sncbStations: [SNCBStation] = []
    @State private var isLoadingSncb = true

    @State private var delijnStops: [OperatorMapStop] = []
    @State private var tecStops: [OperatorMapStop] = []
    @State private var isLoadingDelijn = true
    @State private var isLoadingTec = true
    @State private var locationState: LocationState = .requesting

    @State private var userCoordinate: CLLocationCoordinate2D = OneShotLocationManager.fallback
    @State private var isSeedingFallback = false

    // Recherche d'arrêts (n'importe quel arrêt, pas seulement ceux à proximité).
    @State private var searchQuery = ""
    @State private var stibSearchResults: [NearbyStop] = []
    @State private var isSearchingStib = false

    private static let brusselsCenterFallbackNames: [String] = [
        "DE BROUCKERE", "BOURSE", "GARE CENTRALE"
    ]
    private static let brusselsCenter = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    private var totalSelected: Int {
        stibSelectedIds.count + gareFavorites.ids.count + operatorFavorites.stops.count
    }
    private let minimumStops = 3
    private var canContinue: Bool { totalSelected >= minimumStops }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    counter
                    if locationState == .ready {
                        TransitOperatorRow(
                            activeOperator: selectedOperator,
                            enabledOperators: [.stib, .sncb, .delijn, .tec],
                            onSelect: { selectedOperator = $0 }
                        )
                        searchField
                        operatorContent
                    } else {
                        locationGate
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 180)
            }

            VStack(spacing: 10) {
                continueButton
                Button(action: handleSkip) {
                    HStack(spacing: 6) {
                        if isSeedingFallback {
                            ProgressView()
                                .tint(DS.Color.inkMute)
                                .scaleEffect(0.75)
                        }
                        Text(totalSelected == 0
                             ? "Je découvre avec 3 arrêts du centre"
                             : "Je découvre d'abord")
                            .font(DS.Font.mono).tracking(1.4).textCase(.uppercase)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
                .disabled(isSeedingFallback)
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .background(
                LinearGradient(
                    colors: [DS.Color.background.opacity(0), DS.Color.background, DS.Color.background],
                    startPoint: .top, endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(DS.Color.background)
        .task { await loadAll() }
        .task(id: searchQuery) { await runStibSearch() }
    }

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Recherche

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
            TextField(
                AppLocalizer.string("onboarding.fav.search_ph", defaultValue: "Rechercher un arrêt…"),
                text: $searchQuery
            )
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.ink)
            .autocorrectionDisabled()
            .textInputAutocapitalization(.never)
            .submitLabel(.search)
            if isSearchingStib && selectedOperator == .stib {
                ProgressView().tint(DS.Color.inkMute).scaleEffect(0.7)
            } else if !trimmedQuery.isEmpty {
                Button {
                    searchQuery = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    /// Recherche STIB côté backend (tous les arrêts, pas seulement à proximité).
    /// Débouncée via `.task(id:)` qui s'annule à chaque frappe.
    @MainActor
    private func runStibSearch() async {
        let query = trimmedQuery
        guard query.count >= 2 else {
            stibSearchResults = []
            isSearchingStib = false
            return
        }
        isSearchingStib = true
        try? await Task.sleep(nanoseconds: 300_000_000) // debounce 0.3s
        if Task.isCancelled { return }
        do {
            let results = try await NearbyStopService.searchStopsByName(query)
            if Task.isCancelled { return }
            stibSearchResults = dedupedRealStibStops(results).prefix(40).map { $0 }
        } catch {
            stibSearchResults = []
        }
        isSearchingStib = false
    }

    private func nameMatchesQuery(_ name: String) -> Bool {
        let q = trimmedQuery
        guard !q.isEmpty else { return true }
        return normalizedStopName(name).contains(normalizedStopName(q))
    }

    private enum LocationState {
        case requesting
        case denied
        case ready
    }

    // MARK: - Header / counter / continue

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ÉTAPE 1 / 3")
                .font(DS.Font.mono).tracking(2).foregroundStyle(DS.Color.inkMute)
            Text("Choisis tes arrêts favoris")
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(DS.Color.ink)
            Text("Au moins \(minimumStops) arrêts pour une meilleure expérience. Tu peux mélanger les opérateurs.")
                .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
        }
    }

    private var counter: some View {
        HStack(spacing: 8) {
            Image(systemName: "star.fill").font(.system(size: 12, weight: .bold)).foregroundStyle(DS.Color.primary)
            Text("\(totalSelected) / \(minimumStops) arrêts")
                .font(DS.Font.bodyBold)
                .foregroundStyle(canContinue ? DS.Color.statusOK : DS.Color.ink)
            Spacer()
        }
        .padding(.horizontal, 14).padding(.vertical, 10)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.ink.opacity(canContinue ? 0.5 : 0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var locationGate: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: locationState == .requesting ? "location.fill" : "location.slash.fill")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(locationState == .requesting ? DS.Color.primary : DS.Color.statusMajor)
                    .frame(width: 46, height: 46)
                    .background((locationState == .requesting ? DS.Color.primary : DS.Color.statusMajor).opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(locationState == .requesting ? "Localisation en cours" : "Position nécessaire")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                    Text(locationState == .requesting
                         ? "Autorise ta position pour afficher les vrais arrêts proches de toi."
                         : "Sans position, on ne peut pas proposer des arrêts réellement à proximité.")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if locationState == .requesting {
                ProgressView()
                    .tint(DS.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Button {
                    openAppSettings()
                } label: {
                    Text("Ouvrir les réglages")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(16)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var continueButton: some View {
        Button {
            persistAndContinue()
        } label: {
            HStack(spacing: 10) {
                Text(canContinue ? "Continuer avec \(totalSelected) arrêts" : "Choisis au moins \(minimumStops) arrêts")
                Image(systemName: "arrow.right")
            }
            .font(DesignSystem.Typography.bodyStrong)
            .foregroundStyle(DS.Color.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.ButtonHeight.primary)
            .background(canContinue ? DS.Color.primary : DS.Color.ink.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(canContinue ? 0.95 : 0.18), lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
    }

    private func persistAndContinue() {
        let existing = OnboardingPreferenceStore.load()
        OnboardingPreferenceStore.save(OnboardingPreferences(
            favoriteLines: existing.favoriteLines,
            stibFavoriteStopIds: Array(stibSelectedIds),
            homeLabel: existing.homeLabel,
            departureTime: existing.departureTime
        ))
        AppHaptics.success()
        onContinue()
    }

    private func handleSkip() {
        guard totalSelected == 0 else {
            persistSkipState()
            onSkip()
            return
        }

        // Empty skip = guaranteed empty Home. Auto-seed 3 Brussels-centre stops
        // so the user lands on a populated home instead of nothing.
        isSeedingFallback = true
        Task {
            let ids = await fetchBrusselsCenterFallbackIds()
            await MainActor.run {
                if !ids.isEmpty {
                    stibSelectedIds.formUnion(ids)
                }
                persistSkipState()
                isSeedingFallback = false
                AppHaptics.soft()
                onSkip()
            }
        }
    }

    private func persistSkipState() {
        let existing = OnboardingPreferenceStore.load()
        OnboardingPreferenceStore.save(OnboardingPreferences(
            favoriteLines: existing.favoriteLines,
            stibFavoriteStopIds: Array(stibSelectedIds),
            homeLabel: existing.homeLabel,
            departureTime: existing.departureTime
        ))
    }

    private func fetchBrusselsCenterFallbackIds() async -> [String] {
        // Use the centre Brussels coordinate even if user denied location —
        // fetchNearby doesn't need device location, only raw coords.
        let stops: [NearbyStop]
        do {
            stops = try await NearbyStopService.fetchNearby(
                lat: Self.brusselsCenter.latitude,
                lng: Self.brusselsCenter.longitude,
                radius: 900
            )
        } catch {
            return []
        }

        var picked: [String] = []
        for target in Self.brusselsCenterFallbackNames {
            let match = stops.first { stop in
                guard let _ = stop.backendId else { return false }
                let normalized = normalizedStopName(stop.name)
                return normalized.contains(target)
            }
            if let id = match?.backendId, !picked.contains(id) {
                picked.append(id)
            }
        }
        return picked
    }

    // MARK: - Operator content

    @ViewBuilder
    private var operatorContent: some View {
        switch selectedOperator {
        case .stib: stibList
        case .sncb: sncbList
        case .delijn: operatorList(.delijn)
        case .tec: operatorList(.tec)
        }
    }

    private var displayedStibStops: [NearbyStop] {
        trimmedQuery.isEmpty ? stibStops : stibSearchResults
    }

    private var stibList: some View {
        VStack(spacing: 0) {
            if trimmedQuery.isEmpty && isLoadingStib && stibStops.isEmpty {
                loadingRow
            } else if !trimmedQuery.isEmpty && isSearchingStib && stibSearchResults.isEmpty {
                loadingRow
            } else if displayedStibStops.isEmpty {
                emptyRow(trimmedQuery.isEmpty
                    ? AppLocalizer.string("onboarding.fav.empty_stib", defaultValue: "Aucun arrêt STIB à proximité.")
                    : AppLocalizer.string("onboarding.fav.empty_search", defaultValue: "Aucun arrêt trouvé. Essaie un autre nom."))
            } else {
                ForEach(displayedStibStops) { stop in
                    selectableRow(
                        title: stop.name,
                        subtitle: stop.distanceMeters > 0 ? "\(stop.distanceMeters) m · STIB" : "STIB",
                        lines: stop.lines,
                        operatorColor: TransitOperator.stib.brandColor,
                        operatorAsset: TransitOperator.stib.assetName,
                        isSelected: stibSelectionId(for: stop).map { stibSelectedIds.contains($0) } ?? false,
                        onToggle: {
                            guard let id = stibSelectionId(for: stop) else { return }
                            if stibSelectedIds.contains(id) { stibSelectedIds.remove(id) }
                            else { stibSelectedIds.insert(id) }
                            AppHaptics.soft()
                        }
                    )
                }
            }
        }
        .modifier(SectionContainer())
    }

    private var sncbList: some View {
        let stations = trimmedQuery.isEmpty ? sncbStations : sncbStations.filter { nameMatchesQuery($0.displayName) }
        return VStack(spacing: 0) {
            if isLoadingSncb && sncbStations.isEmpty {
                loadingRow
            } else if stations.isEmpty {
                emptyRow(trimmedQuery.isEmpty
                    ? AppLocalizer.string("onboarding.fav.empty_sncb", defaultValue: "Aucune gare SNCB à proximité.")
                    : AppLocalizer.string("onboarding.fav.empty_search", defaultValue: "Aucun arrêt trouvé. Essaie un autre nom."))
            } else {
                ForEach(stations) { station in
                    selectableRow(
                        title: station.displayName,
                        subtitle: "\(station.displayProvince) · Gare SNCB",
                        operatorColor: TransitOperator.sncb.brandColor,
                        operatorAsset: TransitOperator.sncb.assetName,
                        isSelected: gareFavorites.contains(station.id),
                        onToggle: {
                            gareFavorites.toggle(station.id)
                            AppHaptics.soft()
                        }
                    )
                }
            }
        }
        .modifier(SectionContainer())
    }

    @ViewBuilder
    private func operatorList(_ op: TransitOperator) -> some View {
        let allStops = op == .delijn ? delijnStops : tecStops
        let stops = trimmedQuery.isEmpty ? allStops : allStops.filter { nameMatchesQuery($0.name) }
        let loading = op == .delijn ? isLoadingDelijn : isLoadingTec
        VStack(spacing: 0) {
            if loading && allStops.isEmpty {
                loadingRow
            } else if stops.isEmpty {
                emptyRow(trimmedQuery.isEmpty
                    ? AppLocalizer.format("onboarding.fav.empty_operator", defaultValue: "Aucun arrêt %@ à proximité.", op.mapLabel)
                    : AppLocalizer.string("onboarding.fav.empty_search", defaultValue: "Aucun arrêt trouvé. Essaie un autre nom."))
            } else {
                ForEach(stops) { stop in
                    selectableRow(
                        title: stop.name,
                        subtitle: "Arrêt \(op.mapLabel)",
                        operatorColor: op.brandColor,
                        operatorAsset: op.assetName,
                        isSelected: operatorFavorites.contains(stop.id),
                        onToggle: {
                            let fav = FavoriteOperatorStop(op: op.rawValue, stopId: stop.id, name: stop.name, lat: stop.lat, lng: stop.lng)
                            operatorFavorites.toggle(fav)
                            AppHaptics.soft()
                        }
                    )
                }
            }
        }
        .modifier(SectionContainer())
    }

    // MARK: - Row helpers

    private func selectableRow(title: String, subtitle: String, lines: [StopLine] = [], operatorColor: Color, operatorAsset: String, isSelected: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(operatorAsset)
                    .renderingMode(.original).resizable().scaledToFit()
                    .frame(width: 28, height: 28).frame(width: 42, height: 42)
                    .background(operatorColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink).lineLimit(1)
                    Text(subtitle).font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute).lineLimit(1)
                    if !lines.isEmpty {
                        lineBadges(lines)
                    }
                }
                Spacer()
                Image(systemName: isSelected ? "checkmark.circle.fill" : "plus.circle")
                    .font(.system(size: 22))
                    .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.inkMute)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(DS.Color.paper)
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    /// Badges des lignes qui passent par l'arrêt (numéro + couleur officielle),
    /// affichés sous le nom — limité à 8 pour ne pas surcharger la rangée.
    private func lineBadges(_ lines: [StopLine]) -> some View {
        let shown = Array(lines.prefix(8))
        return HStack(spacing: 4) {
            ForEach(shown) { line in
                Text(line.number)
                    .font(.system(size: 10, weight: .heavy))
                    .foregroundStyle(line.color.isDark ? Color.white : Color.black)
                    .padding(.horizontal, 6)
                    .frame(minWidth: 22, minHeight: 18)
                    .background(line.color)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
            if lines.count > shown.count {
                Text("+\(lines.count - shown.count)")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
    }

    private var loadingRow: some View {
        HStack { ProgressView().tint(DS.Color.ink); Spacer() }
            .padding(.vertical, 32).frame(maxWidth: .infinity)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(verbatim: text)
            .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
            .padding(.vertical, 20).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading

    @MainActor
    private func loadAll() async {
        locationState = .requesting
        guard let coordinate = await locator.requestCurrentLocation() else {
            locationState = .denied
            isLoadingStib = false
            isLoadingSncb = false
            isLoadingDelijn = false
            isLoadingTec = false
            return
        }

        userCoordinate = coordinate
        locationState = .ready
        // STIB nearby + SNCB nearest + De Lijn/TEC viewport in parallel
        async let stib: () = loadStib()
        async let sncb: () = loadSncb()
        async let delijn: () = loadOperator(.delijn)
        async let tec: () = loadOperator(.tec)
        _ = await (stib, sncb, delijn, tec)
    }

    @MainActor
    private func loadStib() async {
        isLoadingStib = true
        defer { isLoadingStib = false }
        do {
            let stops = try await NearbyStopService.fetchNearby(lat: userCoordinate.latitude, lng: userCoordinate.longitude, radius: 1500)
            var candidates = dedupedRealStibStops(stops)

            // TestFlight showed cases where the map had STIB data but the
            // onboarding radius returned nothing. Keep the step usable with
            // real backend/catalog stops from central Brussels instead of an
            // empty "no STIB nearby" state.
            if candidates.isEmpty {
                let fallbackStops = try await NearbyStopService.fetchNearby(
                    lat: Self.brusselsCenter.latitude,
                    lng: Self.brusselsCenter.longitude,
                    radius: 1200
                )
                candidates = dedupedRealStibStops(fallbackStops)
            }

            stibStops = candidates.prefix(25).map { $0 }
        } catch {
            stibStops = []
        }
    }

    @MainActor
    private func loadSncb() async {
        isLoadingSncb = true
        defer { isLoadingSncb = false }
        let nearest = SNCBStationService.nearbyStations(around: userCoordinate, radiusMeters: 35_000, limit: 25)
        sncbStations = nearest.map(\.station)
    }

    @MainActor
    private func loadOperator(_ op: TransitOperator) async {
        let setLoading: (Bool) -> Void = { v in
            if op == .delijn { isLoadingDelijn = v } else { isLoadingTec = v }
        }
        setLoading(true)
        defer { setLoading(false) }
        func fetch(_ d: Double) async -> [OperatorMapStop] {
            await OperatorStopService.stops(
                operator: op,
                minLat: userCoordinate.latitude - d, maxLat: userCoordinate.latitude + d,
                minLng: userCoordinate.longitude - d, maxLng: userCoordinate.longitude + d,
                limit: 80
            )
        }
        var stops = await fetch(0.03)
        if stops.isEmpty { stops = await fetch(0.09) }
        let originLoc = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let sorted = stops
            .sorted {
                originLoc.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))
                    < originLoc.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lng))
            }
            .prefix(25)
            .map { $0 }
        if op == .delijn { delijnStops = sorted } else { tecStops = sorted }
    }

    private func dedupedRealStibStops(_ stops: [NearbyStop]) -> [NearbyStop] {
        var bestByName: [String: NearbyStop] = [:]

        for stop in stops {
            let key = normalizedStopName(stop.name)
            guard !key.isEmpty, !key.contains("TEST") else { continue }

            if let current = bestByName[key] {
                if stop.distanceMeters < current.distanceMeters {
                    bestByName[key] = stop
                }
            } else {
                bestByName[key] = stop
            }
        }

        return bestByName.values.sorted {
            if $0.distanceMeters == $1.distanceMeters {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.distanceMeters < $1.distanceMeters
        }
    }

    private func stibSelectionId(for stop: NearbyStop) -> String? {
        stop.backendId ?? stop.stopId
    }

    private func normalizedStopName(_ name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocale.current)
            .replacingOccurrences(of: #"[^A-Z0-9]+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

private struct SectionContainer: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}
