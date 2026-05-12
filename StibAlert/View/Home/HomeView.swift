import SwiftUI
import MapKit
import Combine
import AVFoundation
import WidgetKit

private enum MapFilter { case none, favorites, perturbations }

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

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject private var locationManager = HomeLocationManager()
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
    @State private var showLegend = false
    @State private var showRoutePlanner = false
    @State private var selectedSignalementPreview: SignalementDTO? = nil
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
    @State private var searchQuery = ""
    @State private var searchSuggestions: [MKMapItem] = []
    @State private var isRouting = false
    @State private var searchTask: Task<Void, Never>? = nil
    @State private var remoteSignalements: [SignalementDTO] = []
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
    @State private var activeMapFilter: MapFilter = .none
    @State private var cameraLatitudeDelta: Double = 0.04
    @State private var showReportAuthGate = false
    @State private var guestGateReason: GuestAuthReason = .report
    @State private var hasBootstrappedHomeData = false
    @State private var homeRefreshTask: Task<Void, Never>? = nil
    @State private var lastHomeRefreshAt: Date? = nil
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
    @State private var selectedClusterIndex: Int? = nil
    @State private var clustersTask: Task<Void, Never>? = nil
    @State private var lastClustersFetchCoordinate: CLLocationCoordinate2D? = nil

    @State private var showDecisionSheet = false
    @State private var hasAutoShownDecision = false

    private struct LiveSignalPoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let typeProbleme: String
        let source: String?
    }

    private struct CommunityWarningPoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let typeProbleme: String
        let evidenceCount: Int
    }

    private struct RouteOfficialSignalPoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let title: String
        let severity: String?
        let stop: TransportStopSummaryDTO?
    }

    private struct RouteMapSegment: Identifiable {
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

    private var communityWarningPoints: [CommunityWarningPoint] {
        struct Bucket {
            var items: [SignalementDTO] = []
            var latitudeTotal: Double = 0
            var longitudeTotal: Double = 0
            var confirmations: Int = 0
            var stillBlocked: Int = 0
            var resolved: Int = 0
        }

        var buckets: [String: Bucket] = [:]
        for signalement in filteredSignalements {
            guard signalement.source != "stib_officiel",
                  signalement.status != "resolved",
                  let lat = signalement.latitude,
                  let lng = signalement.longitude else { continue }

            let stopKey = signalement.arretId?.id ?? "\(round(lat * 10000) / 10000),\(round(lng * 10000) / 10000)"
            let key = "\(signalement.ligne)|\(stopKey)"
            var bucket = buckets[key, default: Bucket()]
            bucket.items.append(signalement)
            bucket.latitudeTotal += lat
            bucket.longitudeTotal += lng
            bucket.confirmations += signalement.community?.confirmations ?? 0
            bucket.stillBlocked += signalement.community?.stillBlocked ?? 0
            bucket.resolved += signalement.community?.resolved ?? 0
            buckets[key] = bucket
        }

        return buckets.compactMap { _, bucket in
            guard let first = bucket.items.first else { return nil }
            let evidence = bucket.items.count + bucket.confirmations + bucket.stillBlocked
            guard evidence >= 3, bucket.resolved < 3 else { return nil }
            let count = Double(bucket.items.count)
            return CommunityWarningPoint(
                id: first.id,
                coordinate: CLLocationCoordinate2D(
                    latitude: bucket.latitudeTotal / count,
                    longitude: bucket.longitudeTotal / count
                ),
                typeProbleme: first.displayTypeProbleme,
                evidenceCount: evidence
            )
        }
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

    private var highlightedEventCount: Int {
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

    private var shouldShowSearchHeader: Bool {
        switch homeSurfaceMode {
        case .mapIdle, .routePreview, .signalementPreview:
            return true
        case .unavailable, .stopPreview, .stopDetail, .routeDetail, .ar:
            return false
        }
    }

    private var shouldShowSignalementPreview: Bool {
        homeSurfaceMode == .signalementPreview
    }

    private var shouldShowPulseBar: Bool {
        homeSurfaceMode == .mapIdle
    }

    private var shouldShowTabBar: Bool {
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

    private var transitionSpring: Animation {
        AppMotion.spring(reduceMotion: reduceMotion)
    }

    // MARK: - Body

    var body: some View {
        ZStack {
            mapLayer
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
                onPlanRoute: { source, destination, originName in
                    Task {
                        await buildRoute(
                            from: source,
                            to: destination,
                            originName: originName
                        )
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
        Map(position: $mapPosition) {
            ForEach(visibleLineShapes) { shape in
                MapPolyline(coordinates: shape.coordinates)
                    .stroke(
                        shape.color.opacity(0.85),
                        style: StrokeStyle(lineWidth: 3.5, lineCap: .round, lineJoin: .round)
                    )
            }
            ForEach(selectedStopLineShapes) { shape in
                MapPolyline(coordinates: shape.coordinates)
                    .stroke(
                        shape.color,
                        style: StrokeStyle(lineWidth: 6.5, lineCap: .round, lineJoin: .round)
                    )
            }
            MapCircle(center: locationManager.displayCoordinate, radius: 200)
                .foregroundStyle(AppTheme.Palette.screen.opacity(0.07))
                .stroke(AppTheme.Palette.info.opacity(0.6), lineWidth: 1)
            Annotation("", coordinate: locationManager.displayCoordinate, anchor: .center) {
                UserLocationDotView(heading: locationManager.heading)
            }
            ForEach(routeMapSegments) { segment in
                MapPolyline(coordinates: segment.coordinates)
                    .stroke(
                        segment.color,
                        style: StrokeStyle(lineWidth: segment.lineWidth, lineCap: .round, lineJoin: .round)
                    )
            }
            if let dest = destinationCoord {
                Annotation("", coordinate: dest, anchor: .bottom) {
                    Image(systemName: "mappin.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(AppTheme.Palette.info)
                        .shadow(radius: 4)
                }
            }
            ForEach(officialSignalPoints) { point in
                Annotation("", coordinate: point.coordinate, anchor: .bottom) {
                    Button { openPreview(for: point.id) } label: {
                        OfficialSignalMarker(problemType: point.typeProbleme)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(routeOfficialSignalPoints) { point in
                Annotation("", coordinate: point.coordinate, anchor: .bottom) {
                    Button {
                        if let stop = point.stop {
                            openStopPreview(for: stop)
                        }
                    } label: {
                        OfficialSignalMarker(problemType: point.title)
                    }
                    .buttonStyle(.plain)
                }
            }
            // Note: legacy `communityWarningPoints` removed — `activeClusters` is now the single source of truth.
            ForEach(activeClusters) { cluster in
                if let lat = cluster.latitude, let lng = cluster.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .bottom) {
                        Button {
                            withAnimation(transitionSpring) {
                                selectedClusterIndex = cluster.clusterIndex
                            }
                        } label: {
                            ClusterMarker(cluster: cluster, isSelected: selectedClusterIndex == cluster.clusterIndex)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ForEach(mapVehicles) { vehicle in
                if let lat = vehicle.latitude, let lng = vehicle.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .center) {
                        VehicleMarker(
                            vehicle: vehicle,
                            bearing: vehicle.vehicleId.flatMap { vehicleTracker.vehicleBearings[$0] }
                        )
                    }
                }
            }
            ForEach(mapStops) { stop in
                if let latitude = stop.latitude, let longitude = stop.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                        Button {
                            openStopPreview(for: stop)
                        } label: {
                            HomeStopMarker(
                                stop: stop,
                                isSelected: selectedMapStopPreview?.id == stop.id || selectedMapStopSummary?.id == stop.id
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
            ForEach(mapVilloStations) { station in
                Annotation("", coordinate: station.coordinate, anchor: .bottom) {
                    Button {
                        selectedVilloStation = station
                    } label: {
                        VilloMapMarker(station: station)
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(mapEventImpacts) { event in
                if let latitude = event.latitude, let longitude = event.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                        Button {
                            selectedEventImpact = event
                        } label: {
                            EventMapMarker(event: event)
                        }
                        .buttonStyle(.plain)
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .environment(\.colorScheme, .light)
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { ctx in
            cameraLatitudeDelta = ctx.region.span.latitudeDelta
            cameraCenterCoordinate = ctx.region.center
            if suppressNextCameraInteraction {
                suppressNextCameraInteraction = false
            } else {
                isFollowingUser = false
            }
            scheduleCatalogMapStopsRefresh()
            scheduleActiveClustersRefresh()
        }
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
            await considerAutoShowDecision()
        } catch {
            if (error as? CancellationError) == nil {
                print("[HomeView] loadActiveClusters error: \(error.localizedDescription)")
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
    private func openReportsFromHome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            nav.currentPage = .reports
        }
    }

    @MainActor
    private func openQuickReportFromHome() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            nav.showReportSheet = true
        }
    }

    @MainActor
    private func selectTab(_ tab: AppTab) {
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

    private var totalActiveSignalementsCount: Int {
        remoteSignalements.filter { $0.status != "resolved" }.count
    }

    private var favoriteLineCount: Int {
        session.currentUser?.favoriteLines?.count ?? 0
    }

    private var favoriteAffectedCount: Int {
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

    private func arretName(for signalement: SignalementDTO) -> String? {
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

    private func reportStillBlocked(id: String) async {
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

    private func reportResolved(id: String) async {
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

// MARK: - User location dot

private struct UserLocationDotView: View {
    let heading: Double

    var body: some View {
        ZStack {
            DirectionConeShape()
                .fill(LinearGradient(
                    colors: [AppTheme.Palette.info.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 28, height: 36)
                .offset(y: -16)
                .rotationEffect(.degrees(heading))

            Circle()
                .fill(AppTheme.Palette.screen)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(AppTheme.Palette.info, lineWidth: 1))
                .shadow(color: Color(red: 0.499, green: 0.527, blue: 0.962), radius: 4, x: 0, y: 4)
        }
    }
}

private struct DirectionConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
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

private struct HomeRouteSurfaceOverlay: View {
    let options: [HomeRouteOption]
    let modeSummaries: [RouteModeSummary]
    @Binding var selectedRouteID: UUID?
    @Binding var isRouteSheetExpanded: Bool
    let selectedRouteDetail: HomeRouteOption?
    let selectedARRoute: HomeRouteOption?
    let shouldShowRouteSheet: Bool
    let shouldShowRouteDetail: Bool
    let shouldShowAR: Bool
    let onSelect: (HomeRouteOption) -> Void
    let onCloseRouteSheet: () -> Void
    let onBackFromRouteDetail: () -> Void
    let onCloseRouteDetail: () -> Void
    let onShowRouteMap: () -> Void
    let onStartAR: (HomeRouteOption) -> Void
    let onCloseAR: () -> Void

    var body: some View {
        Group {
            if shouldShowRouteSheet {
                RouteRecommendationsSheet(
                    options: options,
                    modeSummaries: modeSummaries,
                    selectedRouteID: $selectedRouteID,
                    isExpanded: $isRouteSheetExpanded,
                    onSelect: onSelect,
                    onClose: onCloseRouteSheet
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(8)
            }

            if shouldShowRouteDetail, let selectedRouteDetail {
                RouteItineraryDetailsView(
                    option: selectedRouteDetail,
                    onBack: onBackFromRouteDetail,
                    onClose: onCloseRouteDetail,
                    onShowMap: onShowRouteMap,
                    onStartAR: {
                        onStartAR(selectedRouteDetail)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(9)
            }

            if shouldShowAR, let selectedARRoute {
                RouteARNavigationView(
                    option: selectedARRoute,
                    onClose: onCloseAR
                )
                .transition(.opacity)
                .zIndex(11)
            }
        }
    }
}

private struct HomeSearchHeaderOverlay: View {
    @EnvironmentObject private var connectivity: NetworkConnectivityMonitor
    @Binding var searchQuery: String
    let suggestions: [MKMapItem]
    let isRouting: Bool
    let hasUserCoordinate: Bool
    let favoriteLineCount: Int
    let totalActiveSignalementsCount: Int
    let isFavoritesFilterActive: Bool
    let isPerturbationsFilterActive: Bool
    let onShowLegend: () -> Void
    let onOpenItineraryPlanner: () -> Void
    let onOpenFavorites: () -> Void
    let onOpenReports: () -> Void
    let onSelectSuggestion: (MKMapItem) -> Void

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            if !connectivity.isConnected || connectivity.isConstrained {
                OfflineIndicator(
                    isConnected: connectivity.isConnected,
                    isConstrained: connectivity.isConstrained
                )
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                HomeEditorialSearchField(query: $searchQuery, action: onOpenItineraryPlanner)

                Button(action: onShowLegend) {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.paper.opacity(0.96))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "square.3.layers.3d")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DS.Color.ink)
                        )
                        .shadow(DS.Shadow.floating)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            if isSearching {
                if !suggestions.isEmpty {
                    SearchSuggestionsDropdown(
                        suggestions: suggestions,
                        isRouting: isRouting,
                        onSelect: onSelectSuggestion
                    )
                    .padding(.horizontal, 18)
                }
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Explorer la carte")
                        .font(DS.Font.monoSmall)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.leading, 22)

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            HomeEditorialActionChip(
                                icon: "arrow.triangle.turn.up.right.diamond.fill",
                                title: "Itinéraires",
                                count: nil,
                                isActive: isRouting,
                                action: onOpenItineraryPlanner
                            )

                            HomeEditorialActionChip(
                                icon: "star.fill",
                                title: "Favoris",
                                count: favoriteLineCount,
                                isActive: isFavoritesFilterActive,
                                action: onOpenFavorites
                            )

                            HomeEditorialActionChip(
                                icon: "exclamationmark.triangle.fill",
                                title: "Perturbations",
                                count: totalActiveSignalementsCount,
                                isActive: isPerturbationsFilterActive,
                                action: onOpenReports
                            )
                        }
                        .padding(.horizontal, 18)
                    }
                }
            }
        }
    }
}

private struct HomeEditorialSearchField: View {
    @Binding var query: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Color.inkSoft)

                Text(query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Où vas-tu ?" : query)
                    .font(DS.Font.body)
                    .foregroundStyle(query.isEmpty ? DS.Color.inkMute : DS.Color.ink)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .buttonStyle(.plain)
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(DS.Color.paper.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .shadow(DS.Shadow.floating)
    }
}

private struct HomeEditorialActionChip: View {
    let icon: String
    let title: String
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(DS.Font.bodyBold)
                    .tracking(1.0)
                    .textCase(.uppercase)
                if let count {
                    Text("\(count)")
                        .font(DS.Font.mono)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill((isActive ? DS.Color.ink : DS.Color.paper2).opacity(0.14))
                        )
                }
            }
            .foregroundStyle(isActive ? DS.Color.ink : DS.Color.inkSoft)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(DS.Color.paper.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .shadow(DS.Shadow.raised)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchCircleButton: View {
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.paper.opacity(0.96))
                .frame(width: buttonSize, height: buttonSize)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                )
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Rechercher un trajet")
        .accessibilityHint("Ouvre la recherche de destination")
    }
}

private struct HomeSearchBar: View {
    @Binding var query: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.ink)

            TextField("", text: $query, prompt: Text("Où vas-tu ?").foregroundStyle(DS.Color.inkMute))
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(DS.Color.paper.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
        .shadow(DS.Shadow.floating)
    }
}

private struct SearchSuggestionsDropdown: View {
    let suggestions: [MKMapItem]
    let isRouting: Bool
    let onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Text("DESTINATIONS")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.12))
                    .frame(height: 1)
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, 8)

            ForEach(suggestions, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.Color.paper2)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: symbol(for: item))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Color.primary)
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name ?? "Lieu")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(DS.Color.ink)
                            Text(primaryLocationLine(for: item))
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.inkMute)
                                .lineLimit(1)
                            Text(categoryLabel(for: item))
                                .font(DS.Font.monoSmall.weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(DS.Color.community)
                        }

                        Spacer()

                        if isRouting {
                            ProgressView()
                                .tint(DS.Color.ink)
                                .scaleEffect(0.85)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)

                if item != suggestions.last {
                    Divider()
                        .overlay(DS.Color.ink.opacity(0.08))
                        .padding(.leading, 60)
                }
            }
        }
        .background(DS.Color.paper.opacity(0.98))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(DS.Shadow.floating)
    }

    private func symbol(for item: MKMapItem) -> String {
        if item.pointOfInterestCategory != nil {
            return "sparkles"
        }
        return "mappin"
    }

    private func primaryLocationLine(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let pieces: [String] = [
            placemark.thoroughfare,
            placemark.locality,
            placemark.country
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return pieces.isEmpty ? (placemark.title ?? "") : pieces.joined(separator: ", ")
    }

    private func categoryLabel(for item: MKMapItem) -> String {
        if item.pointOfInterestCategory != nil {
            return "LIEU"
        }
        return "ADRESSE"
    }
}

private struct LiveSignalMarker: View {
    let problemType: String

    private var color: Color {
        switch problemType {
        case "Accident", "Agression": return AppTheme.Palette.alert
        case "Retard", "Panne": return AppTheme.Palette.warning
        case "Incivilité": return AppTheme.Palette.info
        case "Propreté": return AppTheme.Palette.success
        default: return AppTheme.Palette.brand
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 18, height: 18)
        }
        .accessibilityElement()
        .accessibilityLabel("Signalement \(problemType)")
        .accessibilityHint("Ouvre le détail du signalement")
    }
}

private struct OfficialSignalMarker: View {
    let problemType: String
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(hex: "#F0441F").opacity(pulse ? 0.16 : 0.34))
                        .frame(width: pulse ? 48 : 38, height: pulse ? 46 : 36)
                        .scaleEffect(pulse ? 1.12 : 0.92)

                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(Color(hex: "#F0441F"))
                        .frame(width: 34, height: 32)
                        .shadow(color: Color(hex: "#F0441F").opacity(0.35), radius: 8, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 2)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                }

                Text("STIB")
                    .font(.system(size: 6, weight: .black, design: .rounded))
                    .kerning(0.35)
                    .foregroundStyle(Color(hex: "#0055A4"))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: 7, y: -6)
            }

            TrianglePointer()
                .fill(Color(hex: "#F0441F"))
                .frame(width: 12, height: 7)
                .offset(y: -1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Alerte officielle STIB — \(problemType)")
        .accessibilityHint("Ouvre le détail de la perturbation officielle")
    }
}

private struct CommunityWarningMarker: View {
    let problemType: String
    let count: Int
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(Color(hex: "#F0441F").opacity(pulse ? 0.14 : 0.30))
                        .frame(width: pulse ? 50 : 40, height: pulse ? 48 : 38)
                        .scaleEffect(pulse ? 1.12 : 0.94)

                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .fill(Color(hex: "#F0441F"))
                        .frame(width: 36, height: 34)
                        .shadow(color: Color(hex: "#F0441F").opacity(0.38), radius: 9, x: 0, y: 4)
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 2)

                    Image(systemName: "person.2.wave.2.fill")
                        .font(.system(size: 14, weight: .black))
                        .foregroundStyle(.white)
                }

                Text("+\(count)")
                    .font(.system(size: 8, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 3)
                    .background(Color.black)
                    .clipShape(Capsule())
                    .offset(x: 9, y: -7)
            }

            TrianglePointer()
                .fill(Color(hex: "#F0441F"))
                .frame(width: 12, height: 7)
                .offset(y: -1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Alerte communauté — \(problemType)")
        .accessibilityHint("Ouvre le détail du signalement")
    }
}

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

private extension String {
    var normalizedStopKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

private struct HomeStopMarker: View {
    let stop: TransportStopSummaryDTO
    let isSelected: Bool

    private var primaryLine: String? {
        stop.lines.first
    }

    private var fill: Color {
        if isSelected { return DS.Color.ink }
        guard let primaryLine else { return DS.Color.paper }
        return TransitLinePalette.fill(for: primaryLine)
    }

    private var foreground: Color {
        if isSelected { return DS.Color.paper }
        guard let primaryLine else { return DS.Color.ink }
        return TransitLinePalette.foreground(for: primaryLine)
    }

    private var extraCount: Int {
        max(stop.lines.count - 1, 0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: isSelected ? 34 : 32, height: isSelected ? 34 : 32)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.paper, lineWidth: 3)
                    )
                    .overlay(
                        Circle()
                            .stroke(DS.Color.ink.opacity(isSelected ? 0.9 : 0.22), lineWidth: isSelected ? 1.5 : 1)
                    )

                Text(primaryLine ?? "•")
                    .font(.system(size: primaryLine?.count ?? 1 > 2 ? 12 : 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 3)

            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .offset(x: 8, y: -6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Arrêt \(stop.name)")
        .accessibilityHint("Ouvre les détails et prochains passages")
    }
}

private struct VilloMapMarker: View {
    let station: VilloStation

    private var fill: Color {
        switch visualState {
        case .closed:
            return Color.white.opacity(0.32)
        case .empty:
            return Color(hex: "#FF7A7A")
        case .low:
            return Color(hex: "#FFB15A")
        case .full:
            return Color(hex: "#7DB6FF")
        case .healthy:
            return Color(hex: "#57E3B6")
        }
    }

    private var stroke: Color {
        switch visualState {
        case .closed:
            return Color.white.opacity(0.55)
        case .empty:
            return Color(hex: "#FFD1D1")
        case .low:
            return Color(hex: "#FFE1BA")
        case .full:
            return Color(hex: "#D5E7FF")
        case .healthy:
            return Color(hex: "#CCF8EA")
        }
    }

    private var bikeBadgeText: String {
        "\(station.availableBikes)"
    }

    private var docksBadgeText: String {
        "+\(station.availableBikeStands)"
    }

    private var visualState: VilloVisualState {
        if !station.isOperational { return .closed }
        if station.availableBikes == 0 { return .empty }
        if station.availableBikeStands == 0 { return .full }
        if station.availableBikes <= 3 { return .low }
        return .healthy
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().stroke(stroke, lineWidth: 2)
                    )

                Image(systemName: "bicycle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32, alignment: .center)

                Text(bikeBadgeText)
                    .font(.custom("Montserrat-SemiBold", size: 9))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                    )
                    .offset(x: 12, y: -10)
            }
            .frame(width: 42, height: 36)

            Text(docksBadgeText)
                .font(.custom("Montserrat-SemiBold", size: 9))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
        }
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
        .accessibilityElement()
        .accessibilityLabel("Station Villo! \(station.displayName)")
        .accessibilityHint("Ouvre l’état de la station vélo")
    }

    private enum VilloVisualState {
        case closed
        case empty
        case low
        case full
        case healthy
    }
}

private struct EventMapMarker: View {
    let event: TransportEventImpactDTO

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(backgroundTint)
                        .frame(width: 5)

                    ZStack {
                        DS.Color.paper.opacity(0.98)

                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DS.Color.ink)
                    }
                    .frame(width: 34, height: 38)
                }
                .frame(width: 39, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )

                if let firstLine = event.impactedLines.first, !firstLine.isEmpty {
                    Text(firstLine)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(TransitLinePalette.foreground(for: firstLine))
                        .frame(minWidth: 18, minHeight: 16)
                        .padding(.horizontal, 3)
                        .background(TransitLinePalette.fill(for: firstLine))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DS.Color.ink, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .offset(x: 6, y: -6)
                }
            }

            Diamond()
                .fill(DS.Color.paper.opacity(0.98))
                .frame(width: 11, height: 11)
                .overlay(
                    Diamond()
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .offset(y: -4)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5)
        .accessibilityLabel("Événement \(event.title)")
    }

    private var backgroundTint: Color {
        switch event.impactLevel?.lowercased() {
        case "high":
            return Color(hex: "#FF8E6A")
        case "moderate":
            return Color(hex: "#F3C15D")
        default:
            return Color(hex: "#B8E28A")
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
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

private struct RouteRecommendationsSheet: View {
    let options: [HomeRouteOption]
    let modeSummaries: [RouteModeSummary]
    @Binding var selectedRouteID: UUID?
    @Binding var isExpanded: Bool
    let onSelect: (HomeRouteOption) -> Void
    let onClose: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @State private var expandedRouteID: UUID?
    @State private var selectedModeKey: String = "transit"

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let verticalMove = value.translation.height
                let predictedMove = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    if verticalMove < -70 || predictedMove < -120 {
                        isExpanded = true
                    } else if verticalMove > 110 || predictedMove > 180 {
                        if isExpanded {
                            isExpanded = false
                        } else {
                            onClose()
                        }
                    }
                }
            }
    }

    private var filteredOptions: [HomeRouteOption] {
        let subset = options.filter { $0.primaryModeKey == selectedModeKey }
        let base = subset.isEmpty ? options : subset
        return base.sorted { $0.totalDurationMinutes < $1.totalDurationMinutes }
    }
    private var recommended: HomeRouteOption? { filteredOptions.first }
    private var others: [HomeRouteOption] { Array(filteredOptions.dropFirst()) }
    private var preferredInitialMode: String {
        if modeSummaries.contains(where: { $0.modeKey == "transit" && $0.durationText != "—" }) {
            return "transit"
        }
        return modeSummaries.first(where: { $0.durationText != "—" })?.modeKey ?? "transit"
    }

    var body: some View {
        GeometryReader { proxy in
            let expandedHeight = min(proxy.size.height * 0.66, 584)
            let collapsedHeight = min(proxy.size.height * 0.34, 286)
            let sheetHeight = isExpanded ? expandedHeight : collapsedHeight

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    sheetHandle
                        .contentShape(Rectangle())
                        .gesture(sheetDragGesture)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            modeSummaryStrip
                            recommendedSection
                            optionsHeader
                            otherOptionsList
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: sheetHeight, alignment: .top)
                .background(DS.Color.paper)
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute)
                            .frame(width: 32, height: 32)
                            .background(DS.Color.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .opacity(isExpanded ? 1 : 0)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.1))
                        .frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                )
                .offset(y: max(0, dragOffset))
                .allowsHitTesting(true)
            }
            .ignoresSafeArea()
            .onAppear {
                selectedModeKey = preferredInitialMode
                expandedRouteID = recommended?.id
            }
            .onChange(of: modeSummaries.map(\.modeKey)) { _, _ in
                selectedModeKey = preferredInitialMode
                expandedRouteID = filteredOptions.first?.id
            }
        }
    }

    private var sheetHandle: some View {
        Capsule()
            .fill(DS.Color.ink.opacity(0.24))
            .frame(width: 76, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    @ViewBuilder
    private var modeSummaryStrip: some View {
        if !modeSummaries.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(modeSummaries.enumerated()), id: \.offset) { index, summary in
                    RouteModeSummaryTile(
                        summary: summary,
                        isHighlighted: summary.modeKey == selectedModeKey
                    )
                    .onTapGesture {
                        selectedModeKey = summary.modeKey
                        if let first = options.first(where: { $0.primaryModeKey == summary.modeKey }) {
                            expandedRouteID = first.id
                            onSelect(first)
                        }
                    }
                    if index < modeSummaries.count - 1 {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.12))
                            .frame(width: 1)
                    }
                }
            }
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var recommendedSection: some View {
        if let recommended {
            RouteOptionCard(
                option: recommended,
                isRecommended: true,
                isSelected: selectedRouteID == recommended.id,
                action: {
                    onSelect(recommended)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        expandedRouteID = recommended.id
                        isExpanded = true
                    }
                },
                isExpandedCard: expandedRouteID == recommended.id,
                expandedContent: AnyView(InlineRouteDetails(option: recommended)),
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        expandedRouteID = expandedRouteID == recommended.id ? nil : recommended.id
                        isExpanded = true
                    }
                }
            )
            .padding(.horizontal, 16)
        }
    }

    private var optionsHeader: some View {
        HStack(alignment: .center) {
            Text("AUTRES ITINÉRAIRES")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.ink)
            Text(String(format: "%02d", max(others.count, 0)))
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.inkMute)
            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var otherOptionsList: some View {
        VStack(spacing: 12) {
            ForEach(others) { option in
                RouteOptionCard(
                    option: option,
                    isRecommended: false,
                    isSelected: selectedRouteID == option.id,
                    action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            if expandedRouteID == option.id {
                                expandedRouteID = nil
                            } else {
                                onSelect(option)
                                expandedRouteID = option.id
                                isExpanded = true
                            }
                        }
                    },
                    isExpandedCard: expandedRouteID == option.id,
                    expandedContent: AnyView(InlineRouteDetails(option: option)),
                    onToggleExpanded: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            expandedRouteID = expandedRouteID == option.id ? nil : option.id
                            isExpanded = true
                        }
                    },
                    deltaText: option.deltaText(comparedTo: recommended)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }
}

private struct RouteOptionCard: View {
    let option: HomeRouteOption
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void
    var isExpandedCard: Bool = false
    var expandedContent: AnyView? = nil
    var onToggleExpanded: (() -> Void)? = nil
    var deltaText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                if isRecommended {
                    recommendedLayout
                } else {
                    alternativeLayout
                }
            }
            .buttonStyle(.plain)

            if let expandedContent, isExpandedCard {
                expandedContent
            }
        }
        .background(DS.Color.paper)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(option.leadingAccentColor)
                .frame(width: isRecommended ? 6 : 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? DS.Color.primary : DS.Color.ink.opacity(0.16), lineWidth: isRecommended ? 1.35 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func routeMetaPill(_ text: String, tint: Color = DS.Color.paper2, foreground: Color = DS.Color.ink) -> some View {
        Text(text.uppercased())
            .font(DS.Font.monoSmall.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(foreground)
            .padding(.horizontal, 7)
            .frame(height: 20)
            .background(tint)
            .clipShape(Capsule())
    }

    private var recommendedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Color.ink)
                        .frame(width: 42, height: 42)
                    Image(systemName: option.primaryModeIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DS.Color.paper)
                }

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.durationText)
                            .font(.system(size: 22, weight: .black))
                            .tracking(-0.8)
                            .foregroundStyle(DS.Color.ink)
                        Spacer(minLength: 12)
                        Button(action: { onToggleExpanded?() }) {
                            Image(systemName: isExpandedCard ? "chevron.up" : "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }

                    Text("\(option.primaryModeLabel.uppercased()) · \(option.transferSummary.uppercased())")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)

                    Text(option.timingHeadlineText)
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(DS.Color.inkMute)

                    if let timingSecondaryText = option.timingSecondaryText {
                        Text(timingSecondaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute.opacity(0.82))
                    }

                    if let nextDeparture = option.nextDepartureInsight {
                        RouteNextDepartureBanner(insight: nextDeparture, arrivalText: option.arrivalSummaryText)
                            .padding(.top, 2)
                    }

                    HStack(spacing: 8) {
                        ForEach(option.displayLineCodes, id: \.self) { code in
                            RouteLineMiniBadge(line: code)
                        }
                    }

                    RouteDurationStrip(segments: option.visualSegments)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 12)
            .padding(.bottom, isExpandedCard ? 8 : 12)
        }
    }

    private var alternativeLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.durationText)
                    .font(.system(size: 18, weight: .black))
                    .tracking(-0.6)
                    .foregroundStyle(DS.Color.ink)
                if let deltaText {
                    Text(deltaText.uppercased())
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                }
                Text(option.realtimeDepartureTimeText != nil || option.realtimeArrivalTimeText != nil
                     ? "\(option.realtimeDepartureTimeText ?? option.departureTimeText) → \(option.realtimeArrivalTimeText ?? option.arrivalTimeText)"
                     : "\(option.departureTimeText) → \(option.arrivalTimeText)")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(1.2)
                    .foregroundStyle(DS.Color.inkMute)
                if let timingSecondaryText = option.timingSecondaryText {
                    Text(timingSecondaryText)
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(DS.Color.inkMute.opacity(0.72))
                        .lineLimit(1)
                }
                if let nextDeparture = option.nextDepartureInsight {
                    Text("\(nextDeparture.lineCode) · \(nextDeparture.waitText)")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(DS.Color.primary)
                        .lineLimit(1)
                }
            }
            .frame(width: 88, alignment: .leading)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 6) {
                    ForEach(Array(option.displayLineCodes.enumerated()), id: \.offset) { index, code in
                        RouteLineMiniBadge(line: code)
                        if index < option.displayLineCodes.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                }

                Text("\(option.transferSummary.uppercased()) · \(option.terminalLabel.uppercased())")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }
}

private struct RouteModeSummary {
    let modeKey: String
    let title: String
    let durationText: String
    let isFastest: Bool
}

private struct RouteVisualSegment {
    let tint: Color
    let weight: CGFloat
}

private struct RouteDepartureInsight {
    let lineCode: String
    let modeText: String
    let waitText: String
    let departureText: String
    let arrivalText: String?
    let stopText: String?
    let isRealtime: Bool

    var titleText: String {
        "\(modeText) \(lineCode)"
    }

    var detailText: String {
        let destinationPart = stopText.map { "vers \($0)" }
        let arrivalPart = arrivalText.map { "arrivée \($0)" }
        return [destinationPart, "départ \(departureText)", arrivalPart]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

private struct RouteNextDepartureBanner: View {
    let insight: RouteDepartureInsight
    let arrivalText: String

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            RouteLineMiniBadge(line: insight.lineCode)
                .frame(width: 34, height: 34)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text("PROCHAIN DÉPART")
                        .font(.system(size: 8.5, weight: .heavy, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(insight.isRealtime ? "temps réel" : "prévu")
                        .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(insight.isRealtime ? DS.Color.primary : DS.Color.inkMute)
                }
                Text(insight.titleText)
                    .font(.system(size: 13.5, weight: .black))
                    .foregroundStyle(DS.Color.ink)
                Text(insight.detailText)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }

            Spacer(minLength: 8)

            VStack(alignment: .trailing, spacing: 2) {
                Text(insight.waitText)
                    .font(.system(size: 17, weight: .black))
                    .tracking(-0.35)
                    .foregroundStyle(DS.Color.primary)
                Text(arrivalText)
                    .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .background(DS.Color.primary.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.22), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}

private struct InlineRouteStepItem: Identifiable {
    let id = UUID()
    let icon: String?
    let title: String
    let meta: String
    let lineCode: String?
    let timingBadge: String?
    let timingDetail: String?
}

private struct RouteModeSummaryTile: View {
    let summary: RouteModeSummary
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary.isFastest {
                Text("⚡ RAPIDE")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(isHighlighted ? DS.Color.ink : DS.Color.paper)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(isHighlighted ? DS.Color.paper : DS.Color.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Spacer().frame(height: 16)
            }
            HStack(spacing: 6) {
                Image(systemName: summary.modeKey == "bike" ? "bicycle" : summary.modeKey == "walk" ? "figure.walk" : "tram.fill")
                    .font(.system(size: 10, weight: .medium))
                Text(summary.title.uppercased())
            }
            .font(DS.Font.monoSmall.weight(.bold))
            .tracking(1.2)
                .foregroundStyle(isHighlighted ? DS.Color.paper : DS.Color.inkMute)
            Text(summary.durationText)
                .font(.system(size: 14, weight: .black))
                .tracking(-0.4)
                .foregroundStyle(isHighlighted ? DS.Color.paper : DS.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isHighlighted ? DS.Color.ink : DS.Color.paper)
    }
}

private struct RouteLineMiniBadge: View {
    let line: String

    var body: some View {
        Text(line)
            .font(DS.Font.monoSmall.weight(.bold))
            .foregroundStyle(TransitLinePalette.foreground(for: line))
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, 3)
            .background(TransitLinePalette.fill(for: line))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct RouteDurationStrip: View {
    let segments: [RouteVisualSegment]

    private var totalWeight: CGFloat {
        max(segments.reduce(0) { $0 + $1.weight }, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = CGFloat(max(segments.count - 1, 0)) * 2
            let usableWidth = max(geo.size.width - totalSpacing, 0)

            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(segment.tint)
                        .frame(width: max(10, usableWidth * (segment.weight / totalWeight)), height: 12)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16)
            .background(DS.Color.ink.opacity(0.22))
            .clipShape(Capsule())
        }
        .frame(height: 16)
    }
}

private struct InlineRouteDetails: View {
    let option: HomeRouteOption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DS.Color.primary)
                .frame(height: 2)
                .padding(.horizontal, -14)
                .padding(.bottom, 8)

            ForEach(Array(option.inlineSteps.enumerated()), id: \.element.id) { index, item in
                HStack(alignment: .top, spacing: 10) {
                    if let lineCode = item.lineCode {
                        RouteLineMiniBadge(line: lineCode)
                            .frame(width: 30, height: 30)
                    } else {
                        ZStack {
                            Circle()
                                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
                                .frame(width: 28, height: 28)
                            if let icon = item.icon {
                                Image(systemName: icon)
                                    .font(.system(size: 12, weight: .medium))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Text(item.title)
                                .font(.system(size: 12.5, weight: .bold))
                                .foregroundStyle(DS.Color.ink)
                                .lineLimit(2)
                            Spacer(minLength: 6)
                            if let timingBadge = item.timingBadge {
                                Text(timingBadge)
                                    .font(.system(size: 10.5, weight: .black))
                                    .tracking(-0.1)
                                    .foregroundStyle(DS.Color.primary)
                                    .lineLimit(1)
                            }
                        }
                        if let timingDetail = item.timingDetail {
                            Text(timingDetail)
                                .font(.system(size: 11.5, weight: .semibold))
                                .foregroundStyle(DS.Color.ink)
                                .lineLimit(1)
                        }
                        Text(item.meta)
                            .font(DS.Font.monoSmall)
                            .tracking(1.2)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 8)

                if index < option.inlineSteps.count - 1 {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.12))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

private struct HomeRouteOption: Identifiable {
    let id = UUID()
    let route: MKRoute?
    let backendAlternative: TransportAlternativeDTO?
    let originName: String
    let destinationName: String
    let durationText: String
    let transitSummary: String
    let walkingSummary: String
    let reliabilityText: String

    static func from(
        route: MKRoute?,
        index: Int,
        originName: String,
        destinationName: String,
        backendAlternative: TransportAlternativeDTO? = nil
    ) -> HomeRouteOption {
        let transitSteps = route?.steps.filter { $0.transportType == .transit } ?? []
        let walkingDistance = route?.steps.filter { $0.transportType == .walking }.map(\.distance).reduce(0, +) ?? 0
        let walkingMinutes = max(1, Int((walkingDistance / 75).rounded()))
        let transferCount = max(0, transitSteps.count - 1)
        let durationMinutes = backendAlternative?.totalDurationMinutes ?? max(1, Int((((route?.expectedTravelTime) ?? 60) / 60).rounded()))
        let transitSummary = backendAlternative.map(Self.transitSummary(from:)) ?? (transitSteps.isEmpty ? "à pied" : "\(transitSteps.count) transport")
        let walkingSummary = "\(backendAlternative?.walkingMinutes ?? walkingMinutes) min à pied"
        let reliabilityText = backendAlternative.map(Self.reliabilitySummary(from:)) ?? (transferCount == 0 ? "direct" : "\(transferCount) corresp.")

        return HomeRouteOption(
            route: route,
            backendAlternative: backendAlternative,
            originName: originName,
            destinationName: destinationName,
            durationText: "\(durationMinutes) min",
            transitSummary: transitSummary,
            walkingSummary: walkingSummary,
            reliabilityText: reliabilityText
        )
    }

    var detailSegments: [RouteItinerarySegment] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            return detailSegments(from: steps)
        }

        guard let route else { return [] }

        let startDate = Date()
        let usefulSteps = route.steps.filter { step in
            step.distance > 8 || !step.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var elapsedMinutes = 0
        var segments: [RouteItinerarySegment] = [
            RouteItinerarySegment(
                timeText: elapsedMinutes.clockString(from: startDate),
                placeTitle: originName,
                icon: nil,
                accentColor: DS.Color.paper,
                stepCard: nil,
                durationBadge: nil
            )
        ]

        for (index, step) in usefulSteps.enumerated() {
            let durationMinutes = Self.estimatedMinutes(for: step)
            elapsedMinutes += durationMinutes

            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = instruction.isEmpty ? Self.fallbackTitle(for: step, destinationName: destinationName) : instruction
            let lineCode = Self.extractLineCode(from: instruction)
            let isLastLeg = index == usefulSteps.count - 1

            segments.append(
                RouteItinerarySegment(
                    timeText: elapsedMinutes.clockString(from: startDate),
                    placeTitle: Self.placeTitle(for: step, isLastLeg: isLastLeg, destinationName: destinationName, lineCode: lineCode),
                    icon: Self.iconName(for: step),
                    accentColor: Self.accentColor(for: step, lineCode: lineCode),
                    stepCard: RouteItineraryStepCard(
                        style: step.transportType == .walking ? .white : .mint,
                        title: title,
                        subtitle: Self.subtitle(for: step),
                        lineBadge: lineCode,
                        serviceInfo: nil
                    ),
                    durationBadge: "\(durationMinutes) min",
                    stopCountText: Self.stopCountText(for: step)
                )
            )
        }

        if segments.last?.placeTitle != destinationName {
            segments.append(
                RouteItinerarySegment(
                    timeText: max(elapsedMinutes, Int((route.expectedTravelTime / 60).rounded())).clockString(from: startDate),
                    placeTitle: destinationName,
                    icon: nil,
                    accentColor: DS.Color.primary,
                    stepCard: nil,
                    durationBadge: nil
                )
            )
        }

        return segments
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        if let backendAlternative,
           let backendCoordinates = Self.coordinates(from: backendAlternative),
           !backendCoordinates.isEmpty {
            return backendCoordinates
        }

        guard let route else { return [] }
        let polyline = route.polyline
        return (0..<polyline.pointCount).map { polyline.points()[$0].coordinate }
    }

    var mapRectWithPadding: MKMapRect {
        let rect: MKMapRect
        if routeCoordinates.count > 1 {
            rect = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count).boundingMapRect
        } else if let route {
            rect = route.polyline.boundingMapRect
        } else if let first = routeCoordinates.first {
            rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1200, height: 1200))
        } else {
            rect = MKMapRect.world
        }
        return rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35)
    }

    func primaryBearing(from current: CLLocationCoordinate2D) -> Double? {
        let coords = routeCoordinates
        guard coords.count > 1 else { return nil }
        let nextCoord = nextCoordinate(from: current, in: coords) ?? coords[1]
        return current.bearing(to: nextCoord)
    }

    func arInstruction(from current: CLLocationCoordinate2D) -> RouteARInstruction {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            let nextStep = steps.first { step in
                guard let coordinate = Self.primaryCoordinate(for: step) else { return false }
                return current.distance(to: coordinate) > 20
            } ?? steps.first

            let primaryText = nextStep?.instruction ?? "Suivez l’itinéraire vers \(destinationName)"
            let secondaryText = nextStep.map(Self.summaryText(for:)) ?? walkingSummary
            let distanceText = nextStep
                .flatMap(Self.primaryCoordinate(for:))
                .map { current.distance(to: $0).distanceLabel }
                ?? durationText

            return RouteARInstruction(
                primaryText: primaryText,
                secondaryText: secondaryText,
                distanceText: distanceText
            )
        }

        guard let route else {
            return RouteARInstruction(
                primaryText: "Suivez l’itinéraire vers \(destinationName)",
                secondaryText: walkingSummary,
                distanceText: durationText
            )
        }

        let usefulSteps = route.steps.filter { !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nextStep = usefulSteps.first { step in
            guard let coord = step.polyline.firstCoordinate else { return false }
            return current.distance(to: coord) > 20
        } ?? usefulSteps.first

        let cleanedInstruction = nextStep?.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryText = (cleanedInstruction?.isEmpty == false ? cleanedInstruction : nil) ?? "Suivez l’itinéraire vers \(destinationName)"
        let distance = nextStep?.distance ?? route.distance
        let transportType = nextStep?.transportType ?? .walking

        return RouteARInstruction(
            primaryText: primaryText,
            secondaryText: transportType == .transit ? transitSummary : walkingSummary,
            distanceText: distance.distanceLabel
        )
    }

    private func detailSegments(from steps: [TransportRouteStepDTO]) -> [RouteItinerarySegment] {
        let startDate = Date()
        var elapsedMinutes = 0
        var segments: [RouteItinerarySegment] = [
            RouteItinerarySegment(
                timeText: elapsedMinutes.clockString(from: startDate),
                placeTitle: originName,
                icon: nil,
                accentColor: DS.Color.paper,
                stepCard: nil,
                durationBadge: nil
            )
        ]

        let sortedSteps = steps.sorted { $0.order < $1.order }
        for (index, step) in sortedSteps.enumerated() {
            elapsedMinutes += max(1, step.durationMinutes)
            let isLastStep = index == sortedSteps.count - 1

            segments.append(
                RouteItinerarySegment(
                    timeText: elapsedMinutes.clockString(from: startDate),
                    placeTitle: placeTitle(for: step, isLastStep: isLastStep),
                    icon: Self.iconName(for: step),
                    accentColor: Self.accentColor(for: step),
                    stepCard: RouteItineraryStepCard(
                        style: Self.cardStyle(for: step),
                        title: step.instruction,
                        subtitle: Self.subtitle(for: step),
                        lineBadge: step.line,
                        serviceInfo: nil
                    ),
                    durationBadge: "\(max(1, step.durationMinutes)) min",
                    stopCountText: step.stopsCount.map { $0 > 1 ? "\($0) arrêts" : "1 arrêt" }
                )
            )
        }

        if segments.last?.placeTitle != destinationName {
            segments.append(
                RouteItinerarySegment(
                    timeText: max(elapsedMinutes, totalDurationMinutes).clockString(from: startDate),
                    placeTitle: destinationName,
                    icon: nil,
                    accentColor: DS.Color.primary,
                    stepCard: nil,
                    durationBadge: nil
                )
            )
        }

        return segments
    }

    var totalDurationMinutes: Int {
        backendAlternative?.totalDurationMinutes ?? max(1, Int((((route?.expectedTravelTime) ?? 60) / 60).rounded()))
    }

    var departureTimeText: String {
        realtimeDepartureTimeText ?? scheduledDepartureTimeText ?? Self.timeFormatter.string(from: Date())
    }

    var arrivalTimeText: String {
        realtimeArrivalTimeText
            ?? scheduledArrivalTimeText
            ?? Self.timeFormatter.string(from: Date().addingTimeInterval(TimeInterval(totalDurationMinutes * 60)))
    }

    var scheduledDepartureTimeText: String? {
        backendAlternative?.scheduledDepartureAt.map { Self.timeFormatter.string(from: $0) }
    }

    var scheduledArrivalTimeText: String? {
        backendAlternative?.scheduledArrivalAt.map { Self.timeFormatter.string(from: $0) }
    }

    var realtimeDepartureTimeText: String? {
        backendAlternative?.realtimeDepartureAt.map { Self.timeFormatter.string(from: $0) }
    }

    var realtimeArrivalTimeText: String? {
        backendAlternative?.realtimeArrivalAt.map { Self.timeFormatter.string(from: $0) }
    }

    var hasRealtimeTimingDelta: Bool {
        scheduledDepartureTimeText != realtimeDepartureTimeText || scheduledArrivalTimeText != realtimeArrivalTimeText
    }

    var timingHeadlineText: String {
        if let realtimeDepartureTimeText, let realtimeArrivalTimeText {
            return "TEMPS RÉEL \(realtimeDepartureTimeText) → \(realtimeArrivalTimeText)"
        }
        if let scheduledDepartureTimeText, let scheduledArrivalTimeText {
            return "PRÉVU \(scheduledDepartureTimeText) → \(scheduledArrivalTimeText)"
        }
        return "DÉPART \(departureTimeText) · ARRIVÉE \(arrivalTimeText)"
    }

    var timingSecondaryText: String? {
        guard hasRealtimeTimingDelta,
              let scheduledDepartureTimeText,
              let scheduledArrivalTimeText else { return nil }
        return "Prévu \(scheduledDepartureTimeText) → \(scheduledArrivalTimeText)"
    }

    var arrivalSummaryText: String {
        "Arrivée \(arrivalTimeText)"
    }

    var nextDepartureInsight: RouteDepartureInsight? {
        guard let step = backendAlternative?.steps?
            .sorted(by: { $0.order < $1.order })
            .first(where: { step in
                guard let line = step.line else { return false }
                return !line.isEmpty && !["walk", "bike"].contains(step.mode.lowercased())
            }),
            let line = step.line else { return nil }

        let departureDate = step.realtimeDepartureAt ?? step.scheduledDepartureAt
        let departureText = departureDate.map(Self.timeFormatter.string(from:)) ?? departureTimeText
        let arrivalText = (step.realtimeArrivalAt ?? step.scheduledArrivalAt).map(Self.timeFormatter.string(from:))
        let waitText = step.realtimeDepartureMinutes.map(Self.waitText)
            ?? departureDate.map(Self.waitText)
            ?? "À \(departureText)"

        return RouteDepartureInsight(
            lineCode: line,
            modeText: Self.modeText(for: step),
            waitText: waitText,
            departureText: departureText,
            arrivalText: arrivalText,
            stopText: step.destination ?? step.arrivalStopName,
            isRealtime: step.realtimeDepartureAt != nil || step.realtimeDepartureMinutes != nil
        )
    }

    var primaryModeKey: String {
        if let backendAlternative {
            return Self.primaryMode(for: backendAlternative)
        }
        let transportTypes = Set((route?.steps ?? []).map { $0.transportType.rawValue })
        if transportTypes.contains(MKDirectionsTransportType.transit.rawValue) { return "transit" }
        if transportTypes.contains(MKDirectionsTransportType.walking.rawValue) && transportTypes.count == 1 { return "walk" }
        return "bike"
    }

    var primaryModeLabel: String {
        switch primaryModeKey {
        case "bike": return "Vélo"
        case "walk": return "À pied"
        default: return "Transport"
        }
    }

    var primaryModeIcon: String {
        switch primaryModeKey {
        case "bike": return "bicycle"
        case "walk": return "figure.walk"
        default: return "tram.fill"
        }
    }

    var transferSummary: String {
        let transfers = backendAlternative?.transfers ?? max(0, displayLineCodes.count - 1)
        return "\(transfers) corresp."
    }

    var displayLineCodes: [String] {
        if let backendAlternative, !backendAlternative.lines.isEmpty {
            return Array(backendAlternative.lines.prefix(4))
        }

        let extracted = (route?.steps ?? []).compactMap { step -> String? in
            guard step.transportType == .transit else { return nil }
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.extractLineCode(from: instruction)
        }
        return Array(NSOrderedSet(array: extracted).array as? [String] ?? [])
    }

    var terminalLabel: String {
        if let backendAlternative,
           let lastTransit = (backendAlternative.steps ?? []).last(where: { $0.line != nil }),
           let stop = lastTransit.arrivalStopName ?? lastTransit.destination {
            return stop
        }
        return destinationName
    }

    var dedupeKey: String {
        let lines = displayLineCodes.joined(separator: "-")
        return "\(primaryModeKey)|\(totalDurationMinutes)|\(lines)|\(terminalLabel)"
    }

    var leadingAccentColor: Color {
        if let first = displayLineCodes.first {
            return TransitLinePalette.fill(for: first)
        }
        switch primaryModeKey {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.inkMute.opacity(0.45)
        default: return DS.Color.primary
        }
    }

    var visualSegments: [RouteVisualSegment] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            return steps.map { step in
                RouteVisualSegment(
                    tint: Self.segmentColor(for: step),
                    weight: max(CGFloat(step.durationMinutes), 0.8)
                )
            }
        }

        let usefulSteps = (route?.steps ?? []).filter { $0.distance > 8 || !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return usefulSteps.map { step in
            RouteVisualSegment(
                tint: step.transportType == .walking
                    ? DS.Color.ink.opacity(0.28)
                    : TransitLinePalette.fill(for: Self.extractLineCode(from: step.instructions) ?? "1"),
                weight: max(CGFloat(Self.estimatedMinutes(for: step)), 0.8)
            )
        }
    }

    var inlineSteps: [InlineRouteStepItem] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            return steps.sorted { $0.order < $1.order }.map { step in
                InlineRouteStepItem(
                    icon: Self.inlineIcon(for: step),
                    title: Self.inlineTitle(for: step),
                    meta: Self.inlineMeta(for: step),
                    lineCode: step.line,
                    timingBadge: Self.inlineTimingBadge(for: step),
                    timingDetail: Self.inlineTimingDetail(for: step)
                )
            }
        }

        return detailSegments.compactMap { segment in
            guard let stepCard = segment.stepCard else { return nil }
            return InlineRouteStepItem(
                icon: segment.icon,
                title: stepCard.title,
                meta: [segment.stopCountText, segment.durationBadge].compactMap { $0 }.joined(separator: " · "),
                lineCode: stepCard.lineBadge,
                timingBadge: nil,
                timingDetail: nil
            )
        }
    }

    func deltaText(comparedTo base: HomeRouteOption?) -> String? {
        guard let base else { return nil }
        let delta = totalDurationMinutes - base.totalDurationMinutes
        guard delta > 0 else { return nil }
        return "+\(delta) min"
    }

    private static func estimatedMinutes(for step: MKRoute.Step) -> Int {
        switch step.transportType {
        case .walking:
            return max(1, Int((step.distance / 75).rounded()))
        case .transit:
            return max(2, Int((step.distance / 280).rounded()))
        default:
            return max(2, Int((step.distance / 250).rounded()))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.timeZone = TimeZone(identifier: "Europe/Brussels")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func modeText(for step: TransportRouteStepDTO) -> String {
        switch step.mode.lowercased() {
        case "bus": return "Bus"
        case "metro": return "Métro"
        case "tram": return "Tram"
        default: return "Ligne"
        }
    }

    private static func waitText(_ minutes: Int) -> String {
        if minutes <= 0 { return "Maintenant" }
        if minutes == 1 { return "Dans 1 min" }
        return "Dans \(minutes) min"
    }

    private static func waitText(for date: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSince(Date()) / 60))
        if minutes <= 0 { return "Maintenant" }
        if minutes <= 90 { return waitText(minutes) }
        return "À \(timeFormatter.string(from: date))"
    }

    private static func extractLineCode(from instruction: String) -> String? {
        let pattern = #"\b(T?\d{1,3})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(instruction.startIndex..<instruction.endIndex, in: instruction)
        guard let match = regex.firstMatch(in: instruction, range: range),
              let foundRange = Range(match.range(at: 1), in: instruction) else { return nil }
        return String(instruction[foundRange]).uppercased()
    }

    private static func iconName(for step: MKRoute.Step) -> String? {
        switch step.transportType {
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        default: return nil
        }
    }

    private static func accentColor(for step: MKRoute.Step, lineCode: String?) -> Color {
        switch step.transportType {
        case .walking:
            return DS.Color.paper2
        case .transit:
            if let lineCode {
                return TransitLinePalette.fill(for: lineCode)
            }
            return DS.Color.community
        default:
            return DS.Color.inkMute
        }
    }

    private static func placeTitle(for step: MKRoute.Step, isLastLeg: Bool, destinationName: String, lineCode: String?, lineFallback: String = "Transport") -> String {
        if isLastLeg && step.transportType == .walking {
            return destinationName
        }
        if let lineCode {
            return "Ligne \(lineCode)"
        }
        switch step.transportType {
        case .walking: return "À pied"
        case .transit: return lineFallback
        default: return "Étape"
        }
    }

    private static func fallbackTitle(for step: MKRoute.Step, destinationName: String) -> String {
        switch step.transportType {
        case .walking:
            return "Marcher vers \(destinationName)"
        case .transit:
            return "Prendre le transport suivant"
        default:
            return "Suivre l’itinéraire"
        }
    }

    private static func subtitle(for step: MKRoute.Step) -> String {
        switch step.transportType {
        case .walking:
            return step.distance.distanceLabel
        case .transit:
            return "Étape transport"
        default:
            return "Suivez l’itinéraire"
        }
    }

    private static func stopCountText(for step: MKRoute.Step) -> String? {
        guard step.transportType == .transit else { return nil }
        let estimatedStops = max(1, Int((step.distance / 350).rounded()))
        return estimatedStops > 1 ? "\(estimatedStops) arrêts" : "1 arrêt"
    }

    private func placeTitle(for step: TransportRouteStepDTO, isLastStep: Bool) -> String {
        if isLastStep, step.mode == "walk" {
            return destinationName
        }
        if let stopName = step.stopName, !stopName.isEmpty {
            return stopName
        }
        if let arrivalStopName = step.arrivalStopName, !arrivalStopName.isEmpty {
            return arrivalStopName
        }
        if let line = step.line, !line.isEmpty {
            return "Ligne \(line)"
        }
        switch step.mode.lowercased() {
        case "bike": return "À vélo"
        case "walk": return "À pied"
        default: return "Correspondance"
        }
    }

    private static func transitSummary(from alternative: TransportAlternativeDTO) -> String {
        if !alternative.lines.isEmpty {
            let label = alternative.lines.count > 1 ? "lignes" : "ligne"
            return "\(alternative.lines.count) \(label)"
        }
        switch primaryMode(for: alternative) {
        case "bike": return "à vélo"
        case "walk": return "à pied"
        default: return "transport"
        }
    }

    private static func reliabilitySummary(from alternative: TransportAlternativeDTO) -> String {
        if alternative.transfers == 0 {
            return "direct"
        }
        return "\(alternative.transfers) corresp."
    }

    static func primaryMode(for alternative: TransportAlternativeDTO) -> String {
        let modes = Set((alternative.steps ?? []).map { $0.mode.lowercased() })
        if modes.contains("tram") || modes.contains("bus") || modes.contains("metro") {
            return "transit"
        }
        if modes.contains("bike") {
            return "bike"
        }
        return "walk"
    }

    private static func coordinates(from alternative: TransportAlternativeDTO) -> [CLLocationCoordinate2D]? {
        let points = (alternative.steps ?? []).flatMap { step in
            (step.path ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        }
        guard !points.isEmpty else { return nil }

        var deduped: [CLLocationCoordinate2D] = []
        for point in points {
            if deduped.last?.latitude == point.latitude && deduped.last?.longitude == point.longitude {
                continue
            }
            deduped.append(point)
        }
        return deduped
    }

    static func segmentCoordinates(for step: TransportRouteStepDTO) -> [CLLocationCoordinate2D] {
        let pathCoordinates = (step.path ?? []).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }
        if pathCoordinates.count > 1 {
            return dedupedCoordinates(pathCoordinates)
        }

        var coordinates: [CLLocationCoordinate2D] = []
        if let lat = step.startLatitude, let lng = step.startLongitude {
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        if let lat = step.targetLatitude, let lng = step.targetLongitude {
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        return dedupedCoordinates(coordinates)
    }

    static func mapStrokeColor(for step: TransportRouteStepDTO) -> Color {
        if let line = step.line, !line.isEmpty {
            return TransitLinePalette.fill(for: line)
        }
        switch step.mode.lowercased() {
        case "bike":
            return DS.Color.villo
        case "walk":
            return DS.Color.ink.opacity(0.30)
        default:
            return DS.Color.primary
        }
    }

    static func mapStrokeWidth(for step: TransportRouteStepDTO) -> CGFloat {
        switch step.mode.lowercased() {
        case "walk":
            return 4
        case "bike":
            return 5
        default:
            return 6
        }
    }

    private static func primaryCoordinate(for step: TransportRouteStepDTO) -> CLLocationCoordinate2D? {
        if let lat = step.startLatitude, let lng = step.startLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let lat = step.targetLatitude, let lng = step.targetLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let path = step.path?.first {
            return CLLocationCoordinate2D(latitude: path.lat, longitude: path.lng)
        }
        return nil
    }

    private static func iconName(for step: TransportRouteStepDTO) -> String? {
        switch step.mode.lowercased() {
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "bus": return "bus.fill"
        default: return "tram.fill"
        }
    }

    private static func accentColor(for step: TransportRouteStepDTO) -> Color {
        if let line = step.line {
            return TransitLinePalette.fill(for: line)
        }
        switch step.mode.lowercased() {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.paper2
        case "bus": return DS.Color.community
        case "metro": return DS.Color.primary
        default: return DS.Color.accent
        }
    }

    private static func cardStyle(for step: TransportRouteStepDTO) -> RouteItineraryStepCard.CardStyle {
        switch step.mode.lowercased() {
        case "walk": return .white
        default: return .mint
        }
    }

    private static func subtitle(for step: TransportRouteStepDTO) -> String {
        if let arrivalStopName = step.arrivalStopName, !arrivalStopName.isEmpty {
            return "Vers \(arrivalStopName)"
        }
        if let destination = step.destination, !destination.isEmpty {
            return "Direction \(destination)"
        }
        switch step.mode.lowercased() {
        case "bike": return "Étape à vélo"
        case "walk": return "Étape à pied"
        default: return "Étape transport"
        }
    }

    private static func summaryText(for step: TransportRouteStepDTO) -> String {
        if let line = step.line, !line.isEmpty {
            return "Ligne \(line)"
        }
        switch step.mode.lowercased() {
        case "bike": return "Pédalez vers la prochaine étape"
        case "walk": return "Marche en cours"
        default: return "Transport en cours"
        }
    }

    private static func segmentColor(for step: TransportRouteStepDTO) -> Color {
        if let line = step.line, !line.isEmpty {
            return TransitLinePalette.fill(for: line)
        }
        switch step.mode.lowercased() {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.ink.opacity(0.28)
        default: return DS.Color.ink.opacity(0.22)
        }
    }

    private static func inlineIcon(for step: TransportRouteStepDTO) -> String? {
        switch step.mode.lowercased() {
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        default: return nil
        }
    }

    private static func inlineTitle(for step: TransportRouteStepDTO) -> String {
        if let line = step.line, !line.isEmpty {
            let start = step.stopName ?? "Départ"
            let end = step.arrivalStopName ?? step.destination ?? "Arrivée"
            return "\(start) → \(end)"
        }

        if step.mode.lowercased() == "walk" {
            if let target = step.stopName ?? step.arrivalStopName ?? step.destination {
                return "Marche vers \(target)"
            }
            return "Marche"
        }

        if step.mode.lowercased() == "bike" {
            return "Vélo vers \(step.arrivalStopName ?? step.destination ?? "destination")"
        }

        return step.destination ?? "Correspondance"
    }

    private static func inlineMeta(for step: TransportRouteStepDTO) -> String {
        var parts: [String] = []
        if let stops = step.stopsCount {
            parts.append(stops > 1 ? "\(stops) arrêts" : "1 arrêt")
        } else if step.mode.lowercased() == "walk",
                  let startLat = step.startLatitude,
                  let startLng = step.startLongitude,
                  let endLat = step.targetLatitude,
                  let endLng = step.targetLongitude {
            let distance = CLLocation(latitude: startLat, longitude: startLng)
                .distance(from: CLLocation(latitude: endLat, longitude: endLng))
            parts.append(distance.distanceLabel.uppercased())
        }
        parts.append("\(max(1, step.durationMinutes)) min".uppercased())
        if let realtimeDepartureAt = step.realtimeDepartureAt {
            let departure = timeFormatter.string(from: realtimeDepartureAt)
            if let realtimeArrivalAt = step.realtimeArrivalAt {
                parts.append("\(departure)→\(timeFormatter.string(from: realtimeArrivalAt))")
            } else {
                parts.append("DÉP. \(departure)")
            }
        } else if let scheduledDepartureAt = step.scheduledDepartureAt {
            let departure = timeFormatter.string(from: scheduledDepartureAt)
            if let scheduledArrivalAt = step.scheduledArrivalAt {
                parts.append("\(departure)→\(timeFormatter.string(from: scheduledArrivalAt))")
            } else {
                parts.append("PRÉVU \(departure)")
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func inlineTimingBadge(for step: TransportRouteStepDTO) -> String? {
        guard step.line != nil else { return nil }
        if let minutes = step.realtimeDepartureMinutes {
            return waitText(minutes)
        }
        if let realtimeDepartureAt = step.realtimeDepartureAt {
            return waitText(for: realtimeDepartureAt)
        }
        if let scheduledDepartureAt = step.scheduledDepartureAt {
            return "Prévu \(timeFormatter.string(from: scheduledDepartureAt))"
        }
        return nil
    }

    private static func inlineTimingDetail(for step: TransportRouteStepDTO) -> String? {
        let departureDate = step.realtimeDepartureAt ?? step.scheduledDepartureAt
        let arrivalDate = step.realtimeArrivalAt ?? step.scheduledArrivalAt
        guard let departureDate else { return nil }

        let source = (step.realtimeDepartureAt != nil || step.realtimeDepartureMinutes != nil) ? "Temps réel" : "Horaire prévu"
        let departure = timeFormatter.string(from: departureDate)
        if let arrivalDate {
            return "\(source) · \(departure) → \(timeFormatter.string(from: arrivalDate))"
        }
        return "\(source) · départ \(departure)"
    }

    private func nextCoordinate(from current: CLLocationCoordinate2D, in coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coords.isEmpty else { return nil }
        let nearest = coords.enumerated().min { lhs, rhs in
            current.distance(to: lhs.element) < current.distance(to: rhs.element)
        }
        guard let nearest else { return nil }
        return coords[min(coords.count - 1, nearest.offset + 1)]
    }

    private static func dedupedCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var deduped: [CLLocationCoordinate2D] = []
        for point in coordinates {
            if deduped.last?.latitude == point.latitude && deduped.last?.longitude == point.longitude {
                continue
            }
            deduped.append(point)
        }
        return deduped
    }
}

private struct RouteItineraryDetailsView: View {
    let option: HomeRouteOption
    let onBack: () -> Void
    let onClose: () -> Void
    let onShowMap: () -> Void
    let onStartAR: () -> Void

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("ITINÉRAIRE DÉTAILLÉ")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(DS.Color.ink)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute)
                            .frame(width: 36, height: 36)
                            .overlay(
                                RoundedRectangle(cornerRadius: 8)
                                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 10)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        itinerarySummaryCard

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(option.detailSegments.enumerated()), id: \.offset) { index, segment in
                                RouteTimelineRow(
                                    segment: segment,
                                    isFirst: index == 0,
                                    isLast: index == option.detailSegments.count - 1
                                )
                            }
                        }

                        VStack(spacing: 12) {
                            Button(action: onStartAR) {
                                HStack(spacing: 10) {
                                    Image(systemName: "camera.viewfinder")
                                        .font(.system(size: 18, weight: .medium))
                                    Text("Guidage caméra")
                                        .font(.system(size: 14, weight: .bold))
                                }
                                .foregroundStyle(DS.Color.primaryForeground)
                                .frame(maxWidth: .infinity)
                                .frame(height: 50)
                                .background(DS.Color.primary)
                                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button(action: onShowMap) {
                                Text("Voir sur la carte")
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 48)
                                    .background(DS.Color.paper)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                                            .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
                                    )
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var itinerarySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("TRAJET RECOMMANDÉ")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.originName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                    Text("VERS")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(option.destinationName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(option.durationText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text(option.timingHeadlineText.uppercased())
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(DS.Color.inkMute)
                    if let timingSecondaryText = option.timingSecondaryText {
                        Text(timingSecondaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute.opacity(0.82))
                    }
                }
            }

            HStack(spacing: 8) {
                detailPill(option.transitSummary)
                detailPill(option.walkingSummary)
                detailPill(option.reliabilityText, tint: DS.Color.community.opacity(0.14), foreground: DS.Color.community)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
    }

    private func detailPill(_ text: String, tint: Color = DS.Color.paper2, foreground: Color = DS.Color.ink) -> some View {
        Text(text.uppercased())
            .font(DS.Font.monoSmall.weight(.bold))
            .tracking(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint)
            .clipShape(Capsule())
    }
}

private struct RouteARNavigationView: View {
    let option: HomeRouteOption
    let onClose: () -> Void

    @StateObject private var locationManager = HomeLocationManager()

    private var routeBearing: Double {
        option.primaryBearing(from: locationManager.displayCoordinate) ?? locationManager.heading
    }

    private var relativeTurnAngle: Double {
        let delta = routeBearing - locationManager.heading
        return ((delta + 540).truncatingRemainder(dividingBy: 360)) - 180
    }

    private var currentInstruction: RouteARInstruction {
        option.arInstruction(from: locationManager.displayCoordinate)
    }

    var body: some View {
        ZStack {
            CameraPreviewView()
                .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.16),
                    Color.clear,
                    Color.black.opacity(0.08)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack {
                HStack {
                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 38, height: 38)
                            .background(DS.Color.paper.opacity(0.92))
                            .overlay(
                                RoundedRectangle(cornerRadius: 10, style: .continuous)
                                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 62)

                Spacer()
            }

            ARRouteChevronOverlay()
                .rotationEffect(.degrees(relativeTurnAngle * 0.18))
                .allowsHitTesting(false)

            VStack {
                Spacer()

                ARInstructionOverlay(
                    instruction: currentInstruction,
                    relativeTurnAngle: relativeTurnAngle
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 220)
            }

            VStack {
                Spacer()

                ARMiniMapCard(
                    option: option,
                    userCoordinate: locationManager.displayCoordinate,
                    heading: locationManager.heading
                )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 22)
            }
        }
        .onAppear { locationManager.start() }
    }
}

private struct ARRouteChevronOverlay: View {
    var body: some View {
        GeometryReader { proxy in
            ZStack {
                Path { path in
                    let width = proxy.size.width
                    let height = proxy.size.height
                    let centerX = width * 0.52
                    path.addArc(
                        center: CGPoint(x: centerX, y: height * 0.72),
                        radius: width * 0.28,
                        startAngle: .degrees(198),
                        endAngle: .degrees(330),
                        clockwise: false
                    )
                }
                .stroke(
                    AppTheme.Palette.info.opacity(0.55),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .blur(radius: 4)

                VStack(spacing: 10) {
                    Spacer()

                    ForEach(0..<8, id: \.self) { index in
                        ARChevronShape()
                            .fill(AppTheme.Palette.info.opacity(0.92 - Double(index) * 0.08))
                            .frame(
                                width: max(54, 148 - CGFloat(index) * 12),
                                height: max(24, 56 - CGFloat(index) * 4)
                            )
                            .shadow(color: AppTheme.Palette.info.opacity(0.45), radius: 10, x: 0, y: 0)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding(.bottom, 132)
            }
        }
    }
}

private struct ARMiniMapCard: View {
    let option: HomeRouteOption
    let userCoordinate: CLLocationCoordinate2D
    let heading: Double

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(option.destinationName)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Text(option.durationText)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Color.paper.opacity(0.96))

                Map(initialPosition: .rect(option.mapRectWithPadding)) {
                    if option.routeCoordinates.count > 1 {
                        MapPolyline(coordinates: option.routeCoordinates)
                            .stroke(DS.Color.community, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                    }

                    Annotation("", coordinate: userCoordinate, anchor: .center) {
                        ZStack {
                            Circle()
                                .fill(DS.Color.community.opacity(0.16))
                                .frame(width: 52, height: 52)
                            Circle()
                                .fill(DS.Color.primary)
                                .frame(width: 26, height: 26)
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(heading))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .environment(\.colorScheme, .light)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .frame(height: 170)
        }
        .padding(18)
        .background(DS.Color.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct ARChevronShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: 0))
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        path.addLine(to: CGPoint(x: rect.width * 0.72, y: rect.height))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.height * 0.34))
        path.addLine(to: CGPoint(x: rect.width * 0.28, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: rect.height))
        path.closeSubpath()
        return path
    }
}

private struct ARInstructionOverlay: View {
    let instruction: RouteARInstruction
    let relativeTurnAngle: Double

    private var directionText: String {
        switch relativeTurnAngle {
        case ..<(-35): return "Tournez à gauche"
        case 35...: return "Tournez à droite"
        default: return "Continuez tout droit"
        }
    }

    private var directionIcon: String {
        switch relativeTurnAngle {
        case ..<(-35): return "arrow.turn.up.left"
        case 35...: return "arrow.turn.up.right"
        default: return "arrow.up"
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: directionIcon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.community)

                Text(directionText)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)

                Spacer()

                Text(instruction.distanceText)
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.ink)
            }

            Text(instruction.primaryText)
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let secondaryText = instruction.secondaryText {
                Text(secondaryText)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.Color.paper.opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
    }
}

private struct CameraPreviewView: UIViewRepresentable {
    func makeUIView(context: Context) -> CameraPreviewUIView {
        CameraPreviewUIView()
    }

    func updateUIView(_ uiView: CameraPreviewUIView, context: Context) {}
}

private final class CameraPreviewUIView: UIView {
    private let session = AVCaptureSession()
    private let previewLayer = AVCaptureVideoPreviewLayer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        backgroundColor = .black
        previewLayer.videoGravity = .resizeAspectFill
        layer.addSublayer(previewLayer)
        configureSession()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        previewLayer.frame = bounds
    }

    private func configureSession() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            setupInputAndStart()
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                if granted {
                    DispatchQueue.main.async {
                        self.setupInputAndStart()
                    }
                }
            }
        default:
            break
        }
    }

    private func setupInputAndStart() {
        guard session.inputs.isEmpty,
              let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back),
              let input = try? AVCaptureDeviceInput(device: device),
              session.canAddInput(input) else {
            return
        }

        session.beginConfiguration()
        session.sessionPreset = .high
        session.addInput(input)
        session.commitConfiguration()
        previewLayer.session = session

        if !session.isRunning {
            DispatchQueue.global(qos: .userInitiated).async {
                self.session.startRunning()
            }
        }
    }

    deinit {
        if session.isRunning {
            session.stopRunning()
        }
    }
}

private struct RouteTimelineRow: View {
    let segment: RouteItinerarySegment
    let isFirst: Bool
    let isLast: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(segment.timeText)
                .font(DS.Font.mono)
                .foregroundStyle(DS.Color.inkMute)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 2)

            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(segment.accentColor.opacity(0.9))
                        .frame(width: 3, height: 16)
                }

                Circle()
                    .fill(segment.accentColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.paper, lineWidth: segment.stepCard == nil ? 1 : 0)
                    )

                if !isLast {
                    Rectangle()
                        .fill(segment.accentColor.opacity(0.9))
                        .frame(width: 3, height: max(40, segment.stepCard == nil ? 36 : (segment.stepCard?.serviceInfo == nil ? 120 : 188)))
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    if let icon = segment.icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 24)
                    }

                    Text(segment.placeTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)

                    Spacer()

                    if let stopCountText = segment.stopCountText {
                        Text(stopCountText)
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }

                if let card = segment.stepCard {
                    RouteInstructionCard(card: card)
                }

                if let durationBadge = segment.durationBadge {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                        Text(durationBadge)
                            .font(DS.Font.mono.weight(.bold))
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 33)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }
}

private struct RouteInstructionCard: View {
    let card: RouteItineraryStepCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let lineBadge = card.lineBadge {
                    Text(lineBadge)
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundStyle(TransitLinePalette.foreground(for: lineBadge))
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(TransitLinePalette.fill(for: lineBadge))
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Spacer(minLength: 0)
            }

            Text(card.subtitle)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(DS.Color.community)

            if let serviceInfo = card.serviceInfo {
                RouteTransitServiceCard(info: serviceInfo)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card.style == .mint ? DS.Color.paper2.opacity(0.8) : DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RouteTransitServiceCard: View {
    let info: RouteTransitServiceInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(info.lineCode)
                .font(DS.Font.mono.weight(.bold))
                .foregroundStyle(TransitLinePalette.foreground(for: info.lineCode))
                .frame(width: 29, height: 28)
                .background(TransitLinePalette.fill(for: info.lineCode))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.statusTitle)
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.statusMajor)
                Text(info.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.ink)
                Text("Prochain passage")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.top, 4)
                Text(info.waitTime)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 4)
        }
        .padding(10)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RouteItinerarySegment {
    let timeText: String
    let placeTitle: String
    let icon: String?
    let accentColor: Color
    let stepCard: RouteItineraryStepCard?
    let durationBadge: String?
    var stopCountText: String? = nil
}

private struct RouteItineraryStepCard {
    enum CardStyle {
        case mint
        case white
    }

    let style: CardStyle
    let title: String
    let subtitle: String
    let lineBadge: String?
    let serviceInfo: RouteTransitServiceInfo?
}

private struct RouteTransitServiceInfo {
    let lineCode: String
    let statusTitle: String
    let detail: String
    let waitTime: String
}

private struct RouteARInstruction {
    let primaryText: String
    let secondaryText: String?
    let distanceText: String
}

private extension Int {
    func clockString(from startDate: Date) -> String {
        let date = startDate.addingTimeInterval(TimeInterval(self * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

private extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

private extension MKPolyline {
    var firstCoordinate: CLLocationCoordinate2D? {
        guard pointCount > 0 else { return nil }
        return points()[0].coordinate
    }
}

private extension CLLocationDistance {
    var distanceLabel: String {
        if self >= 1000 {
            return String(format: "%.1f km", self / 1000)
        }
        return "\(max(1, Int(rounded()))) m"
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
