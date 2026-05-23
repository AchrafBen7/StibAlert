import CoreLocation
import SwiftUI

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

    @State private var userCoordinate: CLLocationCoordinate2D = OneShotLocationManager.fallback

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
                    TransitOperatorRow(
                        activeOperator: selectedOperator,
                        enabledOperators: [.stib, .sncb, .delijn, .tec],
                        onSelect: { selectedOperator = $0 }
                    )
                    operatorContent
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 180)
            }

            VStack(spacing: 10) {
                continueButton
                Button(action: onSkip) {
                    Text("Je découvre d'abord")
                        .font(DS.Font.mono).tracking(1.4).textCase(.uppercase)
                        .foregroundStyle(DS.Color.inkMute)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.plain)
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

    private var stibList: some View {
        VStack(spacing: 0) {
            if isLoadingStib && stibStops.isEmpty {
                loadingRow
            } else if stibStops.isEmpty {
                emptyRow("Aucun arrêt STIB à proximité.")
            } else {
                ForEach(stibStops) { stop in
                    selectableRow(
                        title: stop.name,
                        subtitle: "\(stop.distanceMeters) m · STIB",
                        operatorColor: TransitOperator.stib.brandColor,
                        operatorAsset: TransitOperator.stib.assetName,
                        isSelected: stop.backendId.map { stibSelectedIds.contains($0) } ?? false,
                        onToggle: {
                            guard let id = stop.backendId else { return }
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
        VStack(spacing: 0) {
            if isLoadingSncb && sncbStations.isEmpty {
                loadingRow
            } else if sncbStations.isEmpty {
                emptyRow("Aucune gare SNCB à proximité.")
            } else {
                ForEach(sncbStations) { station in
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
        let stops = op == .delijn ? delijnStops : tecStops
        let loading = op == .delijn ? isLoadingDelijn : isLoadingTec
        VStack(spacing: 0) {
            if loading && stops.isEmpty {
                loadingRow
            } else if stops.isEmpty {
                emptyRow("Aucun arrêt \(op.mapLabel) à proximité.")
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

    private func selectableRow(title: String, subtitle: String, operatorColor: Color, operatorAsset: String, isSelected: Bool, onToggle: @escaping () -> Void) -> some View {
        Button(action: onToggle) {
            HStack(spacing: 12) {
                Image(operatorAsset)
                    .renderingMode(.original).resizable().scaledToFit()
                    .frame(width: 28, height: 28).frame(width: 42, height: 42)
                    .background(operatorColor.opacity(0.10))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink).lineLimit(1)
                    Text(subtitle).font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute).lineLimit(1)
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

    private var loadingRow: some View {
        HStack { ProgressView().tint(DS.Color.ink); Spacer() }
            .padding(.vertical, 32).frame(maxWidth: .infinity)
    }

    private func emptyRow(_ text: String) -> some View {
        Text(text)
            .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
            .padding(.vertical, 20).padding(.horizontal, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Loading

    @MainActor
    private func loadAll() async {
        userCoordinate = await locator.getCurrentLocation()
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
            stibStops = stops.prefix(25).map { $0 }
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
