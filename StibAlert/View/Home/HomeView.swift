import SwiftUI
import MapKit
import WidgetKit

enum MapFilter { case none, favorites, perturbations }

struct HomeView: View {
    private enum InteractionMode: Equatable {
        case map
        case stopPreview
        case stopDetail
        case routePreview
        case routeDetail
        case ar
    }

    private enum HomeSurfaceMode: Equatable {
        case unavailable
        case stopDetail
        case ar
        case routeDetail
        case routePreview
        case stopPreview
        case signalementPreview
        case mapIdle
    }

    @EnvironmentObject var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var connectivity: NetworkConnectivityMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject var locationManager = HomeLocationManager()
    @StateObject private var realtimeSignalements = SignalementsRealtimeService()
    @StateObject private var vehicleTracker = VehicleTrackingService()
    @ObservedObject private var lineShapesLoader = LineShapesLoader.shared

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )
    @State private var showSearch = false
    @State var showLegend = false
    @State var showRoutePlanner = false
    @State var selectedSignalementPreview: SignalementDTO? = nil
    @State private var lastFetchedAt: Date? = nil
    @State private var currentRoute: MKRoute? = nil
    @State private var currentRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var destinationCoord: CLLocationCoordinate2D? = nil
    @State private var routeOptions: [HomeRouteOption] = []
    @State private var routeModeSummaries: [RouteModeSummary] = []
    @State private var selectedRouteID: UUID?
    @State private var isRouteSheetExpanded = false
    @State private var selectedRouteDetail: HomeRouteOption?
    @State private var selectedARRoute: HomeRouteOption?
    @State var searchQuery = ""
    @State var searchSuggestions: [MKMapItem] = []
    @State var isRouting = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State var remoteSignalements: [SignalementDTO] = []
    @State private var signalementsPage = 1
    @State private var signalementsTotalPages = 1
    @State private var isLoadingSignalements = false
    @State private var hasLoadedSignalements = false
    @State private var signalementLoadError: String? = nil
    @State private var transportOverview: TransportOverviewDTO?
    @State private var currentTransportRecommendation: TransportRecommendationDTO?
    @State private var isLoadingTransportOverview = false
    @State private var selectedAlternativeDetail: TransportAlternativeDTO?
    @State private var selectedMapStopPreview: TransportStopSummaryDTO?
    @State private var selectedMapStopSummary: TransportStopSummaryDTO?
    @State private var selectedMapStopDetail: TransportStopDTO?
    @State private var selectedStopLineNumber: String?
    @State private var isLoadingMapStopDetail = false
    @State private var mapStopDetailError: String?
    @State private var eventImpacts: [TransportEventImpactDTO] = []
    @State private var selectedEventImpact: TransportEventImpactDTO?
    @State private var showVilloStations = true
    @State private var showEventImpacts = true
    @State private var selectedVilloStation: VilloStation?
    @State private var problemFilter: ReportProblemType? = nil
    @State var activeMapFilter: MapFilter = .none
    @State private var cameraLatitudeDelta: Double = 0.04
    @State private var showReportAuthGate = false
    @State private var guestGateReason: GuestAuthReason = .report
    @State private var hasBootstrappedHomeData = false
    @State private var homeRefreshTask: Task<Void, Never>? = nil
    @State var lastHomeRefreshAt: Date? = nil
    @State private var lastHomeSurfaceRefreshCoordinate: CLLocationCoordinate2D? = nil
    @State private var lastMapStopsRefreshCoordinate: CLLocationCoordinate2D? = nil
    @State private var hasAutoCenteredOnUser = false
    @State private var isFollowingUser = true
    @State private var suppressNextCameraInteraction = false
    @State private var cameraCenterCoordinate = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
    @State private var catalogMapStops: [NearbyStop] = []
    @State private var mapStopsTask: Task<Void, Never>? = nil
    @State private var interactionMode: InteractionMode = .map

    @State private var activeClusters: [ClusterDTO] = []
    @State var selectedClusterIndex: Int? = nil
    @State private var clustersTask: Task<Void, Never>? = nil
    @State private var lastClustersFetchCoordinate: CLLocationCoordinate2D? = nil

    @State private var showDecisionSheet = false
    @State private var hasAutoShownDecision = false
    @State var tripDestination: TripDestination? = nil
    @State private var showDestinationPicker = false

    struct TripDestination: Identifiable, Equatable {
        let id = UUID()
        let coordinate: CLLocationCoordinate2D
        let label: String?

        static func == (lhs: TripDestination, rhs: TripDestination) -> Bool {
            lhs.id == rhs.id
        }
    }

    struct LiveSignalPoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let typeProbleme: String
        let source: String?
    }

    struct RouteOfficialSignalPoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let severity: String?
        let stop: TransportStopSummaryDTO?
    }

    struct RouteMapSegment: Identifiable {
        let id: String
        let coordinates: [CLLocationCoordinate2D]
        let color: Color
        let lineWidth: CGFloat
    }

    private var filteredSignalements: [SignalementDTO] {
        guard let filter = problemFilter else { return remoteSignalements }
        return remoteSignalements.filter { $0.typeProbleme == filter.title }
    }

    private var liveSignalPoints: [LiveSignalPoint] {
        filteredSignalements.compactMap { s in
            guard let lat = s.latitude, let lng = s.longitude else { return nil }
            return LiveSignalPoint(
                id: s.id,
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                typeProbleme: s.displayTypeProbleme,
                source: s.source
            )
        }
    }

    private var officialSignalPoints: [LiveSignalPoint] {
        liveSignalPoints.filter { $0.source == "stib_officiel" }
    }

    private var mapClusters: [MapSignalCluster] {
        let communityPoints = liveSignalPoints.filter { $0.source != "stib_officiel" }
        return MapSignalClusterer.cluster(
            points: communityPoints.map { MapSignalClusterer.Input(id: $0.id, coordinate: $0.coordinate, typeProbleme: $0.typeProbleme) },
            latitudeDelta: cameraLatitudeDelta
        )
    }

    private var visibleLineNumbers: Set<String> {
        var numbers = Set<String>()
        if let favs = session.currentUser?.favoriteLines {
            numbers.formUnion(favs)
        }
        numbers.formUnion(remoteSignalements.map(\.ligne))
        if let selectedRouteOption {
            numbers.formUnion(selectedRouteOption.displayLineCodes)
        }
        return numbers
    }

    private var widgetFavoriteLineNumbers: Set<String> {
        Set(session.currentUser?.favoriteLines ?? [])
    }

    private var trackedVehicleLineNumbers: Set<String> {
        guard let selectedRouteOption else { return [] }
        return Set(selectedRouteOption.displayLineCodes)
    }

    private var visibleLineShapes: [LineShape] {
        guard selectedRouteOption == nil else { return [] }
        guard selectedStopLineNumber == nil else { return [] }
        guard cameraLatitudeDelta <= 0.05 else { return [] }
        return lineShapesLoader.shapes(matchingNumbers: visibleLineNumbers)
    }

    private var selectedStopLineShapes: [LineShape] {
        guard selectedRouteOption == nil, let selectedStopLineNumber else { return [] }
        return lineShapesLoader.shapes(matchingNumbers: [selectedStopLineNumber])
    }

    private var mapVehicles: [TransportVehicleDTO] {
        guard cameraLatitudeDelta <= 0.12 else { return [] }
        guard let selectedRouteOption else { return [] }
        if let trackedVehicle = trackedVehicle(for: selectedRouteOption) {
            return [trackedVehicle]
        }
        return []
    }

    private var routeOfficialSignalPoints: [RouteOfficialSignalPoint] {
        guard let selectedRouteOption else { return [] }
        let stopNames = Set(
            (selectedRouteOption.backendAlternative?.steps ?? []).flatMap { step in
                [step.stopName, step.arrivalStopName]
            }
            .compactMap { $0?.normalizedStopKey }
        )
        let routeLines = Set(selectedRouteOption.displayLineCodes)

        return (currentTransportRecommendation?.activeIncidents ?? [])
            .filter { $0.source == "official" }
            .filter { incident in
                guard let stop = incident.stop,
                      let latitude = stop.latitude,
                      let longitude = stop.longitude else { return false }
                _ = latitude
                _ = longitude
                let lineMatches: Bool
                if let line = incident.line {
                    lineMatches = routeLines.contains(line)
                } else {
                    lineMatches = false
                }

                let stopMatches: Bool
                if let stopName = stop.name?.normalizedStopKey {
                    stopMatches = stopNames.contains(stopName)
                } else {
                    stopMatches = false
                }
                return lineMatches || stopMatches
            }
            .compactMap { incident in
                guard let stop = incident.stop,
                      let latitude = stop.latitude,
                      let longitude = stop.longitude else { return nil }
                let summary = stop.id.map {
                    TransportStopSummaryDTO(
                        id: $0,
                        stopId: stop.stopId,
                        name: stop.name ?? "Arrêt STIB",
                        latitude: latitude,
                        longitude: longitude,
                        lines: incident.line.map { [$0] } ?? []
                    )
                }
                return RouteOfficialSignalPoint(
                    id: incident.id,
                    coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    title: incident.type ?? "Alerte STIB",
                    severity: incident.severity,
                    stop: summary
                )
            }
    }

    private var mapStops: [TransportStopSummaryDTO] {
        if let selectedRouteOption {
            return routeScopedStops(for: selectedRouteOption)
        }

        return baseMapStops
    }

    private var baseMapStops: [TransportStopSummaryDTO] {
        guard cameraLatitudeDelta <= 0.07 else { return [] }

        let catalogStops = catalogMapStops.compactMap { stop -> TransportStopSummaryDTO? in
            guard let coordinate = stop.coordinate else { return nil }
            guard let backendId = stop.backendId else { return nil }
            return TransportStopSummaryDTO(
                id: backendId,
                stopId: stop.stopId,
                name: stop.name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                lines: stop.lines.map(\.number)
            )
        }

        let fallbackStops = (transportOverview?.stops ?? []).filter { $0.latitude != nil && $0.longitude != nil }
        if catalogStops.isEmpty {
            return fallbackStops
        }

        let fallbackById = Dictionary(uniqueKeysWithValues: fallbackStops.map { ($0.id, $0) })
        var merged: [TransportStopSummaryDTO] = []
        var seen = Set<String>()

        for stop in catalogStops {
            let enriched = fallbackById[stop.id] ?? stop
            if seen.insert(enriched.id).inserted {
                merged.append(enriched)
            }
        }

        for stop in fallbackStops where seen.insert(stop.id).inserted {
            merged.append(stop)
        }

        switch activeMapFilter {
        case .favorites:
            let favLines = Set(session.currentUser?.favoriteLines ?? [])
            guard !favLines.isEmpty else { return merged }
            return merged.filter { !$0.lines.filter { favLines.contains($0) }.isEmpty }
        case .perturbations:
            let affectedLines = Set(remoteSignalements.filter { $0.status != "resolved" }.map { $0.ligne })
            guard !affectedLines.isEmpty else { return merged }
            return merged.filter { !$0.lines.filter { affectedLines.contains($0) }.isEmpty }
        case .none:
            return merged
        }
    }

    private var selectedRouteOption: HomeRouteOption? {
        if let selectedRouteID,
           let selected = routeOptions.first(where: { $0.id == selectedRouteID }) {
            return selected
        }
        return routeOptions.first
    }

    private var routeMapSegments: [RouteMapSegment] {
        guard let selectedRouteOption else { return [] }

        if let backendAlternative = selectedRouteOption.backendAlternative,
           let steps = backendAlternative.steps, !steps.isEmpty {
            let sortedSteps = steps.sorted { $0.order < $1.order }
            var segments: [RouteMapSegment] = []

            for (index, step) in sortedSteps.enumerated() {
                let coordinates = HomeRouteOption.segmentCoordinates(for: step)
                guard coordinates.count > 1 else { continue }
                let color = HomeRouteOption.mapStrokeColor(for: step)
                let width = HomeRouteOption.mapStrokeWidth(for: step)
                segments.append(RouteMapSegment(
                    id: "\(selectedRouteOption.id.uuidString)-\(step.id)",
                    coordinates: coordinates,
                    color: color,
                    lineWidth: width
                ))

                guard index < sortedSteps.count - 1 else { continue }
                let nextStep = sortedSteps[index + 1]
                let nextCoordinates = HomeRouteOption.segmentCoordinates(for: nextStep)
                guard let end = coordinates.last, let nextStart = nextCoordinates.first else { continue }
                guard coordinateDistance(from: end, to: nextStart) > 2 else { continue }

                segments.append(
                    RouteMapSegment(
                        id: "\(selectedRouteOption.id.uuidString)-bridge-\(step.id)-\(nextStep.id)",
                        coordinates: [end, nextStart],
                        color: DS.Color.ink.opacity(0.28),
                        lineWidth: 4
                    )
                )
            }
            if !segments.isEmpty {
                return segments
            }
        }

        guard selectedRouteOption.routeCoordinates.count > 1 else { return [] }
        return [
            RouteMapSegment(
                id: selectedRouteOption.id.uuidString,
                coordinates: selectedRouteOption.routeCoordinates,
                color: DS.Color.primary,
                lineWidth: 5
            )
        ]
    }

    private var mapVilloStations: [VilloStation] {
        guard showVilloStations, cameraLatitudeDelta <= 0.03 else { return [] }
        return VilloStationService.nearbyStations(
            around: locationManager.displayCoordinate,
            radiusMeters: 2200,
            limit: 80
        ).map(\.station)
    }

    private var mapEventImpacts: [TransportEventImpactDTO] {
        guard showEventImpacts, cameraLatitudeDelta <= 0.14 else { return [] }
        return eventImpacts
            .filter(isRelevantMapEvent(_:))
            .filter { $0.latitude != nil && $0.longitude != nil }
    }

    var highlightedEventCount: Int {
        eventImpacts.filter(isRelevantMapEvent(_:)).count
    }

    private var isStopDetailPresented: Bool {
        selectedMapStopSummary != nil
    }

    private var isHomeSurfaceInteractive: Bool {
        nav.currentPage == .home && !nav.showReportSheet && !nav.showSideMenu
    }

    private var hasRouteSurface: Bool {
        !routeOptions.isEmpty || selectedRouteDetail != nil || selectedARRoute != nil
    }

    private var homeSurfaceMode: HomeSurfaceMode {
        guard isHomeSurfaceInteractive else { return .unavailable }
        if interactionMode == .stopDetail, selectedMapStopSummary != nil { return .stopDetail }
        if interactionMode == .ar, selectedARRoute != nil { return .ar }
        if interactionMode == .routeDetail, selectedRouteDetail != nil { return .routeDetail }
        if interactionMode == .routePreview, !routeOptions.isEmpty { return .routePreview }
        if interactionMode == .stopPreview, selectedMapStopPreview != nil, selectedMapStopSummary == nil { return .stopPreview }
        if selectedSignalementPreview != nil, !showLegend, routeOptions.isEmpty { return .signalementPreview }
        return .mapIdle
    }

    var shouldShowSearchHeader: Bool {
        switch homeSurfaceMode {
        case .mapIdle, .routePreview, .signalementPreview:
            return true
        case .unavailable, .stopPreview, .stopDetail, .routeDetail, .ar:
            return false
        }
    }

    var shouldShowSignalementPreview: Bool {
        homeSurfaceMode == .signalementPreview
    }

    var shouldShowPulseBar: Bool {
        homeSurfaceMode == .mapIdle
    }

    var shouldShowTabBar: Bool {
        !nav.showReportSheet
        && !isStopDetailPresented
        && !hasRouteSurface
    }

    private var shouldShowStopPreview: Bool {
        homeSurfaceMode == .stopPreview
    }

    private var shouldShowStopDetail: Bool {
        homeSurfaceMode == .stopDetail
    }

    private var shouldShowRouteSheet: Bool {
        homeSurfaceMode == .routePreview
    }

    private var shouldShowRouteDetail: Bool {
        homeSurfaceMode == .routeDetail
    }

    private var shouldShowAR: Bool {
        homeSurfaceMode == .ar
    }

    var transitionSpring: Animation {
        AppMotion.spring(reduceMotion: reduceMotion)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mapLayer
            OfflineMapFallback(isConnected: connectivity.isConnected)
                .allowsHitTesting(false)
            mapGradient
            controlsLayer
            zstackOverlays
        }
        .overlay(alignment: .bottom) { reportSheetOverlay }
        .overlay(alignment: .top) { searchHeaderOverlay }
        .overlay(alignment: .bottom) { signalementPreviewOverlay }
        .overlay(alignment: .bottom) { clusterDetailOverlay }
        .overlay(alignment: .bottom) { bottomChromeOverlay }
        .guestAuthGate(
            isPresented: $showReportAuthGate,
            reason: guestGateReason,
            onSignIn: {
                nav.authInitialRoute = .signIn
                nav.showAuthFlow = true
            },
            onSignUp: {
                nav.authInitialRoute = .signUp
                nav.showAuthFlow = true
            }
        )
        .sheet(item: $selectedAlternativeDetail) { alternative in
            HomeAlternativeDetailsSheet(
                alternative: alternative,
                onFocusStep: { step in
                    focusMap(on: step)
                }
            )
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: $showRoutePlanner) {
            HomeRoutePlannerSheet(
                isPresented: $showRoutePlanner,
                userCoordinate: locationManager.userCoordinate ?? locationManager.displayCoordinate,
                isRouting: isRouting,
                onPlanRoute: { _, destination, _ in
                    // Route through trip-mode DecisionView so the user sees disruption
                    // awareness BEFORE the route is built. They can launch the trip from there.
                    let coord = destination.placemark.coordinate
                    let label = destination.name ?? destination.placemark.title
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                        tripDestination = HomeView.TripDestination(coordinate: coord, label: label)
                    }
                }
            )
        }
        .sheet(item: $selectedVilloStation) { station in
            HomeVilloStationSheet(station: station)
                .presentationDetents([.height(260), .medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showDecisionSheet) {
            DecisionView(
                coordinate: locationManager.userCoordinate,
                preferredLine: session.currentUser?.favoriteLines?.first,
                onDismiss: { showDecisionSheet = false },
                onOpenMap: { clusterIndex in
                    showDecisionSheet = false
                    selectedClusterIndex = clusterIndex
                },
                onOpenItinerary: { walkStop in
                    showDecisionSheet = false
                    let target = MKMapItem(placemark: MKPlacemark(
                        coordinate: CLLocationCoordinate2D(
                            latitude: walkStop.latitude,
                            longitude: walkStop.longitude
                        )
                    ))
                    target.name = walkStop.name
                    Task { await buildRoute(to: target) }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $tripDestination) { destination in
            DecisionView(
                coordinate: locationManager.userCoordinate,
                preferredLine: nil,
                mode: .trip(destination: destination.coordinate, label: destination.label),
                onDismiss: { tripDestination = nil },
                onLaunchRoute: { destCoord, label in
                    tripDestination = nil
                    let target = MKMapItem(placemark: MKPlacemark(coordinate: destCoord))
                    target.name = label ?? "Destination"
                    Task { await buildRoute(to: target) }
                }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedEventImpact) { event in
            HomeEventImpactSheet(
                event: event,
                onOpenLine: { line in
                    selectedEventImpact = nil
                    nav.pendingLineFocus = line
                    nav.currentPage = .signalements
                },
                onOpenStop: { stopId in
                    selectedEventImpact = nil
                    nav.pendingMapStopFocusBackendId = stopId
                    nav.currentPage = .home
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: nav.showReportSheet)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            locationManager.start()
            realtimeSignalements.connect()
            vehicleTracker.start(lines: trackedVehicleLineNumbers)
            syncFavoritesToWidget(widgetFavoriteLineNumbers)
        }
        .onDisappear {
            realtimeSignalements.disconnect()
            vehicleTracker.stop()
        }
        .onChange(of: widgetFavoriteLineNumbers) { _, newLines in
            syncFavoritesToWidget(newLines)
        }
        .onChange(of: trackedVehicleLineNumbers) { _, newLines in
            vehicleTracker.updateLines(newLines)
        }
        .task { await loadRemoteSignalements() }
        .task { await loadEventImpacts() }
        .task { lineShapesLoader.loadIfNeeded() }
        .task { await refreshCatalogMapStops(force: true) }
        .task { await loadActiveClusters(around: cameraCenterCoordinate) }
        .task(id: locationManager.userCoordinate?.latitude) {
            // Refresh offline map snapshot if user has moved significantly.
            // Runs only when connectivity is good (no point caching half-loaded tiles).
            guard connectivity.isConnected, !connectivity.isConstrained,
                  let coord = locationManager.userCoordinate else { return }
            await MapTileCache.refreshSnapshotIfNeeded(center: coord)
        }
        .task {
            guard !hasBootstrappedHomeData else { return }
            hasBootstrappedHomeData = true
            await refreshHomeSurface(reason: "initial", force: true)
        }
        .onChange(of: nav.showReportSheet) { oldValue, newValue in
            if oldValue && !newValue {
                Task {
                    await loadRemoteSignalements()
                    await refreshHomeSurface(reason: "report_closed", force: true)
                    await loadActiveClusters(around: cameraCenterCoordinate)
                }
            }
        }
        .onChange(of: selectedClusterIndex) { _, newValue in
            if newValue == nil {
                Task { await loadActiveClusters(around: cameraCenterCoordinate) }
            }
        }
        .onReceive(realtimeSignalements.$latestSignalement.compactMap { $0 }) { signalement in
            mergeIncomingSignalement(signalement)
        }
        .onChange(of: nav.currentPage) { _, newValue in
            if newValue == .home, nav.pendingMapStopFocusBackendId != nil {
                Task { await applyPendingMapStopFocusIfPossible() }
            }
        }
        .onChange(of: nav.pendingMapStopFocusBackendId) { _, newValue in
            guard nav.currentPage == .home, newValue != nil else { return }
            Task { await applyPendingMapStopFocusIfPossible() }
        }
        .onReceive(locationManager.$userCoordinate.compactMap { $0 }) { coord in
            if !hasAutoCenteredOnUser || isFollowingUser {
                suppressNextCameraInteraction = true
                withAnimation(.easeInOut(duration: 0.8)) {
                    mapPosition = .region(MKCoordinateRegion(
                        center: coord,
                        span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                    ))
                }
                hasAutoCenteredOnUser = true
            }
            cameraCenterCoordinate = coord
            scheduleCatalogMapStopsRefresh()
            Task { await refreshHomeSurfaceForLocation(coord) }
        }
        .onChange(of: searchQuery) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else {
                searchSuggestions = []
                return
            }
            searchTask = Task {
                try? await Task.sleep(nanoseconds: 250_000_000)
                guard !Task.isCancelled else { return }
                await searchSuggestions(for: trimmed)
            }
        }
    }

    // MARK: - Map layer

    @ViewBuilder private var mapLayer: some View {
        HomeMapLayer(
            mapPosition: $mapPosition,
            visibleLineShapes: visibleLineShapes,
            selectedStopLineShapes: selectedStopLineShapes,
            displayCoordinate: locationManager.displayCoordinate,
            heading: locationManager.heading,
            routeMapSegments: routeMapSegments,
            destinationCoordinate: destinationCoord,
            officialSignalPoints: officialSignalPoints,
            routeOfficialSignalPoints: routeOfficialSignalPoints,
            activeClusters: activeClusters,
            selectedClusterIndex: selectedClusterIndex,
            mapVehicles: mapVehicles,
            vehicleBearings: vehicleTracker.vehicleBearings,
            mapStops: mapStops,
            selectedMapStopPreview: selectedMapStopPreview,
            selectedMapStopSummary: selectedMapStopSummary,
            mapVilloStations: mapVilloStations,
            mapEventImpacts: mapEventImpacts,
            onOpenPreview: openPreview(for:),
            onOpenStopPreview: openStopPreview(for:),
            onSelectCluster: { cluster in
                withAnimation(transitionSpring) {
                    selectedClusterIndex = cluster.clusterIndex
                }
            },
            onSelectVilloStation: { station in
                selectedVilloStation = station
            },
            onSelectEventImpact: { event in
                selectedEventImpact = event
            },
            onCameraChanged: { region in
                cameraLatitudeDelta = region.span.latitudeDelta
                cameraCenterCoordinate = region.center
                handleMapCameraInteraction()
            }
        )
    }

    private func handleMapCameraInteraction() {
            if suppressNextCameraInteraction {
                suppressNextCameraInteraction = false
            } else {
                isFollowingUser = false
            }
            scheduleCatalogMapStopsRefresh()
            scheduleActiveClustersRefresh()
    }

    @MainActor
    private func scheduleActiveClustersRefresh() {
        let center = cameraCenterCoordinate
        if let last = lastClustersFetchCoordinate {
            let prev = CLLocation(latitude: last.latitude, longitude: last.longitude)
            let curr = CLLocation(latitude: center.latitude, longitude: center.longitude)
            if prev.distance(from: curr) < 250 { return }
        }
        lastClustersFetchCoordinate = center

        clustersTask?.cancel()
        clustersTask = Task { [center] in
            await loadActiveClusters(around: center)
        }
    }

    @MainActor
    private func loadActiveClusters(around center: CLLocationCoordinate2D) async {
        guard AppConfig.isBackendEnabled else { return }
        let radius = max(1500.0, min(8000.0, cameraLatitudeDelta * 111_000.0 * 0.6))
        let bbox = BoundingBox(center: center, radiusMeters: radius)
        do {
            let response = try await ClusterService.active(bbox: bbox, limit: 200)
            guard !Task.isCancelled else { return }
            activeClusters = response.clusters
            OfflineCache.saveClusters(response.clusters)
            await considerAutoShowDecision()
        } catch {
            if (error as? CancellationError) == nil {
                print("[HomeView] loadActiveClusters error: \(error.localizedDescription)")
                // Fallback to cached clusters so the map is not blank offline.
                if activeClusters.isEmpty {
                    let cached = OfflineCache.loadClusters()
                    if !cached.clusters.isEmpty {
                        activeClusters = cached.clusters
                    }
                }
            }
        }
    }

    @MainActor
    private func considerAutoShowDecision() async {
        guard !hasAutoShownDecision,
              !showDecisionSheet,
              nav.currentPage == .home,
              !nav.showReportSheet else { return }

        guard let user = session.currentUser else { return }
        let favoriteLines = Set((user.favoriteLines ?? []).map { $0.uppercased() })
        let hasRoutine = user.routine?.enabled == true
        guard !favoriteLines.isEmpty || hasRoutine else { return }

        let affectsUser = activeClusters.contains { cluster in
            let line = cluster.ligne.uppercased()
            if favoriteLines.contains(line) { return true }
            if let homeStopId = user.routine?.homeStopId, cluster.arretId == homeStopId { return true }
            if let workStopId = user.routine?.workStopId, cluster.arretId == workStopId { return true }
            return false
        }

        guard affectsUser else { return }

        hasAutoShownDecision = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            showDecisionSheet = true
        }
    }

    // MARK: - Map gradient

    private var mapGradient: some View {
        LinearGradient(
            colors: [Color.clear, DS.Color.background.opacity(0.08), DS.Color.background.opacity(0.24), DS.Color.background.opacity(0.68)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Controls (search + floating buttons)

    @ViewBuilder private var controlsLayer: some View {
        if !isStopDetailPresented {
            VStack {
                Spacer()

                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        LocationFloatingButton {
                            recenterOnUser()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 190)
                .zIndex(2)
            }
        }
    }

    // MARK: - ZStack overlays (legend, sheets, AR, page)

    @ViewBuilder private var zstackOverlays: some View {
        if showLegend {
            MapLegendOverlay {
                withAnimation(transitionSpring) {
                    showLegend = false
                }
            }
            .transition(.opacity)
            .zIndex(9)
        }

        HomeStopSurfaceOverlay(
            previewStop: selectedMapStopPreview,
            detailStop: selectedMapStopSummary,
            stopDetail: selectedMapStopDetail,
            isLoading: isLoadingMapStopDetail,
            detailError: mapStopDetailError,
            userCoordinate: locationManager.userCoordinate,
            shouldShowStopPreview: shouldShowStopPreview,
            shouldShowStopDetail: shouldShowStopDetail,
            nearbyStops: { stop in
                nearbyStops(for: stop, detail: selectedMapStopDetail)
            },
            nearbyVilloStations: { stop in
                stopVilloStations(for: stop, detail: selectedMapStopDetail)
            },
            onDismiss: {
                enterInteractionMode(.map)
            },
            onOpenDetail: { stop in
                selectedMapStopSummary = stop
                enterInteractionMode(.stopDetail)
            },
            onOpenLine: openLineFromStop(_:),
            selectedLineRoute: selectedStopLineNumber,
            onSelectLineRoute: selectStopLineRoute(_:),
            onOpenStop: openStopDetail(for:),
            onSelectSiblingStop: openStopPreview(for:),
            onReport: openReportSheet(for:),
            onRetry: {
                if let stop = selectedMapStopPreview ?? selectedMapStopSummary {
                    loadStopDetail(for: stop)
                }
            }
        )

        HomeRouteSurfaceOverlay(
            options: routeOptions,
            modeSummaries: routeModeSummaries,
            selectedRouteID: $selectedRouteID,
            isRouteSheetExpanded: $isRouteSheetExpanded,
            selectedRouteDetail: selectedRouteDetail,
            selectedARRoute: selectedARRoute,
            shouldShowRouteSheet: shouldShowRouteSheet,
            shouldShowRouteDetail: shouldShowRouteDetail,
            shouldShowAR: shouldShowAR,
            onSelect: applyRouteOption(_:),
            onCloseRouteSheet: closeRouteSurface,
            onBackFromRouteDetail: showRoutePreviewFromDetail,
            onCloseRouteDetail: closeRouteSurface,
            onShowRouteMap: showRoutePreviewFromDetail,
            onStartAR: startARRoute(_:),
            onCloseAR: closeARRoute
        )

        if nav.currentPage != .home {
            pageOverlay
                .transition(.opacity.animation(.easeInOut(duration: 0.12)))
                .zIndex(6)
        }
    }

    @MainActor
    private func enterInteractionMode(_ mode: InteractionMode) {
        interactionMode = mode

        switch mode {
        case .map:
            clearStopSelection()
            clearRouteSelection(keepDestination: false)
        case .stopPreview:
            selectedMapStopSummary = nil
            selectedRouteDetail = nil
            selectedARRoute = nil
        case .stopDetail:
            selectedMapStopPreview = nil
            selectedRouteDetail = nil
            selectedARRoute = nil
        case .routePreview:
            clearStopSelection()
            selectedRouteDetail = nil
            selectedARRoute = nil
        case .routeDetail:
            clearStopSelection()
            selectedARRoute = nil
        case .ar:
            clearStopSelection()
        }
    }

    @MainActor
    private func clearStopSelection() {
        selectedMapStopPreview = nil
        selectedMapStopSummary = nil
        selectedMapStopDetail = nil
        selectedStopLineNumber = nil
        isLoadingMapStopDetail = false
    }

    @MainActor
    func openReportsFromHome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            nav.currentPage = .reports
        }
    }

    @MainActor
    func openQuickReportFromHome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            nav.showReportSheet = true
        }
    }

    @MainActor
    func selectTab(_ tab: AppTab) {
        // Tab switching should feel instant, like a native UITabBar — no
        // slide-from-the-side or spring. The pageOverlay still cross-fades
        // briefly via its own transition for polish.
        nav.currentPage = tab.page
    }

    @MainActor
    private func openLineFromStop(_ line: String) {
        clearStopSelection()
        nav.pendingLineFocus = line
        nav.currentPage = .signalements
    }

    @MainActor
    private func selectStopLineRoute(_ line: String) {
        let normalized = normalizedLineNumber(line)
        guard !normalized.isEmpty else { return }
        selectedStopLineNumber = normalized
        focusMap(onLineShapesFor: normalized)
    }

    @MainActor
    private func clearRouteSelection(keepDestination: Bool) {
        routeOptions = []
        routeModeSummaries = []
        selectedRouteID = nil
        currentRoute = nil
        currentRouteCoordinates = []
        if !keepDestination {
            destinationCoord = nil
        }
        currentTransportRecommendation = nil
        isRouteSheetExpanded = false
        selectedRouteDetail = nil
        selectedARRoute = nil
    }

    @MainActor
    private func closeRouteSurface() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            enterInteractionMode(.map)
        }
    }

    @MainActor
    private func showRoutePreviewFromDetail() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedRouteDetail = nil
            enterInteractionMode(.routePreview)
        }
    }

    @MainActor
    private func startARRoute(_ route: HomeRouteOption) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedARRoute = route
            enterInteractionMode(.ar)
        }
    }

    @MainActor
    private func closeARRoute() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedARRoute = nil
            enterInteractionMode(routeOptions.isEmpty ? .map : .routePreview)
        }
    }

    private var homeDashboardData: HomeDashboardData {
        HomeDecisionAdapter.makeDashboardData(
            transportOverview: transportOverview,
            remoteSignalements: remoteSignalements
        )
    }

    private func syncFavoritesToWidget(_ lines: Set<String>) {
        if let shared = UserDefaults(suiteName: AppConfig.appGroupID) {
            shared.set(lines.sorted(), forKey: "favoriteLines")
        }
    }

    private func syncNearbyLinesToWidget(_ stops: [NearbyStop]) {
        var seen = Set<String>()
        let lines = stops
            .flatMap { $0.lines.map { $0.number } }
            .filter { seen.insert($0).inserted }
        guard let shared = UserDefaults(suiteName: AppConfig.appGroupID) else { return }
        shared.set(Array(lines.prefix(8)), forKey: "widget_nearby_lines")
        WidgetCenter.shared.reloadAllTimelines()
    }

    private var eventAgendaStrip: some View {
        HStack(spacing: 10) {
            Image(systemName: "calendar.badge.exclamationmark")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#FFB15D"))

            Text("\(highlightedEventCount) événement\(highlightedEventCount == 1 ? "" : "s") à surveiller")
                .font(AppTheme.Fonts.captionStrong)
                .foregroundStyle(AppTheme.Palette.textPrimary)

            Spacer()

            Button {
                focusMapOnEvents()
            } label: {
                Text("Sur la carte")
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textSecondary)
            }
            .buttonStyle(.plain)

            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    nav.pendingReportsScopeRawValue = "events"
                    nav.currentPage = .reports
                }
            } label: {
                Text("Voir l'agenda")
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.info)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(AppTheme.Palette.surfaceElevated.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Palette.borderStrong, lineWidth: 1)
        )
    }

    @MainActor
    private func loadEventImpacts() async {
        guard AppConfig.isBackendEnabled else { return }
        do {
            let response = try await TransportService.events(activeOnly: false, limit: 80)
            eventImpacts = response.events
        } catch {
            print("Home event impacts failed: \(error.localizedDescription)")
        }
    }

    private func isRelevantMapEvent(_ event: TransportEventImpactDTO) -> Bool {
        let now = Date()

        if let endsAt = event.endsAt, endsAt < now.addingTimeInterval(-2 * 3600) {
            return false
        }

        if let startsAt = event.startsAt, startsAt > now.addingTimeInterval(24 * 3600) {
            return false
        }

        if let phase = event.phase?.lowercased(), phase.contains("past") || phase.contains("ended") {
            return false
        }

        return true
    }

    private func focusMapOnEvents() {
        let coordinates = eventImpacts
            .filter(isRelevantMapEvent(_:))
            .compactMap { event -> CLLocationCoordinate2D? in
                guard let latitude = event.latitude, let longitude = event.longitude else { return nil }
                return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }

        guard !coordinates.isEmpty else { return }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard
            let minLat = latitudes.min(),
            let maxLat = latitudes.max(),
            let minLng = longitudes.min(),
            let maxLng = longitudes.max()
        else {
            return
        }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLng + maxLng) / 2
        )

        let latDelta = max((maxLat - minLat) * 1.45, 0.06)
        let lngDelta = max((maxLng - minLng) * 1.45, 0.06)

        isFollowingUser = false
        suppressNextCameraInteraction = true
        withAnimation(.easeInOut(duration: 0.65)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: latDelta, longitudeDelta: lngDelta)
                )
            )
        }
    }

    private func recenterOnUser() {
        let coord = locationManager.displayCoordinate
        isFollowingUser = true
        hasAutoCenteredOnUser = true
        suppressNextCameraInteraction = true
        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                )
            )
        }
    }

    private func focusMap(on step: TransportRouteStepDTO) {
        selectedAlternativeDetail = nil
        isFollowingUser = false
        suppressNextCameraInteraction = true

        if let path = step.path, path.count >= 2 {
            let coords = path.map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
            var rect = MKMapRect.null
            for coordinate in coords {
                let point = MKMapPoint(coordinate)
                let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
                rect = rect.isNull ? pointRect : rect.union(pointRect)
            }
            withAnimation(.easeInOut(duration: 0.7)) {
                mapPosition = .rect(rect.insetBy(dx: -max(rect.width * 0.22, 250), dy: -max(rect.height * 0.22, 250)))
            }
            return
        }

        let startLat = step.startLatitude ?? step.targetLatitude
        let startLng = step.startLongitude ?? step.targetLongitude
        let endLat = step.targetLatitude ?? step.startLatitude
        let endLng = step.targetLongitude ?? step.startLongitude

        guard let firstLat = startLat, let firstLng = startLng else { return }

        let first = CLLocationCoordinate2D(latitude: firstLat, longitude: firstLng)
        let second = (endLat != nil && endLng != nil)
            ? CLLocationCoordinate2D(latitude: endLat!, longitude: endLng!)
            : first

        let center = CLLocationCoordinate2D(
            latitude: (first.latitude + second.latitude) / 2,
            longitude: (first.longitude + second.longitude) / 2
        )

        let latitudeDelta = max(abs(first.latitude - second.latitude) * 1.8, 0.008)
        let longitudeDelta = max(abs(first.longitude - second.longitude) * 1.8, 0.008)

        withAnimation(.easeInOut(duration: 0.7)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: center,
                    span: MKCoordinateSpan(latitudeDelta: latitudeDelta, longitudeDelta: longitudeDelta)
                )
            )
        }
    }

    private func focusMap(onLineShapesFor line: String) {
        let shapes = lineShapesLoader.shapes(matchingNumbers: [line])
        let coordinates = shapes.flatMap(\.coordinates)
        guard coordinates.count >= 2 else { return }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        guard !rect.isNull else { return }
        isFollowingUser = false
        suppressNextCameraInteraction = true
        withAnimation(.easeInOut(duration: 0.65)) {
            mapPosition = .rect(rect.insetBy(dx: -max(rect.width * 0.18, 450), dy: -max(rect.height * 0.18, 450)))
        }
    }

    private func firstDisplayableLine(from lines: [String]) -> String? {
        var seen = Set<String>()
        for line in lines {
            let normalized = normalizedLineNumber(line)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { continue }
            return normalized
        }
        return nil
    }

    private func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    @MainActor
    private func loadRemoteSignalements() async {
        guard AppConfig.isBackendEnabled else { hasLoadedSignalements = true; return }
        guard !isLoadingSignalements else { return }
        isLoadingSignalements = true
        defer { isLoadingSignalements = false; hasLoadedSignalements = true }
        do {
            let response = try await SignalementService.liste(page: 1)
            remoteSignalements = response.signalements
            signalementsPage = response.pagination?.page ?? 1
            signalementsTotalPages = response.pagination?.totalPages ?? 1
            lastFetchedAt = Date()
            signalementLoadError = nil
        } catch {
            signalementLoadError = "Impossible de charger les signalements."
        }
    }

    var totalActiveSignalementsCount: Int {
        remoteSignalements.filter { $0.status != "resolved" }.count
    }

    var favoriteLineCount: Int {
        session.currentUser?.favoriteLines?.count ?? 0
    }

    var favoriteAffectedCount: Int {
        guard let favoriteLines = session.currentUser?.favoriteLines, !favoriteLines.isEmpty else { return 0 }
        let lines = Set(favoriteLines)
        return remoteSignalements.filter { $0.status != "resolved" && lines.contains($0.ligne) }.count
    }

    private func openPreview(for signalementId: String) {
        guard let match = remoteSignalements.first(where: { $0.id == signalementId }) else { return }
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            selectedSignalementPreview = match
        }
    }

    private func handleClusterTap(_ cluster: MapSignalCluster) {
        if cluster.count == 1, let firstId = cluster.sampleIds.first {
            openPreview(for: firstId)
            return
        }
        UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        let targetDelta = max(0.004, cameraLatitudeDelta * 0.5)
        withAnimation(.easeInOut(duration: 0.5)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: cluster.coordinate,
                    span: MKCoordinateSpan(latitudeDelta: targetDelta, longitudeDelta: targetDelta)
                )
            )
        }
    }

    func arretName(for signalement: SignalementDTO) -> String? {
        if let ref = signalement.arretId, case .populated(let arret) = ref {
            return arret.nom
        }
        return nil
    }

    private func aroundMe() {
        if locationManager.userCoordinate != nil {
            recenterOnUser()
        } else {
            locationManager.start()
        }
    }

    @MainActor
    private func loadStopDetail(for stop: TransportStopSummaryDTO) {
        selectedMapStopDetail = nil
        isLoadingMapStopDetail = true
        mapStopDetailError = nil

        Task {
            do {
                let lookupId = stop.stopId ?? stop.id
                let detail = try await TransportService.stop(id: lookupId)
                await MainActor.run {
                    let matchesPreview = selectedMapStopPreview?.id == stop.id
                    let matchesDetail = selectedMapStopSummary?.id == stop.id
                    if matchesPreview || matchesDetail {
                        selectedMapStopDetail = detail
                        selectDefaultStopLineIfNeeded(from: detail)
                    }
                }
            } catch {
                print("Transport stop detail failed: \(error.localizedDescription)")
                await MainActor.run {
                    let matchesPreview = selectedMapStopPreview?.id == stop.id
                    let matchesDetail = selectedMapStopSummary?.id == stop.id
                    if matchesPreview || matchesDetail {
                        mapStopDetailError = error.localizedDescription
                    }
                }
            }

            await MainActor.run {
                let matchesPreview = selectedMapStopPreview?.id == stop.id
                let matchesDetail = selectedMapStopSummary?.id == stop.id
                if matchesPreview || matchesDetail {
                    isLoadingMapStopDetail = false
                }
            }
        }
    }

    @MainActor
    private func openStopPreview(for stop: TransportStopSummaryDTO) {
        selectedMapStopPreview = stop
        selectedStopLineNumber = firstDisplayableLine(from: stop.lines)
        enterInteractionMode(.stopPreview)
        loadStopDetail(for: stop)
        if let selectedStopLineNumber {
            focusMap(onLineShapesFor: selectedStopLineNumber)
        }
    }

    @MainActor
    private func openStopDetail(for stop: TransportStopSummaryDTO) {
        selectedMapStopSummary = stop
        selectedStopLineNumber = firstDisplayableLine(from: stop.lines)
        enterInteractionMode(.stopDetail)
        loadStopDetail(for: stop)
        if let selectedStopLineNumber {
            focusMap(onLineShapesFor: selectedStopLineNumber)
        }
    }

    @MainActor
    private func selectDefaultStopLineIfNeeded(from detail: TransportStopDTO) {
        let lines = detail.nextDepartures.map(\.line) + detail.stop.lines
        guard let first = firstDisplayableLine(from: lines) else { return }
        if selectedStopLineNumber == nil || !lines.map(normalizedLineNumber).contains(selectedStopLineNumber ?? "") {
            selectedStopLineNumber = first
            focusMap(onLineShapesFor: first)
        }
    }

    @MainActor
    private func focusMap(on stop: TransportStopSummaryDTO) {
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return }
        isFollowingUser = false
        suppressNextCameraInteraction = true
        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
                )
            )
        }
    }

    @MainActor
    private func applyPendingMapStopFocusIfPossible() async {
        guard let stopId = nav.pendingMapStopFocusBackendId else { return }

        if let summary = (transportOverview?.stops ?? []).first(where: { $0.id == stopId }) {
            focusMap(on: summary)
            openStopDetail(for: summary)
            nav.pendingMapStopFocusBackendId = nil
            return
        }

        if let nearby = catalogMapStops.first(where: { $0.backendId == stopId }),
           let coordinate = nearby.coordinate {
            let summary = TransportStopSummaryDTO(
                id: stopId,
                stopId: nearby.stopId,
                name: nearby.name,
                latitude: coordinate.latitude,
                longitude: coordinate.longitude,
                lines: nearby.lines.map(\.number)
            )
            focusMap(on: summary)
            openStopDetail(for: summary)
            nav.pendingMapStopFocusBackendId = nil
            return
        }

        do {
            let detail = try await TransportService.stop(id: stopId)
            let summary = detail.stop
            focusMap(on: summary)
            selectedMapStopSummary = summary
            selectedMapStopDetail = detail
            isLoadingMapStopDetail = false
            enterInteractionMode(.stopDetail)
            nav.pendingMapStopFocusBackendId = nil
        } catch {
            print("Pending map stop focus failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func openReportSheet(for stop: TransportStopSummaryDTO) {
        clearStopSelection()

        nav.pendingReportStopBackendId = stop.id
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            nav.showReportSheet = true
        }
    }

    private func stopVilloStations(
        for stop: TransportStopSummaryDTO,
        detail: TransportStopDTO?
    ) -> [(station: VilloStation, distanceMeters: Int)] {
        let latitude = detail?.stop.latitude ?? stop.latitude
        let longitude = detail?.stop.longitude ?? stop.longitude
        guard let latitude, let longitude else { return [] }
        return VilloStationService.nearbyStations(
            around: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
            radiusMeters: 300,
            limit: 3
        )
    }

    private func nearbyStops(
        for stop: TransportStopSummaryDTO,
        detail: TransportStopDTO?
    ) -> [TransportStopSummaryDTO] {
        let latitude = detail?.stop.latitude ?? stop.latitude
        let longitude = detail?.stop.longitude ?? stop.longitude
        guard let latitude, let longitude else { return [] }

        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)

        return mapStops
            .filter { $0.id != stop.id }
            .filter { summary in
                guard let lat = summary.latitude, let lng = summary.longitude else { return false }
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: lat, longitude: lng))
                return distance <= 350
            }
            .sorted { lhs, rhs in
                let left = CLLocation(latitude: lhs.latitude ?? 0, longitude: lhs.longitude ?? 0)
                    .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                let right = CLLocation(latitude: rhs.latitude ?? 0, longitude: rhs.longitude ?? 0)
                    .distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude))
                return left < right
            }
            .prefix(6)
            .map { $0 }
    }

    private func routeScopedStops(for option: HomeRouteOption) -> [TransportStopSummaryDTO] {
        let corridorStops = mapStopsAlongCurrentRoute(for: option)

        guard let backendAlternative = option.backendAlternative,
              let steps = backendAlternative.steps, !steps.isEmpty else {
            return corridorStops
        }

        var summaries: [TransportStopSummaryDTO] = []
        var seen = Set<String>()

        for step in steps.sorted(by: { $0.order < $1.order }) {
            if let summary = routeStopSummary(
                name: step.stopName,
                latitude: step.startLatitude,
                longitude: step.startLongitude,
                line: step.line
            ) {
                let key = routeStopKey(for: summary)
                if seen.insert(key).inserted {
                    summaries.append(summary)
                }
            }

            if let summary = routeStopSummary(
                name: step.arrivalStopName ?? step.destination,
                latitude: step.targetLatitude,
                longitude: step.targetLongitude,
                line: step.line
            ) {
                let key = routeStopKey(for: summary)
                if seen.insert(key).inserted {
                    summaries.append(summary)
                }
            }
        }

        for summary in corridorStops {
            let key = routeStopKey(for: summary)
            if seen.insert(key).inserted {
                summaries.append(summary)
            }
        }

        return summaries
    }

    private func routeStopSummary(
        name: String?,
        latitude: Double?,
        longitude: Double?,
        line: String?
    ) -> TransportStopSummaryDTO? {
        guard let name, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let latitude, let longitude else { return nil }

        return TransportStopSummaryDTO(
            id: "\(normalizedStopKey(name))-\(latitude)-\(longitude)",
            stopId: nil,
            name: name,
            latitude: latitude,
            longitude: longitude,
            lines: line.map { [$0] } ?? []
        )
    }

    private func routeStopKey(for summary: TransportStopSummaryDTO) -> String {
        "\(normalizedStopKey(summary.name))-\(summary.latitude ?? 0)-\(summary.longitude ?? 0)"
    }

    private func mapStopsAlongCurrentRoute(for option: HomeRouteOption? = nil) -> [TransportStopSummaryDTO] {
        let routeCoordinates = option?.routeCoordinates ?? currentRouteCoordinates
        guard !routeCoordinates.isEmpty else { return [] }

        let sampledCoordinates = stride(from: 0, to: routeCoordinates.count, by: 4).map {
            routeCoordinates[$0]
        } + [routeCoordinates.last].compactMap { $0 }
        let relevantLines = Set((option?.backendAlternative?.lines ?? []).map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines)
        }.filter { !$0.isEmpty })

        return baseMapStops
            .filter { summary in
                guard let latitude = summary.latitude, let longitude = summary.longitude else { return false }
                if !relevantLines.isEmpty {
                    let stopLines = Set(summary.lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) })
                    if stopLines.isDisjoint(with: relevantLines) {
                        return false
                    }
                }
                let stopLocation = CLLocation(latitude: latitude, longitude: longitude)
                return sampledCoordinates.contains { coordinate in
                    stopLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)) <= 120
                }
            }
            .sorted { lhs, rhs in
                routeDistanceScore(for: lhs, on: routeCoordinates) < routeDistanceScore(for: rhs, on: routeCoordinates)
            }
            .prefix(12)
            .map { $0 }
    }

    private func routeDistanceScore(
        for stop: TransportStopSummaryDTO,
        on routeCoordinates: [CLLocationCoordinate2D]? = nil
    ) -> CLLocationDistance {
        let coordinates = routeCoordinates ?? currentRouteCoordinates
        guard let latitude = stop.latitude, let longitude = stop.longitude else { return .greatestFiniteMagnitude }
        let stopLocation = CLLocation(latitude: latitude, longitude: longitude)
        return coordinates.reduce(.greatestFiniteMagnitude) { best, coordinate in
            min(best, stopLocation.distance(from: CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)))
        }
    }

    private func normalizedStopKey(_ value: String) -> String {
        value
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    func reportStillBlocked(id: String) async {
        do {
            let response = try await SignalementService.toujoursBloque(signalementId: id)
            applyCommunityUpdate(id: id, community: response.community, status: response.status)
        } catch {
            signalementLoadError = "Impossible d'envoyer ton vote. Réessaie."
        }
    }

    private func scheduleCatalogMapStopsRefresh() {
        guard cameraLatitudeDelta <= 0.18 else {
            mapStopsTask?.cancel()
            catalogMapStops = []
            return
        }

        mapStopsTask?.cancel()
        mapStopsTask = Task {
            try? await Task.sleep(nanoseconds: 180_000_000)
            guard !Task.isCancelled else { return }
            await refreshCatalogMapStops(force: false)
        }
    }

    @MainActor
    private func refreshCatalogMapStops(force: Bool) async {
        guard cameraLatitudeDelta <= 0.18 else {
            catalogMapStops = []
            return
        }

        let radius: Double
        switch cameraLatitudeDelta {
        case ..<0.02:
            radius = 550
        case ..<0.05:
            radius = 900
        case ..<0.10:
            radius = 1400
        default:
            radius = 2200
        }

        if !force,
           !catalogMapStops.isEmpty,
           lastMapStopsRefreshCoordinate.flatMap({ centerDistanceMeters(from: $0, to: cameraCenterCoordinate) < max(220, radius * 0.22) }) == true {
            return
        }

        do {
            let nearby = try await NearbyStopService.fetchNearby(
                lat: cameraCenterCoordinate.latitude,
                lng: cameraCenterCoordinate.longitude,
                radius: radius
            )
            catalogMapStops = nearby
            lastMapStopsRefreshCoordinate = cameraCenterCoordinate
            syncNearbyLinesToWidget(nearby)
        } catch {
            print("Home map nearby stops failed: \(error.localizedDescription)")
        }
    }

    private func centerDistanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let start = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let end = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return start.distance(from: end)
    }

    private func coordinateDistance(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let start = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let end = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return start.distance(from: end)
    }

    private func trackedVehicle(for option: HomeRouteOption) -> TransportVehicleDTO? {
        guard let activeVehicle = option.backendAlternative?.activeVehicle else { return nil }
        let visibleVehicles = vehicleTracker.vehicles.filter { $0.latitude != nil && $0.longitude != nil }

        if let vehicleId = activeVehicle.vehicleId,
           let exact = visibleVehicles.first(where: { $0.vehicleId == vehicleId }) {
            return exact
        }

        let targetPoint = activeVehicle.latitude.flatMap { lat in
            activeVehicle.longitude.map { lng in CLLocationCoordinate2D(latitude: lat, longitude: lng) }
        }

        let candidates = visibleVehicles.filter {
            guard let line = $0.line else { return false }
            return line == activeVehicle.line
        }

        if let targetPoint {
            return candidates.min { left, right in
                let leftDistance = left.latitude.flatMap { lat in
                    left.longitude.map { lng in coordinateDistance(from: CLLocationCoordinate2D(latitude: lat, longitude: lng), to: targetPoint) }
                } ?? .greatestFiniteMagnitude
                let rightDistance = right.latitude.flatMap { lat in
                    right.longitude.map { lng in coordinateDistance(from: CLLocationCoordinate2D(latitude: lat, longitude: lng), to: targetPoint) }
                } ?? .greatestFiniteMagnitude
                return leftDistance < rightDistance
            } ?? activeVehicle
        }

        return candidates.first ?? activeVehicle
    }

    func reportResolved(id: String) async {
        do {
            let response = try await SignalementService.resoudre(signalementId: id)
            applyCommunityUpdate(id: id, community: response.community, status: response.status)
        } catch {
            signalementLoadError = "Impossible de marquer comme résolu. Réessaie."
        }
    }

    private func applyCommunityUpdate(id: String, community: SignalementCommunityDTO?, status: String?) {
        guard let index = remoteSignalements.firstIndex(where: { $0.id == id }) else { return }
        let current = remoteSignalements[index]
        remoteSignalements[index] = SignalementDTO(
            id: current.id,
            utilisateurId: current.utilisateurId,
            arretId: current.arretId,
            ligne: current.ligne,
            typeProbleme: current.typeProbleme,
            description: current.description,
            photo: current.photo,
            latitude: current.latitude,
            longitude: current.longitude,
            confiance: current.confiance,
            source: current.source,
            votesPositifs: current.votesPositifs,
            votesNegatifs: current.votesNegatifs,
            dateSignalement: current.dateSignalement,
            status: status ?? current.status,
            community: community ?? current.community
        )
    }

    @MainActor
    private func loadTransportOverview(lat: Double? = nil, lng: Double? = nil) async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingTransportOverview else { return }
        isLoadingTransportOverview = true
        defer { isLoadingTransportOverview = false }

        do {
            transportOverview = try await TransportService.overview(lat: lat, lng: lng)
        } catch {
            print("Transport overview failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshHomeSurface(reason: String, force: Bool = false) async {
        guard AppConfig.isBackendEnabled else { return }

        let now = Date()
        if !force, let lastHomeRefreshAt, now.timeIntervalSince(lastHomeRefreshAt) < 20 {
            return
        }

        homeRefreshTask?.cancel()
        let lat = locationManager.userCoordinate?.latitude
        let lng = locationManager.userCoordinate?.longitude

        homeRefreshTask = Task {
            await loadTransportOverview(lat: lat, lng: lng)
        }

        await homeRefreshTask?.value
        guard !Task.isCancelled else { return }
        lastHomeRefreshAt = Date()
    }

    @MainActor
    private func refreshHomeSurfaceForLocation(_ coord: CLLocationCoordinate2D) async {
        let movedEnough: Bool
        if let lastHomeSurfaceRefreshCoordinate {
            let previous = CLLocation(latitude: lastHomeSurfaceRefreshCoordinate.latitude, longitude: lastHomeSurfaceRefreshCoordinate.longitude)
            let current = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            movedEnough = previous.distance(from: current) >= 325
        } else {
            movedEnough = true
        }

        guard movedEnough else { return }
        lastHomeSurfaceRefreshCoordinate = coord
        await refreshHomeSurface(reason: "location", force: false)
    }

    private func relativeTimeString(from date: Date?) -> String {
        guard let date else { return "À l'instant" }
        let formatter = RelativeDateTimeFormatter()
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: .now)
    }

    @MainActor
    private func mergeIncomingSignalement(_ signalement: SignalementDTO) {
        if let index = remoteSignalements.firstIndex(where: { $0.id == signalement.id }) {
            remoteSignalements[index] = signalement
        } else {
            remoteSignalements.insert(signalement, at: 0)
        }
    }

    @MainActor
    private func searchSuggestions(for text: String) async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
        let results = try? await MKLocalSearch(request: req).start()
        var unique: [MKMapItem] = []
        var seen = Set<String>()
        for item in results?.mapItems ?? [] {
            let key = "\(item.name ?? "")|\(item.placemark.title ?? "")"
            if seen.insert(key).inserted {
                unique.append(item)
            }
        }
        searchSuggestions = Array(unique.prefix(8))
    }

    @MainActor
    private func buildRoute(to destination: MKMapItem) async {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: locationManager.displayCoordinate))
        await buildRoute(from: source, to: destination, originName: "Votre position")
    }

    @MainActor
    private func buildRoute(
        from source: MKMapItem,
        to destination: MKMapItem,
        originName: String
    ) async {
        isRouting = true
        defer { isRouting = false }
        async let recommendationTask = fetchBackendRecommendation(source: source, destination: destination)
        async let transitRoutesTask = fetchMKRoutes(source: source, destination: destination, transportType: .transit)
        async let walkingRoutesTask = fetchMKRoutes(source: source, destination: destination, transportType: .walking)

        let recommendation = await recommendationTask
        let transitRoutes = await transitRoutesTask
        let walkingRoutes = await walkingRoutesTask
        let fallbackOptions = buildFallbackRouteOptions(
            transitRoutes: transitRoutes,
            walkingRoutes: walkingRoutes,
            originName: originName,
            destinationName: destination.name ?? "Destination"
        )

        let finalOptions = buildBackendFirstRouteOptions(
            recommendation: recommendation,
            fallbackOptions: fallbackOptions,
            originName: originName,
            destinationName: destination.name ?? "Destination"
        )

        guard !finalOptions.isEmpty || recommendation != nil else { return }

        destinationCoord = destination.placemark.coordinate
        searchSuggestions = []
        searchQuery = destination.name ?? ""
        currentTransportRecommendation = recommendation

        let preferredOption = preferredRouteOption(in: finalOptions)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            routeOptions = finalOptions
            routeModeSummaries = buildModeSummaries(recommendation: recommendation, options: finalOptions)
            selectedRouteID = preferredOption?.id
            isRouteSheetExpanded = false
            enterInteractionMode(.routePreview)
        }

        if let preferredOption {
            applyRouteOption(preferredOption)
        }
    }

    private func fetchBackendRecommendation(
        source: MKMapItem,
        destination: MKMapItem
    ) async -> TransportRecommendationDTO? {
        guard AppConfig.isBackendEnabled else { return nil }

        let depart = "\(source.placemark.coordinate.latitude),\(source.placemark.coordinate.longitude)"
        let destinationQuery = "\(destination.placemark.coordinate.latitude),\(destination.placemark.coordinate.longitude)"
        return try? await TransportService.recommendRoute(
            depart: depart,
            destination: destinationQuery
        )
    }

    private func buildModeSummaries(
        recommendation: TransportRecommendationDTO?,
        options: [HomeRouteOption]
    ) -> [RouteModeSummary] {
        let allAlternatives = recommendation?.recommendedAlternatives ?? []
        let order = ["transit", "bike", "walk"]
        let durationsByMode: [String: Int] = Dictionary(uniqueKeysWithValues: order.map { key in
            let backendMatch = allAlternatives
                .filter { HomeRouteOption.primaryMode(for: $0) == key }
                .min(by: { $0.totalDurationMinutes < $1.totalDurationMinutes })
            let optionMatch = options
                .filter { $0.primaryModeKey == key }
                .min(by: { $0.totalDurationMinutes < $1.totalDurationMinutes })
            return (key, backendMatch?.totalDurationMinutes ?? optionMatch?.totalDurationMinutes ?? .max)
        })
        let fastestDuration = durationsByMode.values.filter { $0 < .max }.min()

        return order.map { key in
            let backendMatch = allAlternatives
                .filter { HomeRouteOption.primaryMode(for: $0) == key }
                .min(by: { $0.totalDurationMinutes < $1.totalDurationMinutes })

            let optionMatch = options
                .filter { $0.primaryModeKey == key }
                .min(by: { $0.totalDurationMinutes < $1.totalDurationMinutes })

            let durationText: String
            if let backendMatch {
                durationText = "\(backendMatch.totalDurationMinutes) min"
            } else if let optionMatch {
                durationText = optionMatch.durationText
            } else {
                durationText = "—"
            }

            return RouteModeSummary(
                modeKey: key,
                title: key == "bike" ? "Vélo" : key == "walk" ? "À pied" : "Transport",
                durationText: durationText,
                isFastest: fastestDuration != nil && durationsByMode[key] == fastestDuration
            )
        }
    }

    private func fetchMKRoutes(
        source: MKMapItem,
        destination: MKMapItem,
        transportType: MKDirectionsTransportType
    ) async -> [MKRoute]? {
        let req = MKDirections.Request()
        req.source = source
        req.destination = destination
        req.transportType = transportType
        req.requestsAlternateRoutes = true

        let dirs = MKDirections(request: req)
        guard let response = try? await dirs.calculate(), !response.routes.isEmpty else {
            return nil
        }

        return Array(response.routes.prefix(4))
    }

    private func buildFallbackRouteOptions(
        transitRoutes: [MKRoute]?,
        walkingRoutes: [MKRoute]?,
        originName: String,
        destinationName: String
    ) -> [HomeRouteOption] {
        var fallback: [HomeRouteOption] = []

        for (index, route) in (transitRoutes ?? []).enumerated() {
            fallback.append(
                HomeRouteOption.from(
                    route: route,
                    index: index,
                    originName: originName,
                    destinationName: destinationName
                )
            )
        }

        if let walkingRoute = walkingRoutes?.first {
            fallback.append(
                HomeRouteOption.from(
                    route: walkingRoute,
                    index: fallback.count,
                    originName: originName,
                    destinationName: destinationName
                )
            )
        }

        return fallback
    }

    private func buildBackendFirstRouteOptions(
        recommendation: TransportRecommendationDTO?,
        fallbackOptions: [HomeRouteOption],
        originName: String,
        destinationName: String
    ) -> [HomeRouteOption] {
        guard let recommendation else { return fallbackOptions }

        var backendOptions = recommendation.recommendedAlternatives.enumerated().map { index, alternative in
            let matchedRoute = matchedFallbackRoute(for: alternative, in: fallbackOptions)
            return HomeRouteOption.from(
                route: matchedRoute,
                index: index,
                originName: originName,
                destinationName: destinationName,
                backendAlternative: alternative
            )
        }

        var dedupeKeys = Set(backendOptions.map(\.dedupeKey))
        if backendOptions.count < 5 {
            for option in fallbackOptions where !dedupeKeys.contains(option.dedupeKey) {
                backendOptions.append(option)
                dedupeKeys.insert(option.dedupeKey)
                if backendOptions.count >= 5 {
                    break
                }
            }
        }

        return backendOptions
    }

    private func matchedFallbackRoute(
        for alternative: TransportAlternativeDTO,
        in fallbackOptions: [HomeRouteOption]
    ) -> MKRoute? {
        fallbackOptions
            .filter { $0.primaryModeKey == HomeRouteOption.primaryMode(for: alternative) }
            .min(by: {
                abs($0.totalDurationMinutes - alternative.totalDurationMinutes) <
                abs($1.totalDurationMinutes - alternative.totalDurationMinutes)
            })?
            .route
    }

    private func preferredRouteOption(in options: [HomeRouteOption]) -> HomeRouteOption? {
        options.first(where: { $0.primaryModeKey == "transit" })
            ?? options.first(where: { $0.primaryModeKey == "bike" })
            ?? options.first
    }

    private func calculateRouteOptions(
        source: MKMapItem,
        destination: MKMapItem,
        transportType: MKDirectionsTransportType
    ) async -> [HomeRouteOption]? {
        async let backendAlternativesTask: [TransportAlternativeDTO]? = fetchBackendRouteAlternatives(
            source: source,
            destination: destination
        )

        let req = MKDirections.Request()
        req.source = source
        req.destination = destination
        req.transportType = transportType
        req.requestsAlternateRoutes = true

        let dirs = MKDirections(request: req)
        guard let response = try? await dirs.calculate(), !response.routes.isEmpty else {
            return nil
        }

        let backendAlternatives = await backendAlternativesTask
        return mergeRouteOptions(
            routes: Array(response.routes.prefix(3)),
            backendAlternatives: backendAlternatives,
            originName: "Votre position",
            destinationName: destination.name ?? "Destination"
        )
    }

    private func fetchBackendRouteAlternatives(
        source: MKMapItem,
        destination: MKMapItem
    ) async -> [TransportAlternativeDTO]? {
        guard AppConfig.isBackendEnabled else { return nil }

        let depart = "\(source.placemark.coordinate.latitude),\(source.placemark.coordinate.longitude)"
        let destinationQuery = "\(destination.placemark.coordinate.latitude),\(destination.placemark.coordinate.longitude)"

        guard let recommendation = try? await TransportService.recommendRoute(
            depart: depart,
            destination: destinationQuery
        ) else {
            return nil
        }

        let usable = recommendation.recommendedAlternatives.filter { alternative in
            guard let steps = alternative.steps else { return false }
            return !steps.isEmpty
        }

        return usable.isEmpty ? nil : usable
    }

    private func mergeRouteOptions(
        routes: [MKRoute],
        backendAlternatives: [TransportAlternativeDTO]?,
        originName: String,
        destinationName: String
    ) -> [HomeRouteOption] {
        var remainingAlternatives = backendAlternatives ?? []

        return routes.enumerated().map { index, route in
            let matchedAlternative: TransportAlternativeDTO?
            if let bestOffset = bestAlternativeOffset(for: route, in: remainingAlternatives) {
                matchedAlternative = remainingAlternatives.remove(at: bestOffset)
            } else {
                matchedAlternative = nil
            }

            return HomeRouteOption.from(
                route: route,
                index: index,
                originName: originName,
                destinationName: destinationName,
                backendAlternative: matchedAlternative
            )
        }
    }

    private func bestAlternativeOffset(
        for route: MKRoute,
        in alternatives: [TransportAlternativeDTO]
    ) -> Int? {
        guard !alternatives.isEmpty else { return nil }

        let routeMinutes = max(1, Int((route.expectedTravelTime / 60).rounded()))
        let routePrimaryMode = route.steps.contains(where: { $0.transportType == .transit })
            ? "transit"
            : route.transportType == .walking ? "walk" : "bike"

        return alternatives.enumerated().min { lhs, rhs in
            let lhsPenalty = routeMatchPenalty(routeMinutes: routeMinutes, routePrimaryMode: routePrimaryMode, alternative: lhs.element)
            let rhsPenalty = routeMatchPenalty(routeMinutes: routeMinutes, routePrimaryMode: routePrimaryMode, alternative: rhs.element)
            return lhsPenalty < rhsPenalty
        }?.offset
    }

    private func routeMatchPenalty(
        routeMinutes: Int,
        routePrimaryMode: String,
        alternative: TransportAlternativeDTO
    ) -> Int {
        let minutesPenalty = abs(alternative.totalDurationMinutes - routeMinutes)
        let alternativeMode = primaryMode(for: alternative)
        let modePenalty = alternativeMode == routePrimaryMode ? 0 : 30
        return minutesPenalty + modePenalty
    }

    private func primaryMode(for alternative: TransportAlternativeDTO) -> String {
        let modes = Set((alternative.steps ?? []).map { $0.mode.lowercased() })
        if modes.contains("tram") || modes.contains("bus") || modes.contains("metro") {
            return "transit"
        }
        if modes.contains("bike") {
            return "bike"
        }
        return "walk"
    }

    private func applyRouteOption(_ option: HomeRouteOption) {
        currentRoute = option.route
        currentRouteCoordinates = option.routeCoordinates
        selectedRouteID = option.id
        enterInteractionMode(.routePreview)

        let rect = option.mapRectWithPadding
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .rect(rect)
        }
    }

    @ViewBuilder
    private var pageOverlay: some View {
        ZStack {
            Color(hex: (nav.currentPage == .signalements || nav.currentPage == .reports || nav.currentPage == .favorites || nav.currentPage == .profile || nav.currentPage == .profileMain) ? "#1B1B1B" : "#0B111E").ignoresSafeArea()

            if nav.currentPage != .signalements && nav.currentPage != .reports && nav.currentPage != .favorites && nav.currentPage != .profile && nav.currentPage != .profileMain {
                VStack {
                    HStack {
                        Button {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                nav.currentPage = .home
                            }
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "chevron.left")
                                    .font(.system(size: 16, weight: .semibold))
                                Text("Carte")
                                    .font(.system(size: 15, weight: .medium))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(Color.white.opacity(0.12))
                            .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        Spacer()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    Spacer()
                }
                .zIndex(1)
            }

            switch nav.currentPage {
            case .signalements:
                SignalementsView()
            case .reports:
                ReportsView()
            case .favorites:
                FavoritesView()
            case .profile:
                ProfileView()
            case .profileMain:
                ProfileMainView()
            case .home:
                EmptyView()
            }
        }
    }

}

// MARK: - Waze overlay

private struct WazeMenuOverlay: View {
    @Binding var isShowing: Bool
    let onNavigate: (AppPage) -> Void
    let onReport: () -> Void

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Color.black.opacity(0.45)
                    .ignoresSafeArea()
                    .onTapGesture {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isShowing = false }
                    }

                WazeMenuPanel(
                    onClose: { withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isShowing = false } },
                    onNavigate: onNavigate,
                    onReport: onReport
                )
                .frame(width: geo.size.width * 0.72)
                .transition(.move(edge: .leading))
            }
        }
        .ignoresSafeArea()
    }
}

private struct WazeMenuPanel: View {
    @EnvironmentObject private var session: AuthSession

    let onClose: () -> Void
    let onNavigate: (AppPage) -> Void
    let onReport: () -> Void

    private let bg = AppTheme.Palette.screenElevated
    private let itemText = AppTheme.Palette.textPrimary.opacity(0.88)
    private let iconColor = AppTheme.Palette.textSecondary

    var body: some View {
        ZStack(alignment: .bottom) {
            bg.ignoresSafeArea()
            VStack(alignment: .leading, spacing: 0) {
                userHeader
                    .padding(.top, 60)
                    .padding(.bottom, 36)

                item("mappin.and.ellipse",   "Carte & trafic en direct")  { onNavigate(.home);         onClose() }
                item("exclamationmark.circle","Signaler un arrêt")         { onReport() }
                item("clock.arrow.circlepath","Lignes")                    { onNavigate(.signalements); onClose() }
                item("bubble.left.and.exclamationmark.bubble.right", "Reports") { onNavigate(.reports); onClose() }
                item("heart",                "Mes favoris")                { onNavigate(.favorites);    onClose() }
                item("gearshape",            "Paramètres")                 { onNavigate(.profile);      onClose() }
                item("questionmark.circle",  "Besoin d'aide ?")            {}

                Spacer()
                Text("Version 1.0.0")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textMuted)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.bottom, 40)
            }
        }
    }

    private var userHeader: some View {
        Button {
            onNavigate(.profile)
            onClose()
        } label: {
            HStack(spacing: 14) {
                Circle()
                    .fill(AppTheme.Palette.surfaceMuted)
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text(session.currentUser?.nom ?? "Mon profil")
                        .font(AppTheme.Fonts.bodyStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                    Text(session.currentUser?.email ?? "")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.success)
                }
            }
            .padding(.horizontal, 24)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private func item(_ icon: String, _ label: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 18) {
                Image(systemName: icon)
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(iconColor)
                    .frame(width: 26)
                Text(label)
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(itemText)
                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Top bar buttons

private struct HamburgerButton: View {
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 48
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(AppTheme.Palette.screen)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(AppTheme.Palette.textPrimary).frame(width: 20, height: 2)
                    }
                })
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Ouvrir le menu")
        .accessibilityHint("Affiche les sections principales de l’application")
    }
}

private struct HomeStopSurfaceOverlay: View {
    let previewStop: TransportStopSummaryDTO?
    let detailStop: TransportStopSummaryDTO?
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let detailError: String?
    let userCoordinate: CLLocationCoordinate2D?
    let shouldShowStopPreview: Bool
    let shouldShowStopDetail: Bool
    let nearbyStops: (TransportStopSummaryDTO) -> [TransportStopSummaryDTO]
    let nearbyVilloStations: (TransportStopSummaryDTO) -> [(station: VilloStation, distanceMeters: Int)]
    let onDismiss: () -> Void
    let onOpenDetail: (TransportStopSummaryDTO) -> Void
    let onOpenLine: (String) -> Void
    let selectedLineRoute: String?
    let onSelectLineRoute: (String) -> Void
    let onOpenStop: (TransportStopSummaryDTO) -> Void
    let onSelectSiblingStop: (TransportStopSummaryDTO) -> Void
    let onReport: (TransportStopSummaryDTO) -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            stopPreviewLayer
            stopDetailLayer
        }
    }

    @ViewBuilder
    private var stopPreviewLayer: some View {
        if shouldShowStopPreview, let stop = previewStop {
            HomeStopPreviewCard(
                stopSummary: stop,
                stopDetail: stopDetail,
                isLoading: isLoading,
                detailError: detailError,
                nearbyStops: nearbyStops(stop),
                nearbyVilloStations: nearbyVilloStations(stop),
                onDismiss: onDismiss,
                onOpenDetail: {
                    onOpenDetail(stop)
                },
                selectedLineRoute: selectedLineRoute,
                onSelectLineRoute: onSelectLineRoute,
                onSelectSiblingStop: onSelectSiblingStop,
                onRetry: onRetry
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(7)
        }
    }

    @ViewBuilder
    private var stopDetailLayer: some View {
        if shouldShowStopDetail, let stop = detailStop {
            ArretDetailPage(
                stopSummary: stop,
                stopDetail: stopDetail,
                isLoading: isLoading,
                userCoordinate: userCoordinate,
                nearbyStops: nearbyStops(stop),
                nearbyVilloStations: nearbyVilloStations(stop),
                onDismiss: onDismiss,
                onOpenLine: onOpenLine,
                selectedLineRoute: selectedLineRoute,
                onSelectLineRoute: onSelectLineRoute,
                onOpenStop: onOpenStop,
                onReport: {
                    onReport(stop)
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .zIndex(10)
        }
    }
}

private extension String {
    var normalizedStopKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HomeVilloStationSheet: View {
    @Environment(\.openURL) private var openURL
    let station: VilloStation

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(DS.Color.ink.opacity(0.22))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                heroCard

                HStack(spacing: 10) {
                    villoMetricCard(
                        title: "Vélos",
                        value: "\(station.availableBikes)",
                        accent: DS.Color.villo,
                        subtitle: station.availableBikes == 1 ? "disponible" : "disponibles"
                    )
                    villoMetricCard(
                        title: "Places",
                        value: "\(station.availableBikeStands)",
                        accent: DS.Color.accent,
                        subtitle: station.availableBikeStands == 1 ? "libre" : "libres"
                    )
                }

                stationFactsCard

                if let lastUpdate = station.lastUpdate {
                    let date = Date(timeIntervalSince1970: TimeInterval(lastUpdate) / 1000)
                    Text("Mis à jour \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.horizontal, 2)
                }
            }
            .padding(20)
        }
        .background(DS.Color.paper)
        .presentationBackground(DS.Color.paper)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("VILLO! · STATION \(station.number)")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(DS.Color.inkMute)

                    Text(station.displayName)
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(2)

                    Text(station.address)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Text(station.statusLabel)
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(station.isOperational ? statusAccent : DS.Color.paper)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(station.isOperational ? statusAccent.opacity(0.15) : statusAccent)
                        .overlay(
                            Capsule()
                                .stroke(station.isOperational ? statusAccent.opacity(0.35) : statusAccent, lineWidth: 1.4)
                        )
                        .clipShape(Capsule())

                    ZStack {
                        Circle()
                            .fill(statusAccent.opacity(0.12))
                            .frame(width: 54, height: 54)
                        Image(systemName: "bicycle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(statusAccent)
                    }
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(station.availableBikes) vélos")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(DS.Color.ink)
                Text("·")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
                Text("\(station.availableBikeStands) places")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Color.inkSoft)
            }

            Button {
                openWalkingDirections()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 15, weight: .bold))
                    Text("ITINÉRAIRE À PIED")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .font(DS.Font.mono.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(DS.Color.paper)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(DS.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DS.Color.paper2.opacity(0.78),
                            DS.Color.paper
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.4)
        )
    }

    private var stationFactsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STATION")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)

            HStack(spacing: 10) {
                factPill(icon: "dock.rectangle", label: "Capacité", value: "\(station.bikeStands)")
                factPill(icon: station.banking ? "creditcard.fill" : "xmark.circle", label: "Paiement", value: station.banking ? "CB" : "Sans CB")
                factPill(icon: "number.square", label: "Numéro", value: "\(station.number)")
            }
        }
        .padding(16)
        .background(DS.Color.paper2.opacity(0.38))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.1), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusAccent: Color {
        if !station.isOperational { return DS.Color.inkMute }
        if station.availableBikes == 0 { return DS.Color.statusMajor }
        if station.availableBikeStands == 0 { return DS.Color.accent }
        if station.availableBikes <= 3 { return DS.Color.statusMinor }
        return DS.Color.villo
    }

    private func openWalkingDirections() {
        let latitude = station.coordinate.latitude
        let longitude = station.coordinate.longitude
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=w") else { return }
        openURL(url)
    }

    private func villoMetricCard(title: String, value: String, accent: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(DS.Font.monoSmall.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(DS.Color.inkMute)

            Text(value)
                .font(.system(size: 31, weight: .black, design: .rounded))
                .foregroundStyle(DS.Color.ink)

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.inkSoft)

            Capsule()
                .fill(accent.opacity(0.88))
                .frame(width: 42, height: 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func factPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DS.Color.paper)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(DS.Color.inkMute)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeStopPreviewCard: View {
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let detailError: String?
    let nearbyStops: [TransportStopSummaryDTO]
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let onDismiss: () -> Void
    let onOpenDetail: () -> Void
    let selectedLineRoute: String?
    let onSelectLineRoute: (String) -> Void
    let onSelectSiblingStop: (TransportStopSummaryDTO) -> Void
    let onRetry: () -> Void

    private var siblingStops: [TransportStopSummaryDTO] {
        let originLat = effectiveStop.latitude
        let originLng = effectiveStop.longitude
        guard let originLat, let originLng else { return [] }
        let origin = CLLocation(latitude: originLat, longitude: originLng)
        return nearbyStops
            .filter { stop in
                guard let lat = stop.latitude, let lng = stop.longitude else { return false }
                return origin.distance(from: CLLocation(latitude: lat, longitude: lng)) <= 90
            }
            .prefix(4)
            .map { $0 }
    }

    private func distanceMeters(to stop: TransportStopSummaryDTO) -> Int? {
        guard
            let lat = stop.latitude, let lng = stop.longitude,
            let originLat = effectiveStop.latitude, let originLng = effectiveStop.longitude
        else { return nil }
        let dist = CLLocation(latitude: originLat, longitude: originLng)
            .distance(from: CLLocation(latitude: lat, longitude: lng))
        return Int(dist.rounded())
    }

    private var effectiveStop: TransportStopSummaryDTO {
        stopDetail?.stop ?? stopSummary
    }

    private var displayedLines: [String] {
        var seen = Set<String>()
        // Realtime departures are the ground truth for this specific physical stop.
        // Arret.lignesDesservies in the backend is the UNION of lines across merged
        // sub-stops with the same name, so it shows lines that don't actually pass here.
        // Only fall back to catalog lines when no departures are available yet.
        let departureLines = stopDetail?.nextDepartures.map(\.line) ?? []
        let source = departureLines.isEmpty ? effectiveStop.lines : departureLines
        return source.compactMap { line in
            let normalized = Self.normalizedLineNumber(line)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .sorted { left, right in
            if let leftInt = Int(left), let rightInt = Int(right) { return leftInt < rightInt }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private struct DepartureGroup: Identifiable {
        let id: String
        let line: String
        let destination: String?
        let primary: TransportDepartureDTO
        let secondary: TransportDepartureDTO?
    }

    private var departureGroups: [DepartureGroup] {
        // Show the next 2 departures per (line, destination) so users see both
        // directions of every line, not just the soonest few across the whole stop.
        let all = (stopDetail?.nextDepartures ?? [])
            .sorted { $0.minutes < $1.minutes }
        var buckets: [String: [TransportDepartureDTO]] = [:]
        var order: [String] = []
        for dep in all {
            let key = "\(dep.line)|\(dep.destination ?? "")"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(dep)
        }
        return order.compactMap { key in
            guard let arr = buckets[key], let first = arr.first else { return nil }
            return DepartureGroup(
                id: key,
                line: first.line,
                destination: first.destination,
                primary: first,
                secondary: arr.dropFirst().first
            )
        }
    }

    private var villoSummary: String? {
        guard !nearbyVilloStations.isEmpty else { return nil }
        let bikes = nearbyVilloStations.reduce(0) { $0 + $1.station.availableBikes }
        let label = nearbyVilloStations.count == 1 ? "1 Villo! à proximité" : "\(nearbyVilloStations.count) Villo! à proximité"
        return "\(label) · \(bikes) vélos"
    }

    private static func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ARRÊT" + (effectiveStop.stopId.map { " · \($0)" } ?? ""))
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)

                        Text(effectiveStop.name)
                            .font(DS.Font.displayH2)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(2)

                        if !displayedLines.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(displayedLines, id: \.self) { line in
                                        Button {
                                            onSelectLineRoute(line)
                                        } label: {
                                            LineBadge(line: line, size: .sm)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                                        .stroke(selectedLineRoute == line ? DS.Color.ink : Color.clear, lineWidth: 2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 12)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 44, height: 44)
                            .background(DS.Color.paper)
                            .overlay(
                                Circle()
                                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 18)

                Rectangle()
                    .fill(DS.Color.ink.opacity(0.12))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute)
                        Text("PROCHAINS PASSAGES")
                            .font(DS.Font.mono.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)
                    }

                    if isLoading {
                        Text("Chargement des prochains passages…")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    } else if detailError != nil {
                        HStack(spacing: 10) {
                            Text("Impossible de charger les passages.")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.inkMute)
                            Spacer()
                            Button(action: onRetry) {
                                Label("Réessayer", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DS.Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if departureGroups.isEmpty {
                        Text("Aucun passage prévu pour le moment.")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 10) {
                                ForEach(departureGroups) { group in
                                    HStack(spacing: 12) {
                                        LineBadge(line: group.line, size: .sm)
                                        Text("→ \(group.destination ?? "Direction en cours")")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(DS.Color.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(group.primary.minutes <= 0 ? "Imminent" : "\(group.primary.minutes) min")
                                                .font(DS.Font.displayH3)
                                                .foregroundStyle(DS.Color.ink)
                                            if let secondary = group.secondary {
                                                Text("puis \(secondary.minutes) min")
                                                    .font(DS.Font.monoSmall.weight(.bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(DS.Color.inkMute)
                                            } else if let delay = group.primary.delayMinutes, delay > 2 {
                                                Text("+\(delay) min")
                                                    .font(DS.Font.monoSmall.weight(.bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(DS.Color.statusMajor)
                                            } else if group.primary.source == "scheduled" {
                                                Text("théorique")
                                                    .font(DS.Font.monoSmall.weight(.bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(DS.Color.inkMute)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }

                    if let villoSummary {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.12))
                            .frame(height: 1)

                        Label(villoSummary, systemImage: "bicycle")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkSoft)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                if !siblingStops.isEmpty {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.12))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DS.Color.inkMute)
                            Text("AUTRES QUAIS ICI")
                                .font(DS.Font.mono.weight(.bold))
                                .tracking(2)
                                .foregroundStyle(DS.Color.inkMute)
                        }

                        VStack(spacing: 6) {
                            ForEach(siblingStops) { stop in
                                Button {
                                    onSelectSiblingStop(stop)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.triangle.swap")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DS.Color.inkMute)
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stop.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(DS.Color.ink)
                                                .lineLimit(1)
                                            if let dist = distanceMeters(to: stop) {
                                                Text("\(dist) m · ARRÊT \(stop.stopId ?? stop.id)")
                                                    .font(DS.Font.monoSmall)
                                                    .foregroundStyle(DS.Color.inkMute)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DS.Color.inkMute)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(DS.Color.ink.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                Button(action: onOpenDetail) {
                    HStack {
                        Text("VOIR L'ARRÊT EN DÉTAIL")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(DS.Font.mono.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.primary)
                }
                .buttonStyle(.plain)
            }
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: DS.Color.ink.opacity(0.16), radius: 18, y: 10)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
    }
}

private struct HomeEventImpactSheet: View {
    let event: TransportEventImpactDTO
    let onOpenLine: (String) -> Void
    let onOpenStop: (String) -> Void

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(DS.Color.ink.opacity(0.22))
                    .frame(width: 44, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 6)

                heroCard

                if !event.impactedLines.isEmpty {
                    sectionCard(title: "LIGNES TOUCHÉES") {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 70), spacing: 8)], spacing: 8) {
                            ForEach(event.impactedLines, id: \.self) { line in
                                Button {
                                    onOpenLine(line)
                                } label: {
                                    HStack(spacing: 6) {
                                        LineBadge(line: line, size: .sm)
                                        Image(systemName: "arrow.up.right")
                                            .font(.system(size: 10, weight: .bold))
                                            .foregroundStyle(DS.Color.inkMute)
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10)
                                    .frame(height: 40)
                                    .background(DS.Color.paper)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                                            .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }

                if let impactedStops = event.impactedStopDetails, !impactedStops.isEmpty {
                    sectionCard(title: "ARRÊTS / ZONES") {
                        VStack(spacing: 0) {
                            ForEach(Array(impactedStops.enumerated()), id: \.element.id) { index, stop in
                                if index > 0 {
                                    Rectangle()
                                        .fill(DS.Color.ink.opacity(0.1))
                                        .frame(height: 1)
                                }

                                if let stopId = stop.id {
                                    Button {
                                        onOpenStop(stopId)
                                    } label: {
                                        stopRow(title: stop.name, subtitle: "Ouvrir l'arrêt")
                                    }
                                    .buttonStyle(.plain)
                                } else {
                                    stopRow(title: stop.name, subtitle: "Zone impactée", interactive: false)
                                }
                            }
                        }
                    }
                } else if !event.impactedStops.isEmpty {
                    sectionCard(title: "ARRÊTS / ZONES") {
                        VStack(spacing: 0) {
                            ForEach(Array(event.impactedStops.enumerated()), id: \.offset) { index, stop in
                                if index > 0 {
                                    Rectangle()
                                        .fill(DS.Color.ink.opacity(0.1))
                                        .frame(height: 1)
                                }
                                stopRow(title: stop, subtitle: "Zone impactée", interactive: false)
                            }
                        }
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 22)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .presentationBackground(DS.Color.paper)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("ÉVÉNEMENT BRUXELLES")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.8)
                .foregroundStyle(DS.Color.inkMute)

            VStack(alignment: .leading, spacing: 6) {
                Text(event.title)
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)

                Text(event.venue ?? event.zoneLabel ?? "Bruxelles")
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)

                if let eventDateLabel {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar")
                            .font(.system(size: 12, weight: .semibold))
                        Text(eventDateLabel)
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(1.1)
                    }
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.top, 2)
                }
            }

            HStack(spacing: 8) {
                badge(event.phaseLabel ?? "À venir", tint: phaseTint)
                if let impact = event.impactLevel {
                    badge(impactLabel(impact), tint: impactTint(impact))
                }
            }

            if let notes = event.notesFr, !notes.isEmpty {
                Text(notes)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private func sectionCard<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.horizontal, 4)

            content()
                .padding(12)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
    }

    private func stopRow(title: String, subtitle: String, interactive: Bool = true) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(DS.Color.paper2)
                .frame(width: 34, height: 34)
                .overlay(
                    Image(systemName: interactive ? "location.viewfinder" : "mappin.and.ellipse")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                )

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)

                Text(subtitle)
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.inkMute)
                    .tracking(1.1)
            }

            Spacer()

            if interactive {
                Image(systemName: "arrow.right")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.vertical, 10)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(DS.Font.monoSmall.weight(.bold))
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(tint)
            .overlay(
                Capsule()
                    .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
            )
            .clipShape(Capsule())
    }

    private var phaseTint: Color {
        switch event.phase {
        case "live":
            return Color(hex: "#FFD1B4")
        case "upcoming":
            return Color(hex: "#F3D58F")
        default:
            return DS.Color.paper2
        }
    }

    private func impactLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "high":
            return "Affluence forte"
        case "moderate":
            return "Affluence probable"
        default:
            return "Affluence légère"
        }
    }

    private func impactTint(_ value: String) -> Color {
        switch value.lowercased() {
        case "high":
            return Color(hex: "#FFA17F")
        case "moderate":
            return Color(hex: "#F1C46C")
        default:
            return Color(hex: "#B8E28A")
        }
    }

    private var eventDateLabel: String? {
        guard let startsAt = event.startsAt else { return nil }
        return Self.eventDateFormatter.string(from: startsAt)
    }

    private static let eventDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.timeZone = TimeZone(identifier: "Europe/Brussels")
        formatter.dateFormat = "EEE d MMM · HH:mm"
        return formatter
    }()
}

private struct HomeStopDetailSheet: View {
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let onReport: () -> Void

    private var effectiveStop: TransportStopSummaryDTO {
        stopDetail?.stop ?? stopSummary
    }

    private static func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) { return String(trimmed.dropFirst()) }
        return trimmed
    }

    private var sheetDisplayedLines: [String] {
        var seen = Set<String>()
        let departureLines = stopDetail?.nextDepartures.map(\.line) ?? []
        let source = departureLines.isEmpty ? effectiveStop.lines : departureLines
        return source.compactMap { line in
            let normalized = Self.normalizedLineNumber(line)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .sorted { l, r in
            if let li = Int(l), let ri = Int(r) { return li < ri }
            return l.localizedStandardCompare(r) == .orderedAscending
        }
    }

    private struct DepartureGroup: Identifiable {
        let id: String
        let line: String
        let destination: String?
        let primary: TransportDepartureDTO
        let secondary: TransportDepartureDTO?
    }

    private var sheetDepartureGroups: [DepartureGroup] {
        let all = (stopDetail?.nextDepartures ?? [])
            .sorted { $0.minutes < $1.minutes }
        var buckets: [String: [TransportDepartureDTO]] = [:]
        var order: [String] = []
        for dep in all {
            let key = "\(dep.line)|\(dep.destination ?? "")"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(dep)
        }
        return order.compactMap { key in
            guard let arr = buckets[key], let first = arr.first else { return nil }
            return DepartureGroup(
                id: key,
                line: first.line,
                destination: first.destination,
                primary: first,
                secondary: arr.dropFirst().first
            )
        }
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(effectiveStop.name)
                            .font(.custom("DelaGothicOne-Regular", size: 20))
                            .foregroundStyle(.white)

                        Text(TransportViewAdapters.localizedSeverityLabel(
                            severity: stopDetail?.severity ?? "minor",
                            fallback: stopDetail?.label?.fr ?? "Arrêt surveillé"
                        ))
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(Color(hex: "#B5CFF8"))
                    }

                    Spacer()

                    Button(action: onReport) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 18, weight: .bold))
                            .foregroundStyle(.black)
                            .frame(width: 44, height: 44)
                            .background(Color(hex: "#F8E2B3"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Signaler à cet arrêt")
                }

                if isLoading {
                    HStack(spacing: 10) {
                        ProgressView()
                            .tint(.white)
                        Text("Chargement des prochains passages…")
                            .font(.custom("Montserrat-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.78))
                    }
                }

                if !sheetDisplayedLines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lignes")
                            .font(.custom("Montserrat-SemiBold", size: 12))
                            .foregroundStyle(Color.white.opacity(0.72))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(sheetDisplayedLines, id: \.self) { line in
                                    Text(line)
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 10)
                                        .frame(height: 30)
                                        .background(Color.white.opacity(0.08))
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 10) {
                    Text("Prochains passages")
                        .font(.custom("DelaGothicOne-Regular", size: 15))
                        .foregroundStyle(.white)

                    if !sheetDepartureGroups.isEmpty {
                        ForEach(sheetDepartureGroups) { group in
                            HStack(spacing: 10) {
                                Text(group.line)
                                    .font(.custom("Montserrat-SemiBold", size: 13))
                                    .foregroundStyle(.black)
                                    .frame(minWidth: 36, minHeight: 28)
                                    .background(Color(hex: "#B5CFF8"))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(group.destination ?? "Direction en cours")
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)

                                    let primaryText = "Dans \(group.primary.minutes) min"
                                    let secondaryText = group.secondary.map { " · puis \($0.minutes) min" } ?? ""
                                    if let delay = group.primary.delayMinutes, delay > 2 {
                                        Text("\(primaryText) · retard +\(delay) min\(secondaryText)")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(Color(hex: "#FF6B6B"))
                                    } else if group.primary.source == "scheduled" {
                                        Text("\(primaryText) · horaire théorique\(secondaryText)")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(.white.opacity(0.72))
                                    } else {
                                        Text("\(primaryText)\(secondaryText)")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(.white.opacity(0.72))
                                    }
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    } else if !isLoading {
                        Text("Aucun prochain passage fiable pour le moment.")
                            .font(.custom("Montserrat-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.72))
                    }
                }

                if !nearbyVilloStations.isEmpty {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("Villo! à proximité")
                            .font(.custom("DelaGothicOne-Regular", size: 15))
                            .foregroundStyle(.white)

                        ForEach(Array(nearbyVilloStations.prefix(3)), id: \.station.id) { item in
                            HStack(spacing: 10) {
                                Image(systemName: "bicycle")
                                    .font(.system(size: 16, weight: .bold))
                                    .foregroundStyle(.black)
                                    .frame(width: 34, height: 34)
                                    .background(Color(hex: "#57E3B6"))
                                    .clipShape(Circle())

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(item.station.displayName)
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text("\(item.station.availableBikes) vélos • \(item.station.availableBikeStands) places • \(item.distanceMeters)m")
                                        .font(.custom("Montserrat-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.72))
                                }

                                Spacer()

                                Text(item.station.statusLabel)
                                    .font(.custom("Montserrat-SemiBold", size: 11))
                                    .foregroundStyle(item.station.isOperational ? Color.black : .white)
                                    .padding(.horizontal, 8)
                                    .frame(height: 24)
                                    .background(item.station.isOperational ? Color(hex: "#57E3B6") : Color.white.opacity(0.12))
                                    .clipShape(Capsule())
                            }
                            .padding(12)
                            .background(Color.white.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        }
                    }
                }
            }
            .padding(20)
        }
        .presentationBackground(Color(hex: "#111827"))
    }
}

private struct HomeStopDetailOverlay: View {
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let onDismiss: () -> Void
    let onReport: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.52)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack {
                Spacer()

                VStack(spacing: 0) {
                    Capsule()
                        .fill(AppTheme.Palette.borderStrong)
                        .frame(width: 42, height: 5)
                        .padding(.top, 10)
                        .padding(.bottom, 12)

                    HomeStopDetailSheet(
                        stopSummary: stopSummary,
                        stopDetail: stopDetail,
                        isLoading: isLoading,
                        nearbyVilloStations: nearbyVilloStations,
                        onReport: onReport
                    )
                    .frame(maxHeight: 520)
                }
                .background(AppTheme.Palette.screen)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 28, style: .continuous)
                        .stroke(AppTheme.Palette.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 94)
        }
    }
}

struct HomeDecisionCard: View {
    let data: TransportHomeDecisionData
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Recommandation")
                        .font(.custom("Montserrat-SemiBold", size: 10))
                        .textCase(.uppercase)
                        .foregroundStyle(Color.white.opacity(0.48))

                    Text(data.title)
                        .font(AppTheme.Fonts.title3)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(.white)
                        .scaleEffect(0.85)
                } else {
                    Text(data.severityLabel)
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(AppTheme.Palette.surfaceMuted)
                        .clipShape(Capsule())
                }
            }

            Text(data.subtitle)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                Text(data.nextDepartureSummary)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.info)

                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [Color(hex: "#141C2A"), AppTheme.Palette.screenElevated.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(Color(hex: "#B5CFF8").opacity(0.14), lineWidth: 1)
        )
    }
}

private struct HomeAlternativeDetailsSheet: View {
    let alternative: TransportAlternativeDTO
    let onFocusStep: (TransportRouteStepDTO) -> Void
    @Environment(\.dismiss) private var dismiss

    private var linesSummary: String {
        let trimmed = alternative.lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !trimmed.isEmpty else { return "Aucune ligne précise" }
        return trimmed.joined(separator: " • ")
    }

    var body: some View {
        NavigationStack {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(alternative.label)
                            .font(.custom("DelaGothicOne-Regular", size: 22))
                            .foregroundStyle(.white)

                        Text(alternative.explanationDetails?.summary ?? alternative.explanation)
                            .font(.custom("Montserrat-Regular", size: 13))
                            .foregroundStyle(.white.opacity(0.76))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    HStack(spacing: 10) {
                        metricPill(title: "Durée", value: "\(alternative.totalDurationMinutes) min")
                        metricPill(title: "Marche", value: "\(alternative.walkingMinutes) min")
                        metricPill(title: "Transferts", value: "\(alternative.transfers)")
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lignes impliquées")
                            .font(.custom("Montserrat-SemiBold", size: 12))
                            .textCase(.uppercase)
                            .foregroundStyle(.white.opacity(0.58))

                        Text(linesSummary)
                            .font(.custom("Montserrat-SemiBold", size: 14))
                            .foregroundStyle(Color(hex: "#B5CFF8"))
                    }

                    if let reasons = alternative.reasons, !reasons.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Pourquoi cette alternative")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.58))

                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(reasons, id: \.self) { reason in
                                    bulletRow(reason)
                                }
                            }
                        }
                    }

                    if let categories = alternative.explanationDetails?.categories, !categories.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Lecture du choix")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.58))

                            ForEach(categories) { category in
                                VStack(alignment: .leading, spacing: 4) {
                                    Text(category.title)
                                        .font(.custom("Montserrat-SemiBold", size: 13))
                                        .foregroundStyle(.white)
                                    Text(category.detail)
                                        .font(.custom("Montserrat-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.72))
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }

                    if let steps = alternative.steps, !steps.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Étapes")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.58))

                            ForEach(steps) { step in
                                Button {
                                    dismiss()
                                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) {
                                        onFocusStep(step)
                                    }
                                } label: {
                                    HStack(alignment: .top, spacing: 12) {
                                        Text("\(step.order)")
                                            .font(.custom("Montserrat-SemiBold", size: 12))
                                            .foregroundStyle(.black)
                                            .frame(width: 28, height: 28)
                                            .background(Color(hex: "#B5CFF8"))
                                            .clipShape(Circle())

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(step.instruction)
                                                .font(.custom("Montserrat-SemiBold", size: 13))
                                                .foregroundStyle(.white)

                                            Text(stepMeta(step))
                                                .font(.custom("Montserrat-Regular", size: 12))
                                                .foregroundStyle(.white.opacity(0.7))
                                                .fixedSize(horizontal: false, vertical: true)

                                            Text("Voir sur la carte")
                                                .font(.custom("Montserrat-SemiBold", size: 11))
                                                .foregroundStyle(Color(hex: "#B5CFF8"))
                                                .padding(.top, 4)
                                        }

                                        Spacer()

                                        Image(systemName: "location.viewfinder")
                                            .font(.system(size: 14, weight: .semibold))
                                            .foregroundStyle(Color.white.opacity(0.42))
                                    }
                                    .padding(12)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(Color.white.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    let villoSuggestions = VilloStationService.routeSuggestions(for: alternative.steps)
                    if !villoSuggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Villo! disponible")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .textCase(.uppercase)
                                .foregroundStyle(.white.opacity(0.58))

                            ForEach(Array(villoSuggestions.enumerated()), id: \.offset) { _, suggestion in
                                HStack(spacing: 10) {
                                    Image(systemName: "bicycle")
                                        .font(.system(size: 15, weight: .bold))
                                        .foregroundStyle(.black)
                                        .frame(width: 32, height: 32)
                                        .background(Color(hex: "#57E3B6"))
                                        .clipShape(Circle())

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("\(suggestion.contextLabel) • \(suggestion.station.displayName)")
                                            .font(.custom("Montserrat-SemiBold", size: 12))
                                            .foregroundStyle(.white)
                                        Text("\(suggestion.station.availableBikes) vélos • \(suggestion.station.availableBikeStands) places • \(suggestion.distanceMeters)m")
                                            .font(.custom("Montserrat-Regular", size: 12))
                                            .foregroundStyle(.white.opacity(0.72))
                                    }

                                    Spacer()
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(Color.white.opacity(0.04))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                        }
                    }
                }
                .padding(20)
            }
            .background(Color(hex: "#12161F").ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Text("Alternative")
                        .font(.custom("Montserrat-SemiBold", size: 13))
                        .foregroundStyle(.white.opacity(0.72))
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Button("Fermer") { dismiss() }
                        .font(.custom("Montserrat-SemiBold", size: 13))
                        .foregroundStyle(Color(hex: "#B5CFF8"))
                }
            }
        }
    }

    private func metricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("Montserrat-SemiBold", size: 10))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.5))
            Text(value)
                .font(.custom("Montserrat-SemiBold", size: 13))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func bulletRow(_ text: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Circle()
                .fill(Color(hex: "#B5CFF8"))
                .frame(width: 7, height: 7)
                .padding(.top, 5)
            Text(text)
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.76))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func stepMeta(_ step: TransportRouteStepDTO) -> String {
        var parts: [String] = []
        parts.append(step.mode.capitalized)
        parts.append("\(step.durationMinutes) min")
        if let line = step.line, !line.isEmpty {
            parts.append("Ligne \(line)")
        }
        if let destination = step.destination, !destination.isEmpty {
            parts.append("vers \(destination)")
        }
        return parts.joined(separator: " • ")
    }
}

private struct MapLegendOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                legendHeader(left: "RÉSEAU", right: "AUCUN")

                VStack(spacing: 0) {
                    legendSimpleRow(letter: "M", fill: Color(hex: "#F05A22"), title: "Métro")
                    legendSimpleRow(letter: "T", fill: Color(hex: "#FFC20E"), title: "Tram", textColor: .black)
                    legendSimpleRow(letter: "B", fill: Color(hex: "#243F73"), title: "Bus")
                    legendSimpleRow(letter: "N", fill: Color(hex: "#6F3BA8"), title: "Noctis")
                }

                legendSubheader("AUTRES")

                VStack(spacing: 0) {
                    legendSimpleRow(letter: "V", fill: Color(hex: "#2E8B57"), title: "Villo!")
                    legendSimpleRow(letter: "E", fill: Color(hex: "#8E2AD1"), title: "Évènements")
                }
            }
            .frame(width: 248, alignment: .leading)
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
            )
            .shadow(color: DS.Color.ink.opacity(0.16), radius: 18, y: 10)
            .padding(.top, 122)
            .padding(.trailing, 18)
        }
    }

    private func legendHeader(left: String, right: String) -> some View {
        HStack {
            Text(left)
            Spacer()
            Text(right)
        }
        .font(DS.Font.mono.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.paper)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(DS.Color.ink)
    }

    private func legendSubheader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
        .font(DS.Font.mono.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.inkMute)
        .padding(.horizontal, 12)
        .frame(height: 38)
        .background(DS.Color.paper2.opacity(0.65))
    }

    private func legendSimpleRow(letter: String, fill: Color, title: String, textColor: Color = .white) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 40, height: 40)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                    )
                Text(letter)
                    .font(.system(size: 16, weight: .heavy, design: .rounded))
                    .foregroundStyle(textColor)
            }

            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.Color.ink)

            Spacer()

            Image(systemName: "checkmark")
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(DS.Color.ink)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.ink.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 66)
        }
    }
}

private struct RecentReportsBottomSheet: View {
    let items: [RecentReportItem]
    let canLoadMore: Bool
    let isLoadingMore: Bool
    let onLoadMore: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.95))
                    .frame(width: 103, height: 3)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 10)
                    .padding(.bottom, 20)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onDismiss)

                HStack(spacing: 8) {
                    Text("Derniers signalements")
                        .font(AppTheme.Fonts.title2)
                        .foregroundStyle(AppTheme.Palette.textPrimary)

                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(AppTheme.Palette.textSecondary)

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .frame(width: 28, height: 28)
                            .background(AppTheme.Palette.surfaceMuted)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 18)

                VStack(spacing: 12) {
                    ForEach(items) { item in
                        RecentReportCard(item: item)
                    }

                    if canLoadMore {
                        Button(action: onLoadMore) {
                            Group {
                                if isLoadingMore {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Text("Voir plus")
                                        .font(AppTheme.Fonts.bodyStrong)
                                        .foregroundStyle(AppTheme.Palette.textPrimary)
                                }
                            }
                            .frame(maxWidth: .infinity)
                            .frame(height: AppTheme.ButtonHeight.secondary)
                            .background(AppTheme.Palette.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(AppTheme.Palette.screenElevated)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        }
        .ignoresSafeArea()
        .background(
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onDismiss)
        )
    }
}

private struct RecentReportItem: Identifiable {
    let id: String
    let line: String
    let title: String
    let time: String
    let details: String
    let signalementId: String?
    let status: String?
    let source: String?
    let confidence: String?
    let community: SignalementCommunityDTO?

}

private struct RecentReportCard: View {
    let item: RecentReportItem
    @State private var community: SignalementCommunityDTO?
    @State private var status: String?
    @State private var isSubmitting = false
    @State private var showConfidenceExplanation = false
    @State private var actionError: String? = nil

    private var effectiveCommunity: SignalementCommunityDTO? { community ?? item.community }
    private var effectiveStatus: String? { status ?? item.status }

    private var statusColor: Color {
        switch effectiveStatus {
        case "resolved":
            return AppTheme.Palette.success
        case "active":
            return AppTheme.Palette.warning
        default:
            return AppTheme.Palette.info
        }
    }

    private var confidenceText: String? { item.confidence }
    private var isStale: Bool { (effectiveCommunity?.freshnessMinutes ?? 0) >= 120 }
    private var freshnessSummary: String { item.time }
    private var confirmationsSummary: String? {
        guard let community = effectiveCommunity else { return nil }
        let confirmations = community.confirmations ?? 0
        guard confirmations > 0, let freshness = community.freshnessMinutes else { return nil }
        let window = freshness < 60 ? "\(freshness) min" : "\(freshness / 60) h"
        return "Confirmé \(confirmations)× en \(window)"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.line)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .frame(width: 30, height: 28)
                    .background(AppTheme.Palette.brandStrong)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                (
                    Text(item.title + " ")
                        .font(AppTheme.Fonts.title3)
                    + Text(item.time)
                        .font(AppTheme.Fonts.captionStrong)
                )
                .foregroundStyle(AppTheme.Palette.textOnBrand)

                Spacer()

                Circle()
                    .fill(statusColor)
                    .frame(width: 10, height: 10)
            }

            Text(item.details)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                communityPill(freshnessSummary, background: AppTheme.Palette.screen)
                if let confirmationsSummary {
                    communityPill(confirmationsSummary, background: AppTheme.Palette.screen)
                }
            }

            if let community = effectiveCommunity {
                HStack(spacing: 10) {
                    communityPill("\(community.confirmations ?? 0) confirm.", background: AppTheme.Palette.screen)
                    communityPill("\(community.stillBlocked ?? 0) bloqué", background: AppTheme.Palette.warning, textColor: AppTheme.Palette.textOnBrand)
                    communityPill("\(community.resolved ?? 0) résolu", background: AppTheme.Palette.success, textColor: AppTheme.Palette.textOnBrand)

                    if let confidenceText {
                        Button {
                            showConfidenceExplanation = true
                        } label: {
                            HStack(spacing: 5) {
                                Text(confidenceText)
                                Image(systemName: "questionmark.circle")
                                    .font(.system(size: 10, weight: .semibold))
                            }
                            .font(AppTheme.Fonts.captionStrong)
                            .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.7))
                        }
                        .buttonStyle(.plain)
                    }
                }
            }

            HStack(spacing: 10) {
                communityPill(
                    item.source ?? "Communauté",
                    background: (item.source?.contains("STIB") == true) ? Color(hex: "#0055A4") : AppTheme.Palette.brandStrong,
                    textColor: AppTheme.Palette.textOnBrand
                )
                if isStale {
                    communityPill("Plus récent ?", background: AppTheme.Palette.surfaceMuted, textColor: AppTheme.Palette.textPrimary)
                }
            }

            if let signalementId = item.signalementId {
                HStack(spacing: 8) {
                    actionButton("Je confirme", fill: AppTheme.Palette.screen) {
                        await applyCommunityAction(.confirm, signalementId: signalementId)
                    }
                    actionButton("Toujours bloqué", fill: AppTheme.Palette.warning) {
                        await applyCommunityAction(.stillBlocked, signalementId: signalementId)
                    }
                    actionButton("C'est résolu", fill: AppTheme.Palette.success, textColor: AppTheme.Palette.textOnBrand) {
                        await applyCommunityAction(.resolved, signalementId: signalementId)
                    }
                }
                .opacity(isSubmitting ? 0.6 : 1)
            }
            if let actionError {
                Text(actionError)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.alert)
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(AppTheme.Palette.brand)
        .opacity(isStale ? 0.7 : 1)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .alert("Pourquoi cette confiance ?", isPresented: $showConfidenceExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(confidenceExplanation)
        }
        .task {
            community = item.community
            status = item.status
        }
    }

    private func communityPill(_ text: String, background: Color, textColor: Color? = nil) -> some View {
        Text(text)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(textColor ?? AppTheme.Palette.textPrimary)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(background)
            .clipShape(Capsule())
    }

    private var confidenceExplanation: String {
        switch item.confidence?.lowercased() {
        case let value? where value.contains("haute"):
            return "Basée sur une position GPS très proche de l'arrêt signalé."
        case let value? where value.contains("moyenne"):
            return "Basée sur une position GPS cohérente, mais moins précise autour de l'arrêt."
        case let value? where value.contains("basse"):
            return "Basée sur une position GPS absente ou trop éloignée de l'arrêt signalé."
        default:
            return "Basée sur la proximité GPS observée au moment du signalement."
        }
    }

    private func actionButton(
        _ title: String,
        fill: Color,
        textColor: Color = AppTheme.Palette.textPrimary,
        action: @escaping @Sendable () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            Text(title)
                .font(AppTheme.Fonts.captionStrong)
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
    private func applyCommunityAction(_ action: CommunityAction, signalementId: String) async {
        guard !isSubmitting else { return }
        isSubmitting = true
        defer { isSubmitting = false }

        do {
            let response: SignalementCommunityActionResponse
            switch action {
            case .confirm:
                response = try await SignalementService.confirmer(signalementId: signalementId)
            case .stillBlocked:
                response = try await SignalementService.toujoursBloque(signalementId: signalementId)
            case .resolved:
                response = try await SignalementService.resoudre(signalementId: signalementId)
            }
            community = response.community ?? community
            status = response.status ?? status
            actionError = nil
        } catch {
            actionError = "Action non envoyée. Réessaie."
        }
    }

    private enum CommunityAction {
        case confirm
        case stillBlocked
        case resolved
    }
}

private struct SearchPillButton: View {
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundColor(AppTheme.Palette.textPrimary)
                Text("Rechercher un arrêt…")
                    .font(AppTheme.Fonts.body)
                    .foregroundColor(AppTheme.Palette.textSecondary)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.ButtonHeight.secondary)
            .background(AppTheme.Palette.screen)
            .clipShape(Capsule())
            .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchInputOverlay: View {
    @Binding var isShowing: Bool
    let onRouteFound: (MKRoute, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var suggestions: [MKMapItem] = []
    @State private var isSearching = false
    @State private var isRouting = false
    @State private var searchTask: Task<Void, Never>? = nil
    @FocusState private var focused: Bool

    private let brussels = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.5)
                .ignoresSafeArea()
                .onTapGesture { dismiss() }

            VStack(spacing: 0) {
                // ── Search bar row ────────────────────────────────────
                HStack(spacing: 12) {
                    Button { dismiss() } label: {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .semibold))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .frame(width: 48, height: 48)
                            .background(AppTheme.Palette.screen)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Image(systemName: isRouting ? "arrow.triangle.turn.up.right.circle.fill" : "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                        ZStack(alignment: .leading) {
                            if query.isEmpty {
                                Text("Où voulez-vous aller ?")
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(AppTheme.Palette.textMuted)
                            }
                            TextField("", text: $query)
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                .focused($focused)
                                .submitLabel(.go)
                                .onChange(of: query) { _, newVal in
                                    searchTask?.cancel()
                                    guard !newVal.isEmpty else { suggestions = []; return }
                                    searchTask = Task {
                                        try? await Task.sleep(nanoseconds: 300_000_000)
                                        guard !Task.isCancelled else { return }
                                        await searchSuggestions(for: newVal)
                                    }
                                }
                        }
                        if !query.isEmpty {
                            Button { query = ""; suggestions = [] } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundStyle(AppTheme.Palette.textMuted)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.ButtonHeight.secondary)
                    .background(AppTheme.Palette.surface)
                    .clipShape(Capsule())
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)

                // ── Suggestions list ──────────────────────────────────
                if !suggestions.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(suggestions, id: \.self) { item in
                            Button {
                                Task { await buildRoute(to: item) }
                            } label: {
                                HStack(spacing: 14) {
                                    Image(systemName: "mappin.circle.fill")
                                        .font(.system(size: 22))
                                        .foregroundStyle(AppTheme.Palette.info)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "")
                                            .font(AppTheme.Fonts.bodyStrong)
                                            .foregroundStyle(AppTheme.Palette.textPrimary)
                                        if let addr = item.placemark.title {
                                            Text(addr)
                                                .font(AppTheme.Fonts.caption)
                                                .foregroundStyle(AppTheme.Palette.textSecondary)
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if isRouting {
                                        ProgressView()
                                            .tint(AppTheme.Palette.textPrimary)
                                            .scaleEffect(0.8)
                                    }
                                }
                                .padding(.horizontal, 20)
                                .padding(.vertical, 14)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            if item != suggestions.last {
                                Divider()
                                    .background(Color.white.opacity(0.08))
                                    .padding(.leading, 56)
                            }
                        }
                    }
                    .background(AppTheme.Palette.screenElevated)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .shadow(color: .black.opacity(0.3), radius: 12, x: 0, y: 4)
                }

                Spacer()
            }
        }
        .onAppear { focused = true }
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { isShowing = false }
    }

    @MainActor
    private func searchSuggestions(for text: String) async {
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.region = MKCoordinateRegion(
            center: brussels,
            span: MKCoordinateSpan(latitudeDelta: 0.3, longitudeDelta: 0.3)
        )
        let results = try? await MKLocalSearch(request: req).start()
        suggestions = Array((results?.mapItems ?? []).prefix(5))
    }

    @MainActor
    private func buildRoute(to destination: MKMapItem) async {
        isRouting = true
        let req = MKDirections.Request()
        req.source = MKMapItem(placemark: MKPlacemark(coordinate: brussels))
        req.destination = destination
        req.transportType = .transit
        let dirs = MKDirections(request: req)
        if let response = try? await dirs.calculate(), let route = response.routes.first {
            onRouteFound(route, destination.placemark.coordinate)
            dismiss()
        } else {
            // Fallback: transit not available, show destination pin anyway
            req.transportType = .walking
            if let response = try? await MKDirections(request: req).calculate(),
               let route = response.routes.first {
                onRouteFound(route, destination.placemark.coordinate)
                dismiss()
            }
        }
        isRouting = false
    }
}
