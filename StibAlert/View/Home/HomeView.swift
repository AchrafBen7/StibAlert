import SwiftUI
import MapKit
import Combine
import AVFoundation

struct HomeView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var stibi: StibiCenter
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
    @State private var selectedSignalementPreview: SignalementDTO? = nil
    @State private var lastFetchedAt: Date? = nil
    @State private var currentRoute: MKRoute? = nil
    @State private var destinationCoord: CLLocationCoordinate2D? = nil
    @State private var routeOptions: [HomeRouteOption] = []
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
    @State private var isLoadingTransportOverview = false
    @State private var stibiBrief: AssistantBriefDTO?
    @State private var isLoadingStibiBrief = false
    @State private var selectedAlternativeDetail: TransportAlternativeDTO?
    @State private var selectedMapStopSummary: TransportStopSummaryDTO?
    @State private var selectedMapStopDetail: TransportStopDTO?
    @State private var isLoadingMapStopDetail = false
    @State private var eventImpacts: [TransportEventImpactDTO] = []
    @State private var selectedEventImpact: TransportEventImpactDTO?
    @State private var showVilloStations = true
    @State private var showEventImpacts = true
    @State private var selectedVilloStation: VilloStation?
    @State private var problemFilter: ReportProblemType? = nil
    @State private var cameraLatitudeDelta: Double = 0.04
    @State private var showReportAuthGate = false
    @State private var guestGateReason: GuestAuthReason = .report
    @State private var hasBootstrappedHomeData = false
    @State private var homeRefreshTask: Task<Void, Never>? = nil
    @State private var lastHomeRefreshAt: Date? = nil
    @State private var lastRefreshCoordinate: CLLocationCoordinate2D? = nil
    @State private var hasAutoCenteredOnUser = false
    @State private var isFollowingUser = true
    @State private var suppressNextCameraInteraction = false
    @State private var cameraCenterCoordinate = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
    @State private var catalogMapStops: [NearbyStop] = []
    @State private var mapStopsTask: Task<Void, Never>? = nil

    private struct LiveSignalPoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let typeProbleme: String
        let source: String?
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
                typeProbleme: s.typeProbleme,
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
        return numbers
    }

    private var visibleLineShapes: [LineShape] {
        guard cameraLatitudeDelta <= 0.08 else { return [] }
        return lineShapesLoader.shapes(matchingNumbers: visibleLineNumbers)
    }

    private var mapVehicles: [TransportVehicleDTO] {
        guard cameraLatitudeDelta <= 0.12 else { return [] }
        return vehicleTracker.vehicles.filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var mapStops: [TransportStopSummaryDTO] {
        guard cameraLatitudeDelta <= 0.12 else { return [] }

        let catalogStops = catalogMapStops.compactMap { stop -> TransportStopSummaryDTO? in
            guard let coordinate = stop.coordinate else { return nil }
            guard let backendId = stop.backendId else { return nil }
            return TransportStopSummaryDTO(
                id: backendId,
                stopId: nil,
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

        return merged
    }

    private var mapVilloStations: [VilloStation] {
        guard showVilloStations, cameraLatitudeDelta <= 0.06 else { return [] }
        return VilloStationService.nearbyStations(
            around: locationManager.displayCoordinate,
            radiusMeters: 2200,
            limit: 80
        ).map(\.station)
    }

    private var mapEventImpacts: [TransportEventImpactDTO] {
        guard showEventImpacts, cameraLatitudeDelta <= 0.18 else { return [] }
        return eventImpacts
            .filter(isRelevantMapEvent(_:))
            .filter { $0.latitude != nil && $0.longitude != nil }
    }

    private var highlightedEventCount: Int {
        eventImpacts.filter(isRelevantMapEvent(_:)).count
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
        .overlay(alignment: .bottom) {
            if nav.showReportSheet {
                ReportSheetView(
                    isShowing: $nav.showReportSheet,
                    userLatitude: locationManager.userCoordinate?.latitude,
                    userLongitude: locationManager.userCoordinate?.longitude
                )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            }
        }
        .overlay(alignment: .top) {
            if nav.currentPage == .home, !nav.showReportSheet, !nav.showSideMenu {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        HomeEditorialSearchField(query: $searchQuery)

                        Button {
                            withAnimation(transitionSpring) {
                                showLegend = true
                            }
                        } label: {
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

                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 10) {
                            HomeEditorialActionChip(
                                icon: "location.viewfinder",
                                title: "Autour de moi",
                                count: nil,
                                isActive: locationManager.userCoordinate != nil
                            ) {
                                aroundMe()
                            }

                            HomeEditorialActionChip(
                                icon: "star",
                                title: "Favoris",
                                count: favoriteLineCount,
                                isActive: favoriteLineCount > 0
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    nav.currentPage = .favorites
                                }
                            }

                            HomeEditorialActionChip(
                                icon: "exclamationmark.triangle",
                                title: "Perturbations",
                                count: totalActiveSignalementsCount,
                                isActive: totalActiveSignalementsCount > 0
                            ) {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                    nav.currentPage = .reports
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                    }

                    if !searchSuggestions.isEmpty {
                        SearchSuggestionsDropdown(
                            suggestions: searchSuggestions,
                            isRouting: isRouting,
                            onSelect: { item in
                                Task { await buildRoute(to: item) }
                            }
                        )
                        .padding(.horizontal, 18)
                    }
                }
                .padding(.top, 68)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .overlay(alignment: .bottom) {
            if let preview = selectedSignalementPreview,
               nav.currentPage == .home,
               !nav.showReportSheet,
               !nav.showSideMenu,
               !showLegend,
               routeOptions.isEmpty {
                SignalementMiniCard(
                    signalement: preview,
                    arretName: arretName(for: preview),
                    onClose: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            selectedSignalementPreview = nil
                        }
                    },
                    onStillBlocked: {
                        await reportStillBlocked(id: preview.id)
                    },
                    onResolved: {
                        await reportResolved(id: preview.id)
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 154)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(7)
            }
        }
        .overlay(alignment: .bottom) {
            if nav.currentPage == .home, !nav.showReportSheet, !nav.showSideMenu, routeOptions.isEmpty, selectedSignalementPreview == nil {
                HomePulseBar(
                    totalActive: totalActiveSignalementsCount,
                    eventCount: highlightedEventCount,
                    onOpenReports: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            nav.currentPage = .reports
                        }
                    }
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 92)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
            }
        }
        .overlay(alignment: .bottom) {
            if !nav.showReportSheet, routeOptions.isEmpty, selectedARRoute == nil, selectedRouteDetail == nil {
                AppTabBar(selection: Binding(
                    get: { AppTab.from(page: nav.currentPage) },
                    set: { newTab in
                        withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                            nav.currentPage = newTab.page
                        }
                    }
                ))
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(8)
            }
        }
        .guestAuthGate(
            isPresented: $showReportAuthGate,
            reason: guestGateReason,
            onSignIn: { nav.showAuthFlow = true },
            onSignUp: { nav.showAuthFlow = true }
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
        .sheet(item: $selectedVilloStation) { station in
            HomeVilloStationSheet(station: station)
                .presentationDetents([.height(260), .medium])
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
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: nav.currentPage == .home)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            stibi.setCurrentScreen("home")
            locationManager.start()
            realtimeSignalements.connect()
            vehicleTracker.start(lines: visibleLineNumbers)
        }
        .onDisappear {
            realtimeSignalements.disconnect()
            vehicleTracker.stop()
        }
        .onChange(of: visibleLineNumbers) { _, newLines in
            vehicleTracker.updateLines(newLines)
            syncFavoritesToWidget(newLines)
        }
        .task { await loadRemoteSignalements() }
        .task { await loadEventImpacts() }
        .task { lineShapesLoader.loadIfNeeded() }
        .task { await refreshCatalogMapStops(force: true) }
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
                }
            }
        }
        .onReceive(realtimeSignalements.$latestSignalement.compactMap { $0 }) { signalement in
            mergeIncomingSignalement(signalement)
        }
        .onChange(of: nav.currentPage) { _, newValue in
            switch newValue {
            case .home: stibi.setCurrentScreen("home")
            case .signalements: stibi.setCurrentScreen("signalements")
            case .reports: stibi.setCurrentScreen("reports")
            case .favorites:   stibi.setCurrentScreen("favorites")
            case .profile:     stibi.setCurrentScreen("profile")
            case .profileMain: stibi.setCurrentScreen("profile_main")
            }
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
            Task { await refreshCatalogMapStops(force: true) }
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
            MapCircle(center: locationManager.displayCoordinate, radius: 400)
                .foregroundStyle(AppTheme.Palette.screen.opacity(0.10))
                .stroke(AppTheme.Palette.info, lineWidth: 1)
            Annotation("", coordinate: locationManager.displayCoordinate, anchor: .center) {
                UserLocationDotView(heading: locationManager.heading)
            }
            if let route = currentRoute {
                MapPolyline(route.polyline)
                    .stroke(AppTheme.Palette.info, style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
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
            ForEach(mapClusters) { cluster in
                Annotation("", coordinate: cluster.coordinate, anchor: .bottom) {
                    Button { handleClusterTap(cluster) } label: {
                        if cluster.count > 1 {
                            MapClusterMarker(count: cluster.count, dominantType: cluster.dominantType)
                        } else {
                            LiveSignalMarker(problemType: cluster.dominantType)
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
            ForEach(mapVehicles) { vehicle in
                if let lat = vehicle.latitude, let lng = vehicle.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .center) {
                        VehicleMarker(vehicle: vehicle)
                    }
                }
            }
            ForEach(mapStops) { stop in
                if let latitude = stop.latitude, let longitude = stop.longitude {
                    Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                        Button {
                            openStopDetail(for: stop)
                        } label: {
                            HomeStopMarker(stop: stop)
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
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .allowsHitTesting(searchSuggestions.isEmpty)
        .onMapCameraChange(frequency: .onEnd) { ctx in
            cameraLatitudeDelta = ctx.region.span.latitudeDelta
            cameraCenterCoordinate = ctx.region.center
            if suppressNextCameraInteraction {
                suppressNextCameraInteraction = false
            } else {
                isFollowingUser = false
            }
            scheduleCatalogMapStopsRefresh()
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
        VStack {
            Spacer()

            HStack {
                Spacer()

                VStack(spacing: 12) {
                    HelpFloatingButton {
                        withAnimation(transitionSpring) {
                            showLegend = true
                        }
                    }

                    LocationFloatingButton {
                        recenterOnUser()
                    }
                }
            }
            .padding(.horizontal, 20)
            .padding(.bottom, 150)
            .zIndex(2)
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

        if let stop = selectedMapStopSummary {
            ArretDetailPage(
                stopSummary: stop,
                stopDetail: selectedMapStopDetail,
                isLoading: isLoadingMapStopDetail,
                nearbyStops: nearbyStops(for: stop, detail: selectedMapStopDetail),
                nearbyVilloStations: stopVilloStations(for: stop, detail: selectedMapStopDetail),
                onDismiss: {
                    selectedMapStopSummary = nil
                    selectedMapStopDetail = nil
                    isLoadingMapStopDetail = false
                },
                onOpenLine: { line in
                    selectedMapStopSummary = nil
                    selectedMapStopDetail = nil
                    isLoadingMapStopDetail = false
                    nav.pendingLineFocus = line
                    nav.currentPage = .signalements
                },
                onOpenStop: { summary in
                    openStopDetail(for: summary)
                },
                onReport: {
                    openReportSheet(for: stop)
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .zIndex(10)
        }

        if !routeOptions.isEmpty {
            RouteRecommendationsSheet(
                options: routeOptions,
                selectedRouteID: $selectedRouteID,
                isExpanded: $isRouteSheetExpanded,
                onSelect: { option in
                    applyRouteOption(option)
                    selectedRouteDetail = option
                },
                onClose: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        routeOptions = []
                        selectedRouteID = nil
                        currentRoute = nil
                        destinationCoord = nil
                        isRouteSheetExpanded = false
                        selectedRouteDetail = nil
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(8)
        }

        if let selectedRouteDetail {
            RouteItineraryDetailsView(
                option: selectedRouteDetail,
                onBack: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        self.selectedRouteDetail = nil
                    }
                },
                onClose: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        self.selectedRouteDetail = nil
                        routeOptions = []
                        selectedRouteID = nil
                        currentRoute = nil
                        destinationCoord = nil
                        isRouteSheetExpanded = false
                    }
                },
                onShowMap: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        self.selectedRouteDetail = nil
                    }
                },
                onStartAR: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        selectedARRoute = selectedRouteDetail
                    }
                }
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
            .zIndex(9)
        }

        if let selectedARRoute {
            RouteARNavigationView(
                option: selectedARRoute,
                onClose: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        self.selectedARRoute = nil
                    }
                }
            )
            .transition(.opacity)
            .zIndex(11)
        }

        if nav.currentPage != .home {
            pageOverlay
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(6)
        }
    }

    private var currentCommuteBrief: AssistantBriefDTO? {
        guard let brief = stibi.brief, brief.type == "commute_brief" else { return nil }
        return brief
    }

    private var homeDashboardData: HomeDashboardData {
        HomeDecisionAdapter.makeDashboardData(
            transportOverview: transportOverview,
            remoteSignalements: remoteSignalements,
            stibiBrief: currentCommuteBrief,
            stibiContext: stibi.context
        )
    }

    private func syncFavoritesToWidget(_ lines: Set<String>) {
        if let shared = UserDefaults(suiteName: AppConfig.appGroupID) {
            shared.set(lines.sorted(), forKey: "favoriteLines")
        }
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
            if let stibiBrief {
                let enriched = enrichHomeBriefWithCommunity(stibiBrief)
                self.stibiBrief = enriched
                stibi.consume(enriched)
            }
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
    private func openStopDetail(for stop: TransportStopSummaryDTO) {
        selectedMapStopSummary = stop
        selectedMapStopDetail = nil
        isLoadingMapStopDetail = true

        Task {
            do {
                let detail = try await TransportService.stop(id: stop.id)
                await MainActor.run {
                    if selectedMapStopSummary?.id == stop.id {
                        selectedMapStopDetail = detail
                    }
                }
            } catch {
                print("Transport stop detail failed: \(error.localizedDescription)")
            }

            await MainActor.run {
                if selectedMapStopSummary?.id == stop.id {
                    isLoadingMapStopDetail = false
                }
            }
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
                stopId: nil,
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
            nav.pendingMapStopFocusBackendId = nil
        } catch {
            print("Pending map stop focus failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func openReportSheet(for stop: TransportStopSummaryDTO) {
        selectedMapStopSummary = nil
        selectedMapStopDetail = nil
        isLoadingMapStopDetail = false

        guard !session.isGuest else {
            guestGateReason = .report
            showReportAuthGate = true
            return
        }

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

    private func reportStillBlocked(id: String) async {
        guard !session.isGuest else {
            guestGateReason = .confirm
            showReportAuthGate = true
            return
        }
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
           lastRefreshCoordinate.flatMap({ centerDistanceMeters(from: $0, to: cameraCenterCoordinate) < max(220, radius * 0.22) }) == true {
            return
        }

        do {
            let nearby = try await NearbyStopService.fetchNearby(
                lat: cameraCenterCoordinate.latitude,
                lng: cameraCenterCoordinate.longitude,
                radius: radius
            )
            catalogMapStops = nearby
            lastRefreshCoordinate = cameraCenterCoordinate
        } catch {
            print("Home map nearby stops failed: \(error.localizedDescription)")
        }
    }

    private func centerDistanceMeters(from lhs: CLLocationCoordinate2D, to rhs: CLLocationCoordinate2D) -> Double {
        let start = CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
        let end = CLLocation(latitude: rhs.latitude, longitude: rhs.longitude)
        return start.distance(from: end)
    }

    private func reportResolved(id: String) async {
        guard !session.isGuest else {
            guestGateReason = .confirm
            showReportAuthGate = true
            return
        }
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
    private func loadStibiBrief(lat: Double? = nil, lng: Double? = nil) async {
        guard AppConfig.isBackendEnabled else { return }
        guard session.isSignedIn else {
            stibiBrief = nil
            return
        }
        guard !isLoadingStibiBrief else { return }
        isLoadingStibiBrief = true
        defer { isLoadingStibiBrief = false }

        do {
            let brief = try await AssistantService.homeBrief(lat: lat, lng: lng)
            let enriched = enrichHomeBriefWithCommunity(brief)
            stibiBrief = enriched
            stibi.consume(enriched)
        } catch {
            print("Stibi home brief failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func refreshHomeSurface(reason: String, force: Bool = false) async {
        guard AppConfig.isBackendEnabled else { return }

        let now = Date()
        if !force, let lastHomeRefreshAt, now.timeIntervalSince(lastHomeRefreshAt) < 12 {
            return
        }

        homeRefreshTask?.cancel()
        let lat = locationManager.userCoordinate?.latitude
        let lng = locationManager.userCoordinate?.longitude

        homeRefreshTask = Task {
            await withTaskGroup(of: Void.self) { group in
                group.addTask { await loadTransportOverview(lat: lat, lng: lng) }
                if session.isSignedIn {
                    group.addTask { await loadStibiBrief(lat: lat, lng: lng) }
                }
            }
        }

        await homeRefreshTask?.value
        guard !Task.isCancelled else { return }
        lastHomeRefreshAt = Date()
    }

    @MainActor
    private func refreshHomeSurfaceForLocation(_ coord: CLLocationCoordinate2D) async {
        let movedEnough: Bool
        if let lastRefreshCoordinate {
            let previous = CLLocation(latitude: lastRefreshCoordinate.latitude, longitude: lastRefreshCoordinate.longitude)
            let current = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
            movedEnough = previous.distance(from: current) >= 250
        } else {
            movedEnough = true
        }

        guard movedEnough else { return }
        lastRefreshCoordinate = coord
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
        req.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
        let results = try? await MKLocalSearch(request: req).start()
        searchSuggestions = Array((results?.mapItems ?? []).prefix(5))
    }

    @MainActor
    private func buildRoute(to destination: MKMapItem) async {
        isRouting = true
        defer { isRouting = false }
        let source = MKMapItem(placemark: MKPlacemark(coordinate: locationManager.displayCoordinate))

        let transitOptions = await calculateRouteOptions(source: source, destination: destination, transportType: .transit)
        let anyOptions = transitOptions == nil
            ? await calculateRouteOptions(source: source, destination: destination, transportType: .any)
            : nil
        let walkingOptions = transitOptions == nil && anyOptions == nil
            ? await calculateRouteOptions(source: source, destination: destination, transportType: .walking)
            : nil

        if let options = transitOptions ?? anyOptions ?? walkingOptions {
            destinationCoord = destination.placemark.coordinate
            searchSuggestions = []
            searchQuery = destination.name ?? ""

            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                routeOptions = options
                selectedRouteID = options.first?.id
                isRouteSheetExpanded = false
            }

            if let first = options.first {
                applyRouteOption(first)
            }
        }
    }

    private func calculateRouteOptions(
        source: MKMapItem,
        destination: MKMapItem,
        transportType: MKDirectionsTransportType
    ) async -> [HomeRouteOption]? {
        let req = MKDirections.Request()
        req.source = source
        req.destination = destination
        req.transportType = transportType
        req.requestsAlternateRoutes = true

        let dirs = MKDirections(request: req)
        guard let response = try? await dirs.calculate(), !response.routes.isEmpty else {
            return nil
        }

        return response.routes.prefix(3).enumerated().map { index, route in
            HomeRouteOption.from(
                route: route,
                index: index,
                originName: "Votre position",
                destinationName: destination.name ?? "Destination"
            )
        }
    }

    private func applyRouteOption(_ option: HomeRouteOption) {
        currentRoute = option.route
        selectedRouteID = option.id

        let rect = option.route.polyline.boundingMapRect
        withAnimation(.easeInOut(duration: 0.8)) {
            mapPosition = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
        }
    }

    @ViewBuilder
    private var pageOverlay: some View {
        ZStack {
            Color((nav.currentPage == .signalements || nav.currentPage == .reports || nav.currentPage == .favorites || nav.currentPage == .profile || nav.currentPage == .profileMain) ? "#1B1B1B" : "#0B111E").ignoresSafeArea()

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

    private func enrichHomeBriefWithCommunity(_ brief: AssistantBriefDTO) -> AssistantBriefDTO {
        let confirmationCount = remoteSignalements.reduce(0) { partialResult, signalement in
            partialResult + (signalement.community?.confirmations ?? 0)
        }
        let stillBlockedCount = remoteSignalements.reduce(0) { partialResult, signalement in
            partialResult + (signalement.community?.stillBlocked ?? 0)
        }

        guard confirmationCount > 0 || stillBlockedCount > 0 else { return brief }

        let terrainNote: String
        if stillBlockedCount > 0 {
            terrainNote = "\(confirmationCount + stillBlockedCount) retours terrain confirment encore des zones bloquées."
        } else {
            terrainNote = "\(confirmationCount) confirmation(s) terrain récentes soutiennent cette lecture."
        }

        guard !brief.message.localizedCaseInsensitiveContains(terrainNote) else { return brief }

        return AssistantBriefDTO(
            assistant: brief.assistant,
            context: brief.context,
            type: brief.type,
            priority: brief.priority,
            severity: brief.severity,
            confidence: brief.confidence,
            title: brief.title,
            message: "\(brief.message) \(terrainNote)",
            shortMessage: brief.shortMessage,
            actions: brief.actions,
            source: brief.source,
            assistantContext: brief.assistantContext,
            supporting: brief.supporting
        )
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
            onNavigate(.profileMain)
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

private struct HomeEditorialSearchField: View {
    @Binding var query: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.inkSoft)

            TextField("", text: $query, prompt: Text("Où vas-tu ?").foregroundStyle(DS.Color.inkMute))
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
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

private struct HomePulseBar: View {
    let totalActive: Int
    let eventCount: Int
    let onOpenReports: () -> Void

    var body: some View {
        Button(action: onOpenReports) {
            HStack(spacing: 12) {
                Circle()
                    .fill(totalActive > 0 ? DS.Color.statusMajor : DS.Color.statusMinor)
                    .frame(width: 12, height: 12)

                VStack(alignment: .leading, spacing: 2) {
                    Text(totalActive == 0 ? "0 lignes perturbées" : "\(totalActive) signalements actifs")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                    Text("\(eventCount) événements ce soir")
                        .font(DS.Font.monoSmall)
                        .tracking(1.2)
                        .textCase(.uppercase)
                        .foregroundStyle(DS.Color.inkMute)
                }

                Spacer()

                Image(systemName: "chevron.up")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 16)
            .frame(height: 60)
            .background(DS.Color.paper.opacity(0.98))
            .overlay(alignment: .topLeading) {
                Rectangle()
                    .fill(DS.Color.ink)
                    .frame(width: 64, height: 3)
                    .padding(.leading, 18)
                    .padding(.top, 8)
            }
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .shadow(DS.Shadow.overlay)
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
        VStack(spacing: 0) {
            ForEach(suggestions, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 18))
                            .foregroundStyle(DS.Color.primary)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name ?? "Lieu")
                                .font(DS.Font.bodyBold)
                                .foregroundStyle(DS.Color.ink)
                            Text(item.placemark.title ?? "")
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.inkMute)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isRouting {
                            ProgressView()
                                .tint(DS.Color.ink)
                                .scaleEffect(0.85)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if item != suggestions.last {
                    Divider().overlay(DS.Color.ink.opacity(0.08))
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
}

private struct LocationFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.paper.opacity(0.96))
                .frame(width: 42, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .rotationEffect(.degrees(18))
                )
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Recentrer la carte")
        .accessibilityHint("Replace la carte sur votre position")
    }
}

private struct HelpFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .fill(DS.Color.paper.opacity(0.96))
                .frame(width: 42, height: 44)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                )
                .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Aide de la carte")
        .accessibilityHint("Explique les icônes et statuts affichés")
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

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 5, style: .continuous)
                .fill(Color(hex: "#0055A4"))
                .frame(width: 28, height: 20)
                .shadow(color: .black.opacity(0.4), radius: 2, x: 0, y: 1)
            Text("STIB")
                .font(.system(size: 8, weight: .black))
                .foregroundStyle(.white)
                .kerning(0.5)
        }
        .accessibilityElement()
        .accessibilityLabel("Alerte officielle STIB — \(problemType)")
        .accessibilityHint("Ouvre le détail de la perturbation officielle")
    }
}

private struct HomeStopMarker: View {
    let stop: TransportStopSummaryDTO

    private var badgeText: String {
        let labels = stop.lines.prefix(2)
        return labels.isEmpty ? "STOP" : labels.joined(separator: " · ")
    }

    private var accentColor: Color {
        stop.lines.first.map { line in
            switch line {
            case "1", "2", "5", "6":
                return Color(hex: "#4D8DFF")
            default:
                return Color(hex: "#F8E2B3")
            }
        } ?? Color(hex: "#F8E2B3")
    }

    var body: some View {
        VStack(spacing: 4) {
            Text(badgeText)
                .font(.custom("Montserrat-SemiBold", size: 10))
                .foregroundStyle(.black.opacity(0.85))
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(accentColor)
                .clipShape(Capsule())

            Image(systemName: "tram.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 28, height: 28)
                .background(Color(hex: "#182131"))
                .clipShape(Circle())
                .overlay(
                    Circle()
                        .stroke(accentColor.opacity(0.95), lineWidth: 2)
                )
                .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
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
            ZStack(alignment: .topTrailing) {
                Circle()
                    .fill(fill)
                    .frame(width: 28, height: 28)
                    .overlay(
                        Circle().stroke(stroke, lineWidth: 2)
                    )

                Image(systemName: "bicycle")
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(.black)

                Text(bikeBadgeText)
                    .font(.custom("Montserrat-SemiBold", size: 9))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .offset(x: 8, y: -6)
            }

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
        VStack(spacing: 4) {
            ZStack {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(backgroundTint)
                    .frame(width: 42, height: 42)
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.white.opacity(0.28), lineWidth: 1)
                    )

                Image(systemName: "calendar.badge.exclamationmark")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textPrimary)
            }

            Text(compactLabel)
                .font(.custom("Montserrat-SemiBold", size: 10))
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .padding(.horizontal, 8)
                .frame(height: 22)
                .background(AppTheme.Palette.screenElevated.opacity(0.96))
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.Palette.border, lineWidth: 1)
                )
        }
        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
        .accessibilityLabel("Événement \(event.title)")
    }

    private var compactLabel: String {
        if let first = event.impactedLines.first, !first.isEmpty {
            return "Ligne \(first)"
        }
        return event.phaseLabel ?? "Event"
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

private struct HomeVilloStationSheet: View {
    let station: VilloStation

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(station.displayName)
                        .font(.custom("DelaGothicOne-Regular", size: 20))
                        .foregroundStyle(.white)

                    Text(station.address)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.white.opacity(0.72))
                        .fixedSize(horizontal: false, vertical: true)

                    Text(station.occupancyStateLabel)
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(statusAccent)
                }

                Spacer()

                Text(station.statusLabel)
                    .font(.custom("Montserrat-SemiBold", size: 11))
                    .foregroundStyle(station.isOperational ? Color.black : .white)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(statusAccent)
                    .clipShape(Capsule())
            }

            HStack(spacing: 10) {
                villoMetricPill(title: "Vélos", value: "\(station.availableBikes)")
                villoMetricPill(title: "Places", value: "\(station.availableBikeStands)")
                villoMetricPill(title: "Bornes", value: "\(station.bikeStands)")
            }

            if let lastUpdate = station.lastUpdate {
                let date = Date(timeIntervalSince1970: TimeInterval(lastUpdate) / 1000)
                Text("Mis à jour \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.62))
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding(20)
        .presentationBackground(Color(hex: "#111827"))
    }

    private var statusAccent: Color {
        if !station.isOperational { return Color.white.opacity(0.12) }
        if station.availableBikes == 0 { return Color(hex: "#FF7A7A") }
        if station.availableBikeStands == 0 { return Color(hex: "#7DB6FF") }
        if station.availableBikes <= 3 { return Color(hex: "#FFB15A") }
        return Color(hex: "#57E3B6")
    }

    private func villoMetricPill(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.custom("Montserrat-SemiBold", size: 10))
                .textCase(.uppercase)
                .foregroundStyle(.white.opacity(0.52))
            Text(value)
                .font(.custom("DelaGothicOne-Regular", size: 16))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}

private struct HomeEventImpactSheet: View {
    let event: TransportEventImpactDTO
    let onOpenLine: (String) -> Void
    let onOpenStop: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Capsule()
                .fill(AppTheme.Palette.borderStrong)
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)
                .padding(.top, 8)

            VStack(alignment: .leading, spacing: 8) {
                Text(event.title)
                    .font(AppTheme.Fonts.clash(22))
                    .foregroundStyle(AppTheme.Palette.textPrimary)

                Text(event.venue ?? event.zoneLabel ?? "Bruxelles")
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textSecondary)

                HStack(spacing: 8) {
                    badge(event.phaseLabel ?? "À venir", tint: phaseTint)
                    if let impact = event.impactLevel {
                        badge(impactLabel(impact), tint: impactTint(impact))
                    }
                }
            }

            if let notes = event.notesFr, !notes.isEmpty {
                Text(notes)
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textSecondary)
            }

            if !event.impactedLines.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Lignes potentiellement affectées")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textMuted)

                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 8)], spacing: 8) {
                        ForEach(event.impactedLines, id: \.self) { line in
                            Button {
                                onOpenLine(line)
                            } label: {
                                HStack(spacing: 6) {
                                    Text("Ligne \(line)")
                                        .font(AppTheme.Fonts.captionStrong)
                                    Image(systemName: "arrow.right")
                                        .font(.system(size: 10, weight: .bold))
                                }
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(height: 32)
                                .frame(maxWidth: .infinity)
                                .background(AppTheme.Palette.surfaceElevated)
                                .clipShape(Capsule())
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }

            if let impactedStops = event.impactedStopDetails, !impactedStops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Arrêts / zones")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textMuted)

                    ForEach(impactedStops) { stop in
                        if let stopId = stop.id {
                            Button {
                                onOpenStop(stopId)
                            } label: {
                                HStack {
                                    Text(stop.name)
                                        .font(AppTheme.Fonts.bodyStrong)
                                        .foregroundStyle(AppTheme.Palette.textPrimary)
                                    Spacer()
                                    Image(systemName: "location.viewfinder")
                                        .font(.system(size: 12, weight: .semibold))
                                        .foregroundStyle(AppTheme.Palette.textMuted)
                                }
                                .padding(12)
                                .background(AppTheme.Palette.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                            }
                            .buttonStyle(.plain)
                        } else {
                            Text(stop.name)
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(AppTheme.Palette.textSecondary)
                        }
                    }
                }
            } else if !event.impactedStops.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Arrêts / zones")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textMuted)

                    Text(event.impactedStops.joined(separator: " • "))
                        .font(AppTheme.Fonts.body)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 20)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.screen)
    }

    private func badge(_ title: String, tint: Color) -> some View {
        Text(title)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(tint)
            .clipShape(Capsule())
    }

    private var phaseTint: Color {
        switch event.phase {
        case "live":
            return Color(hex: "#FFB89A")
        case "upcoming":
            return Color(hex: "#F4D6A0")
        default:
            return AppTheme.Palette.surfaceElevated
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
            return Color(hex: "#FF9A7A")
        case "moderate":
            return Color(hex: "#F1C46C")
        default:
            return Color(hex: "#B8E28A")
        }
    }
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

                if !effectiveStop.lines.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Lignes")
                            .font(.custom("Montserrat-SemiBold", size: 12))
                            .foregroundStyle(Color.white.opacity(0.72))

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(effectiveStop.lines, id: \.self) { line in
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

                    if let stopDetail, !stopDetail.nextDepartures.isEmpty {
                        ForEach(stopDetail.nextDepartures.prefix(4)) { departure in
                            HStack(spacing: 10) {
                                Text(departure.line)
                                    .font(.custom("Montserrat-SemiBold", size: 13))
                                    .foregroundStyle(.black)
                                    .frame(minWidth: 36, minHeight: 28)
                                    .background(Color(hex: "#B5CFF8"))
                                    .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(departure.destination ?? "Direction en cours")
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(.white)
                                        .lineLimit(2)
                                    Text("Dans \(departure.minutes) min")
                                        .font(.custom("Montserrat-Regular", size: 12))
                                        .foregroundStyle(.white.opacity(0.72))
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

struct MorningCommuteStatusCard: View {
    let brief: AssistantBriefDTO
    let onOpenStibi: () -> Void
    let onPrimaryAction: () -> Void

    private var glowColor: Color {
        AssistantViewAdapters.glowColor(for: brief.assistant.visualState)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                Circle()
                    .fill(glowColor.opacity(0.2))
                    .frame(width: 34, height: 34)
                    .overlay(
                        Circle()
                            .fill(glowColor)
                            .frame(width: 12, height: 12)
                    )

                VStack(alignment: .leading, spacing: 2) {
                    Text("Stibi • Trajet du matin")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textSecondary)

                    Text(brief.title)
                        .font(AppTheme.Fonts.title3)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                }

                Spacer()

                if let decision = brief.supporting?.commuteDecision {
                    Text(localizedDecision(decision))
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .padding(.horizontal, 9)
                        .padding(.vertical, 6)
                        .background(glowColor)
                        .clipShape(Capsule())
                }
            }

            Text(brief.message)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textSecondary)
                .fixedSize(horizontal: false, vertical: true)

            if let departureTime = brief.supporting?.departureTime, !departureTime.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.info)
                    Text("Départ habituel \(departureTime)")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.info)
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.05))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }

            HStack(spacing: 10) {
                Button(action: onPrimaryAction) {
                    Text(brief.actions.first?.label ?? "Agir")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.ButtonHeight.secondary)
                        .background(glowColor)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)

                Button(action: onOpenStibi) {
                    Text("Ouvrir Stibi")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .frame(maxWidth: .infinity)
                        .frame(height: AppTheme.ButtonHeight.secondary)
                        .background(AppTheme.Palette.surfaceMuted)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [glowColor.opacity(0.14), AppTheme.Palette.screenElevated.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(glowColor.opacity(0.22), lineWidth: 1)
        )
    }

    private func localizedDecision(_ decision: String) -> String {
        switch decision {
        case "leave_now": return "Pars"
        case "prepare": return "Prépare"
        case "wait": return "Attends"
        case "detour": return "Détour"
        default: return "Suivi"
        }
    }
}

private struct MapLegendOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text("Que signifient les icônes ?")
                    .font(AppTheme.Fonts.title2)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .padding(.horizontal, 28)
                    .padding(.top, 20)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 18) {
                    legendSectionTitle("Signalements & réseau")
                    legendRow(marker: AnyView(LiveSignalMarker(problemType: "Accident")), text: "Signalement critique confirmé")
                    legendRow(marker: AnyView(LiveSignalMarker(problemType: "Retard")), text: "Signalement léger ou retard")
                    legendRow(marker: AnyView(OfficialSignalMarker(problemType: "Information STIB")), text: "Alerte officielle STIB")
                    legendRow(marker: AnyView(HomeStopMarker(stop: demoStop)), text: "Arrêt STIB tapable avec détails")

                    Divider()
                        .overlay(Color.white.opacity(0.12))

                    legendSectionTitle("Villo!")
                    legendRow(marker: AnyView(VilloMapMarker(station: demoVilloHealthy)), text: "Station disponible")
                    legendRow(marker: AnyView(VilloMapMarker(station: demoVilloLow)), text: "Peu de vélos disponibles")
                    legendRow(marker: AnyView(VilloMapMarker(station: demoVilloEmpty)), text: "Aucun vélo disponible")
                    legendRow(marker: AnyView(VilloMapMarker(station: demoVilloFull)), text: "Plus de places libres")
                    legendRow(marker: AnyView(VilloMapMarker(station: demoVilloClosed)), text: "Station fermée")

                    legendSectionTitle("Événements")
                    legendRow(marker: AnyView(EventMapMarker(event: demoEventHigh)), text: "Événement à forte affluence probable")
                    legendRow(marker: AnyView(EventMapMarker(event: demoEventModerate)), text: "Événement à affluence modérée")
                }
                .padding(.horizontal, 28)

                Button("Je comprends", action: onDismiss)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.ButtonHeight.primary)
                    .background(AppTheme.Palette.screen)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    .padding(.horizontal, 18)
                    .padding(.top, 30)
                    .padding(.bottom, 20)
            }
            .frame(width: 357)
            .background(AppTheme.Palette.brand)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
    }

    private func legendSectionTitle(_ title: String) -> some View {
        Text(title)
            .font(.custom("Montserrat-SemiBold", size: 11))
            .textCase(.uppercase)
            .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.55))
    }

    private func legendRow(marker: AnyView, text: String) -> some View {
        HStack(spacing: 12) {
            marker
                .frame(width: 34, height: 34)

            Text(text)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.88))

            Spacer()
        }
    }

    private var demoStop: TransportStopSummaryDTO {
        TransportStopSummaryDTO(
            id: "legend-stop",
            stopId: nil,
            name: "Arrêt démo",
            latitude: nil,
            longitude: nil,
            lines: ["3", "7"]
        )
    }

    private var demoVilloHealthy: VilloStation {
        VilloStation(
            number: 1,
            name: "001 - DEMO",
            address: "Bruxelles",
            position: .init(lat: 50.85, lng: 4.35),
            status: "OPEN",
            bikeStands: 24,
            availableBikes: 11,
            availableBikeStands: 13,
            banking: false,
            lastUpdate: nil
        )
    }

    private var demoVilloLow: VilloStation {
        VilloStation(
            number: 2,
            name: "002 - DEMO",
            address: "Bruxelles",
            position: .init(lat: 50.85, lng: 4.35),
            status: "OPEN",
            bikeStands: 24,
            availableBikes: 2,
            availableBikeStands: 14,
            banking: false,
            lastUpdate: nil
        )
    }

    private var demoVilloEmpty: VilloStation {
        VilloStation(
            number: 3,
            name: "003 - DEMO",
            address: "Bruxelles",
            position: .init(lat: 50.85, lng: 4.35),
            status: "OPEN",
            bikeStands: 24,
            availableBikes: 0,
            availableBikeStands: 19,
            banking: false,
            lastUpdate: nil
        )
    }

    private var demoVilloFull: VilloStation {
        VilloStation(
            number: 4,
            name: "004 - DEMO",
            address: "Bruxelles",
            position: .init(lat: 50.85, lng: 4.35),
            status: "OPEN",
            bikeStands: 24,
            availableBikes: 9,
            availableBikeStands: 0,
            banking: false,
            lastUpdate: nil
        )
    }

    private var demoVilloClosed: VilloStation {
        VilloStation(
            number: 5,
            name: "005 - DEMO",
            address: "Bruxelles",
            position: .init(lat: 50.85, lng: 4.35),
            status: "CLOSED",
            bikeStands: 24,
            availableBikes: 0,
            availableBikeStands: 0,
            banking: false,
            lastUpdate: nil
        )
    }

    private var demoEventHigh: TransportEventImpactDTO {
        .init(
            id: "demo-event-high",
            source: "events-bruxelles",
            title: "Concert ING Arena",
            category: "concert",
            venue: "ING Arena",
            zoneLabel: "Heysel",
            address: nil,
            latitude: 50.8987,
            longitude: 4.3403,
            startsAt: nil,
            endsAt: nil,
            phase: "upcoming",
            phaseLabel: "À venir",
            expectedAttendance: 12000,
            impactLevel: "high",
            notesFr: nil,
            impactedLines: ["6", "7", "51"],
            impactedStops: ["Heysel", "Roi Baudouin"],
            impactedStopDetails: nil,
            confidence: 0.84,
            soldOut: true,
            url: nil
        )
    }

    private var demoEventModerate: TransportEventImpactDTO {
        .init(
            id: "demo-event-moderate",
            source: "events-bruxelles",
            title: "Bozar",
            category: "expo",
            venue: "Bozar",
            zoneLabel: "Gare Centrale",
            address: nil,
            latitude: 50.8424,
            longitude: 4.3573,
            startsAt: nil,
            endsAt: nil,
            phase: "live",
            phaseLabel: "En cours",
            expectedAttendance: 2200,
            impactLevel: "moderate",
            notesFr: nil,
            impactedLines: ["1", "5", "92"],
            impactedStops: ["Gare Centrale", "Parc"],
            impactedStopDetails: nil,
            confidence: 0.62,
            soldOut: false,
            url: nil
        )
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
    @Binding var selectedRouteID: UUID?
    @Binding var isExpanded: Bool
    let onSelect: (HomeRouteOption) -> Void
    let onClose: () -> Void

    @GestureState private var dragOffset: CGFloat = 0

    private var recommended: HomeRouteOption? { options.first }
    private var others: [HomeRouteOption] { Array(options.dropFirst()) }

    var body: some View {
        GeometryReader { proxy in
            let expandedHeight = min(proxy.size.height * 0.78, 702)
            let collapsedHeight = min(proxy.size.height * 0.42, 330)
            let sheetHeight = isExpanded ? expandedHeight : collapsedHeight

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    Capsule()
                        .fill(.white)
                        .frame(width: 103, height: 3)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 12)
                        .padding(.bottom, 18)

                    if let recommended {
                        RouteOptionCard(
                            option: recommended,
                            isRecommended: true,
                            isSelected: selectedRouteID == recommended.id
                        ) {
                            onSelect(recommended)
                        }
                        .padding(.horizontal, 18)
                    }

                    HStack(alignment: .center) {
                        Text("Autres options")
                            .font(AppTheme.Fonts.bodyStrong)
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                        Spacer()
                        Text("\(others.count + 1) trajets disponible")
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                    }
                    .padding(.horizontal, 18)
                    .padding(.top, 18)

                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 12) {
                            ForEach(others) { option in
                                RouteOptionCard(
                                    option: option,
                                    isRecommended: false,
                                    isSelected: selectedRouteID == option.id
                                ) {
                                    onSelect(option)
                                }
                            }
                        }
                        .padding(.horizontal, 18)
                        .padding(.top, 12)
                        .padding(.bottom, 26)
                    }
                    .scrollDisabled(!isExpanded)
                }
                .frame(maxWidth: .infinity)
                .frame(height: sheetHeight, alignment: .top)
                .background(AppTheme.Palette.overlay.opacity(0.82))
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .opacity(isExpanded ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
                .offset(y: max(0, dragOffset))
                .gesture(
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
                )
            }
            .ignoresSafeArea()
        }
    }
}

private struct RouteOptionCard: View {
    let option: HomeRouteOption
    let isRecommended: Bool
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                RoundedRectangle(cornerRadius: 5, style: .continuous)
                    .fill(isSelected ? AppTheme.Palette.textPrimary : AppTheme.Palette.screen)
                    .frame(width: 42, height: 41)
                    .overlay(
                        Image(systemName: isSelected ? "point.topleft.down.curvedto.point.bottomright.up.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected ? AppTheme.Palette.textOnBrand : AppTheme.Palette.textPrimary)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(option.durationText)
                        .font(AppTheme.Fonts.title3)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)

                    HStack(spacing: 10) {
                        Text(option.transitSummary)
                        Text(option.walkingSummary)
                        Text(option.reliabilityText)
                            .foregroundStyle(AppTheme.Palette.success)
                    }
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                }

                Spacer()

                if isRecommended {
                    Text("Recommandé")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .padding(.horizontal, 10)
                        .frame(height: 20)
                        .background(AppTheme.Palette.screen)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 83)
            .background(AppTheme.Palette.brand)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

private struct HomeRouteOption: Identifiable {
    let id = UUID()
    let route: MKRoute
    let originName: String
    let destinationName: String
    let durationText: String
    let transitSummary: String
    let walkingSummary: String
    let reliabilityText: String

    static func from(route: MKRoute, index: Int, originName: String, destinationName: String) -> HomeRouteOption {
        let transitSteps = route.steps.filter { $0.transportType == .transit }
        let walkingMinutes = max(1, Int((route.steps.filter { $0.transportType == .walking }.map(\.distance).reduce(0, +) / 75).rounded()))
        let reliability = max(82, 95 - index * 6)

        return HomeRouteOption(
            route: route,
            originName: originName,
            destinationName: destinationName,
            durationText: "\(max(1, Int((route.expectedTravelTime / 60).rounded()))) min",
            transitSummary: "\(max(1, transitSteps.count)) tram",
            walkingSummary: "\(walkingMinutes) min à pied",
            reliabilityText: "\(reliability)% fiable"
        )
    }

    var detailSegments: [RouteItinerarySegment] {
        let totalMinutes = max(10, Int((route.expectedTravelTime / 60).rounded()))
        let walkingMinutes = max(1, Int(walkingSummary.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 4)
        let transitCount = max(1, Int(transitSummary.components(separatedBy: CharacterSet.decimalDigits.inverted).joined()) ?? 1)
        let startDate = Date()

        let firstWalkDuration = max(1, min(6, walkingMinutes / 2 == 0 ? walkingMinutes : walkingMinutes / 2))
        let secondWalkDuration = max(1, walkingMinutes - firstWalkDuration)
        let firstTransitDuration = max(4, (totalMinutes - walkingMinutes) / transitCount)
        let secondTransitDuration = max(4, totalMinutes - walkingMinutes - firstTransitDuration)
        let firstLine = transitCount > 1 ? "7" : "4"
        let secondLine = transitCount > 1 ? "58" : "3"

        let schedule = [0, firstWalkDuration, firstWalkDuration + firstTransitDuration, firstWalkDuration + firstTransitDuration + secondWalkDuration, totalMinutes]
        let stopCountPrimary = max(3, firstTransitDuration / 2)
        let stopCountSecondary = max(4, secondTransitDuration / 2)

        return [
            RouteItinerarySegment(
                timeText: schedule[0].clockString(from: startDate),
                placeTitle: originName,
                icon: nil,
                accentColor: .white,
                stepCard: nil,
                durationBadge: nil
            ),
            RouteItinerarySegment(
                timeText: schedule[1].clockString(from: startDate),
                placeTitle: "Premier arrêt",
                icon: "figure.walk",
                accentColor: AppTheme.Palette.brand.opacity(0.9),
                stepCard: RouteItineraryStepCard(
                    style: .mint,
                    title: "Marcher \(max(120, firstWalkDuration * 110))m jusqu’au premier arrêt",
                    subtitle: "Directions >",
                    lineBadge: nil,
                    serviceInfo: nil
                ),
                durationBadge: "\(firstWalkDuration) min",
                stopCountText: nil
            ),
            RouteItinerarySegment(
                timeText: schedule[2].clockString(from: startDate),
                placeTitle: "Correspondance",
                icon: transitCount > 1 ? "tram.fill" : "tram.fill",
                accentColor: AppTheme.Palette.success,
                stepCard: RouteItineraryStepCard(
                    style: .mint,
                    title: "Prenez le tram \(firstLine)\ndirection centre-ville",
                    subtitle: "Directions >",
                    lineBadge: firstLine,
                    serviceInfo: nil
                ),
                durationBadge: "\(firstTransitDuration) min",
                stopCountText: "\(stopCountPrimary) arrêts"
            ),
            RouteItinerarySegment(
                timeText: schedule[3].clockString(from: startDate),
                placeTitle: destinationName,
                icon: "figure.walk",
                accentColor: Color.white.opacity(0.85),
                stepCard: RouteItineraryStepCard(
                    style: .white,
                    title: "Marcher \(max(50, secondWalkDuration * 70))m jusqu’à \(destinationName)",
                    subtitle: "Directions >",
                    lineBadge: nil,
                    serviceInfo: nil
                ),
                durationBadge: "\(secondWalkDuration) min",
                stopCountText: nil
            ),
            RouteItinerarySegment(
                timeText: schedule[4].clockString(from: startDate),
                placeTitle: destinationName,
                icon: transitCount > 1 ? "bus.fill" : nil,
                accentColor: AppTheme.Palette.warning,
                stepCard: transitCount > 1 ? RouteItineraryStepCard(
                    style: .white,
                    title: "Prenez le bus \(secondLine)\ndirection \(destinationName)",
                    subtitle: "Directions >",
                    lineBadge: secondLine,
                    serviceInfo: RouteTransitServiceInfo(
                        lineCode: secondLine,
                        statusTitle: "Service Perturbé",
                        detail: "Perturbations mineures",
                        waitTime: "\(max(6, secondTransitDuration + 4)) min"
                    )
                ) : nil,
                durationBadge: transitCount > 1 ? "1 min" : nil,
                stopCountText: transitCount > 1 ? "\(stopCountSecondary) arrêts" : nil
            )
        ]
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        let polyline = route.polyline
        return (0..<polyline.pointCount).map { polyline.points()[$0].coordinate }
    }

    var mapRectWithPadding: MKMapRect {
        let rect = route.polyline.boundingMapRect
        return rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35)
    }

    func primaryBearing(from current: CLLocationCoordinate2D) -> Double? {
        let coords = routeCoordinates
        guard coords.count > 1 else { return nil }
        let nextCoord = nextCoordinate(from: current, in: coords) ?? coords[1]
        return current.bearing(to: nextCoord)
    }

    func arInstruction(from current: CLLocationCoordinate2D) -> RouteARInstruction {
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

    private func nextCoordinate(from current: CLLocationCoordinate2D, in coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coords.isEmpty else { return nil }
        let nearest = coords.enumerated().min { lhs, rhs in
            current.distance(to: lhs.element) < current.distance(to: rhs.element)
        }
        guard let nearest else { return nil }
        return coords[min(coords.count - 1, nearest.offset + 1)]
    }
}

private struct RouteItineraryDetailsView: View {
    let option: HomeRouteOption
    let onBack: () -> Void
    let onClose: () -> Void
    let onShowMap: () -> Void
    let onStartAR: () -> Void

    private var arrivalText: String {
        let arrival = Date().addingTimeInterval(option.route.expectedTravelTime)
        return Self.timeFormatter.string(from: arrival)
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ZStack {
            AppTheme.Palette.screen.ignoresSafeArea()

            VStack(spacing: 0) {
                HStack {
                    Button(action: onBack) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)

                    Spacer()

                    Text("Itinéraire détaillés")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 32, height: 32)
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 20)
                .padding(.top, 50)

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
                                    Text("Navigation AR")
                                        .font(AppTheme.Fonts.bodyStrong)
                                }
                                .foregroundStyle(AppTheme.Palette.textOnBrand)
                                .frame(maxWidth: .infinity)
                                .frame(height: AppTheme.ButtonHeight.primary)
                                .background(AppTheme.Palette.brandStrong)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button(action: onShowMap) {
                                Text("Voir sur la carte")
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(AppTheme.Palette.textPrimary)
                                    .frame(maxWidth: .infinity)
                                    .frame(height: AppTheme.ButtonHeight.secondary)
                                    .background(AppTheme.Palette.surfaceMuted)
                                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                            }
                        }
                        .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var itinerarySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text(option.originName)
                Spacer()
                Text(option.destinationName)
            }
            .font(AppTheme.Fonts.body)
            .foregroundStyle(AppTheme.Palette.textOnBrand)

            HStack {
                Text("Arrivée estimé :")
                Spacer()
                Text(arrivalText)
            }
            .font(AppTheme.Fonts.body)
            .foregroundStyle(AppTheme.Palette.textOnBrand)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(AppTheme.Palette.brand)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
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
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .frame(width: 42, height: AppTheme.ButtonHeight.secondary)
                            .background(AppTheme.Palette.overlay.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
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
                .padding(.bottom, 228)
            }

            VStack {
                Spacer()

                ARMiniMapCard(
                    option: option,
                    userCoordinate: locationManager.displayCoordinate,
                    heading: locationManager.heading
                )
                    .padding(.horizontal, 18)
                    .padding(.bottom, 26)
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
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                Spacer()
                Text(option.durationText)
                    .font(AppTheme.Fonts.title3)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
            }

            ZStack {
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .fill(AppTheme.Palette.surfaceElevated.opacity(0.94))

                Map(initialPosition: .rect(option.mapRectWithPadding)) {
                    MapPolyline(option.route.polyline)
                        .stroke(AppTheme.Palette.info, style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

                    Annotation("", coordinate: userCoordinate, anchor: .center) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 52, height: 52)
                            Circle()
                                .fill(AppTheme.Palette.brandStrong)
                                .frame(width: 26, height: 26)
                            Image(systemName: "location.north.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(.white)
                                .rotationEffect(.degrees(heading))
                        }
                    }
                }
                .mapStyle(.standard(elevation: .flat))
                .environment(\.colorScheme, .dark)
                .allowsHitTesting(false)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            }
            .frame(height: 170)
        }
        .padding(18)
        .background(AppTheme.Palette.screenElevated.opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
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
                    .foregroundStyle(AppTheme.Palette.info)

                Text(directionText)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)

                Spacer()

                Text(instruction.distanceText)
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
            }

            Text(instruction.primaryText)
                .font(AppTheme.Fonts.title2)
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            if let secondaryText = instruction.secondaryText {
                Text(secondaryText)
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textSecondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(AppTheme.Palette.overlay.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Palette.borderStrong, lineWidth: 1)
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
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white.opacity(0.82))
                .frame(width: 50, alignment: .leading)
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
                            .stroke(Color.white.opacity(0.9), lineWidth: segment.stepCard == nil ? 1 : 0)
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
                            .font(.system(size: 16, weight: .medium))
                            .foregroundStyle(.white)
                            .frame(width: 24)
                    }

                    Text(segment.placeTitle)
                        .font(.custom("Montserrat-Regular", size: 14))
                        .foregroundStyle(.white)

                    Spacer()

                    if let stopCountText = segment.stopCountText {
                        Text(stopCountText)
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.textMuted)
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
                            .font(.custom("Montserrat-SemiBold", size: 14))
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 12)
                    .frame(height: 33)
                    .overlay(
                        RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous)
                            .stroke(Color.white, lineWidth: 1)
                    )
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
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .fixedSize(horizontal: false, vertical: true)

                if let lineBadge = card.lineBadge {
                    Text(lineBadge)
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(AppTheme.Palette.brand)
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }

                Spacer(minLength: 0)
            }

            Text(card.subtitle)
                .font(AppTheme.Fonts.captionStrong)
                .foregroundStyle(AppTheme.Palette.info)

            if let serviceInfo = card.serviceInfo {
                RouteTransitServiceCard(info: serviceInfo)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card.style == .mint ? AppTheme.Palette.brand.opacity(0.75) : AppTheme.Palette.brand)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
    }
}

private struct RouteTransitServiceCard: View {
    let info: RouteTransitServiceInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(info.lineCode)
                .font(AppTheme.Fonts.bodyStrong)
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .frame(width: 29, height: 28)
                .background(AppTheme.Palette.success.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.statusTitle)
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.warning)
                Text(info.detail)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                Text("Prochain passage")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                    .padding(.top, 4)
                Text(info.waitTime)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.warning)
                .padding(.top, 4)
        }
        .padding(10)
        .background(AppTheme.Palette.screen)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(Color.white, lineWidth: 1)
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
