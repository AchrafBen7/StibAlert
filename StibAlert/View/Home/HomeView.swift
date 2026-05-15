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

    var shouldShowAllClearChip: Bool {
        guard session.isSignedIn,
              activeClusters.isEmpty,
              !nav.showReportSheet,
              !showLegend,
              selectedClusterIndex == nil,
              selectedMapStopPreview == nil,
              !isRouting
        else { return false }
        return true
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
                .homeFeatureTip(.map)
            OfflineMapFallback(isConnected: connectivity.isConnected)
                .allowsHitTesting(false)
            mapGradient
            controlsLayer
            zstackOverlays
        }
        .overlay(alignment: .bottom) { reportSheetOverlay }
        .overlay(alignment: .top) { searchHeaderOverlay }
        .overlay(alignment: .top) { allClearChipOverlay }
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
            cameraLatitudeDelta: cameraLatitudeDelta,
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
            onSelectClusterCount: { center in
                zoomCameraIn(to: center, factor: 0.4)
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
                ErrorReporting.capture(error, tag: "home.loadActiveClusters")
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
                .zLayer(.controls)
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
            .zLayer(.mapLegend)
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
                .zLayer(.pageOverlay)
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
            ErrorReporting.capture(error, tag: "home.eventImpacts")
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

    private func zoomCameraIn(to center: CLLocationCoordinate2D, factor: Double = 0.32) {
        let newDelta = max(0.004, cameraLatitudeDelta * factor)
        let span = MKCoordinateSpan(latitudeDelta: newDelta, longitudeDelta: newDelta)
        let region = MKCoordinateRegion(center: center, span: span)
        // easeOut is cheaper to animate than a spring on Map (which redraws
        // annotations at every interpolation step). Keeps the tap responsive
        // when the city is dense with clusters.
        withAnimation(.easeOut(duration: 0.28)) {
            mapPosition = .region(region)
        }
        cameraLatitudeDelta = newDelta
        cameraCenterCoordinate = center
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
                ErrorReporting.capture(error, tag: "home.stopDetail")
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
        if #available(iOS 17.0, *) {
            HomeFeatureTour.map.invalidate(reason: .actionPerformed)
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
            ErrorReporting.capture(error, tag: "home.pendingStopFocus")
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
            ErrorReporting.capture(error, tag: "home.nearbyStops")
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
            ErrorReporting.capture(error, tag: "home.transportOverview")
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
                .zLayer(.backgroundPage)
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

