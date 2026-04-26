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
    @State private var showRecentReportsSheet = false
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
    @State private var problemFilter: ReportProblemType? = nil
    @State private var cameraLatitudeDelta: Double = 0.04
    @State private var showReportAuthGate = false
    @State private var guestGateReason: GuestAuthReason = .report

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
            } else if nav.currentPage == .home, !showRecentReportsSheet, !nav.showSideMenu, routeOptions.isEmpty {
                HomeDecisionDashboard(
                    data: homeDashboardData,
                    isLoadingDecision: isLoadingTransportOverview,
                    onOpenStibi: { stibi.openConversation() },
                    onPrimaryCommuteAction: {
                        if let action = currentCommuteBrief?.actions.first {
                            Task { await stibi.performTargetedAction(id: action.id) }
                        } else {
                            stibi.openConversation()
                        }
                    },
                    onOpenRecentReports: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showRecentReportsSheet = true
                        }
                    }
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 132)
                .zIndex(4)
            }
        }
        .overlay(alignment: .top) {
            if nav.currentPage == .home, !nav.showReportSheet, !nav.showSideMenu, !showSearch {
                VStack(spacing: 10) {
                    HomeStatusBanner(
                        favoriteAffected: favoriteAffectedCount,
                        totalActive: totalActiveSignalementsCount,
                        lastUpdated: lastFetchedAt,
                        onTap: {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                showRecentReportsSheet = true
                            }
                        }
                    )
                    .padding(.horizontal, 20)

                    if let signalementLoadError {
                        HStack(spacing: 8) {
                            Image(systemName: "wifi.slash")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundStyle(AppTheme.Palette.alert)
                            Text(signalementLoadError)
                                .font(AppTheme.Fonts.caption)
                                .foregroundStyle(.white.opacity(0.85))
                            Spacer()
                            Button {
                                self.signalementLoadError = nil
                                Task { await loadRemoteSignalements() }
                            } label: {
                                Text("Réessayer")
                                    .font(AppTheme.Fonts.captionStrong)
                                    .foregroundStyle(AppTheme.Palette.info)
                            }
                            .buttonStyle(.plain)
                        }
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.horizontal, 20)
                    }

                    HomeMapFilterBar(selected: $problemFilter)
                }
                .padding(.top, 76)
                .transition(.move(edge: .top).combined(with: .opacity))
                .zIndex(3)
            }
        }
        .overlay(alignment: .bottom) {
            if nav.currentPage == .home, !nav.showReportSheet, !showRecentReportsSheet, !nav.showSideMenu, routeOptions.isEmpty, selectedSignalementPreview == nil {
                HomeFloatingActions(
                    onReport: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            nav.showReportSheet = true
                        }
                    },
                    onRoute: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            showSearch = true
                        }
                    }
                )
                .padding(.bottom, 330)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(6)
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
                .padding(.bottom, 190)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(7)
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
        .task { lineShapesLoader.loadIfNeeded() }
        .task { await loadTransportOverview() }
        .task { await loadStibiBrief() }
        .onChange(of: nav.showReportSheet) { oldValue, newValue in
            if oldValue && !newValue {
                Task {
                    await loadRemoteSignalements()
                    await loadStibiBrief(
                        lat: locationManager.userCoordinate?.latitude,
                        lng: locationManager.userCoordinate?.longitude
                    )
                }
            }
        }
        .onReceive(realtimeSignalements.$latestSignalement.compactMap { $0 }) { signalement in
            mergeIncomingSignalement(signalement)
        }
        .onChange(of: nav.currentPage) { _, newValue in
            switch newValue {
            case .home:        stibi.setCurrentScreen("home")
            case .signalements: stibi.setCurrentScreen("signalements")
            case .favorites:   stibi.setCurrentScreen("favorites")
            case .profile:     stibi.setCurrentScreen("profile")
            case .profileMain: stibi.setCurrentScreen("profile_main")
            }
        }
        .onReceive(locationManager.$userCoordinate.compactMap { $0 }.first()) { coord in
            withAnimation(.easeInOut(duration: 0.8)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                ))
            }
            Task {
                await loadTransportOverview(lat: coord.latitude, lng: coord.longitude)
                await loadStibiBrief(lat: coord.latitude, lng: coord.longitude)
            }
        }
        .onChange(of: searchQuery) { _, newValue in
            searchTask?.cancel()
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            guard showSearch, !trimmed.isEmpty else {
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
        }
        .mapStyle(.standard(elevation: .realistic))
        .environment(\.colorScheme, .dark)
        .ignoresSafeArea()
        .allowsHitTesting(!(showSearch && !searchSuggestions.isEmpty))
        .onMapCameraChange(frequency: .onEnd) { ctx in
            cameraLatitudeDelta = ctx.region.span.latitudeDelta
        }
    }

    // MARK: - Map gradient

    private var mapGradient: some View {
        LinearGradient(
            colors: [Color.clear, Color.black.opacity(0.10), Color.black.opacity(0.46), Color.black.opacity(0.72)],
            startPoint: .top, endPoint: .bottom
        )
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    // MARK: - Controls (search + floating buttons)

    @ViewBuilder private var controlsLayer: some View {
        VStack {
            HStack {
                Spacer()

                if showSearch {
                    HomeSearchBar(
                        query: $searchQuery,
                        onClose: {
                            withAnimation(transitionSpring) {
                                showSearch = false
                                searchQuery = ""
                                searchSuggestions = []
                            }
                        }
                    )
                    .frame(width: 291)
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    SearchCircleButton(action: {
                        withAnimation(transitionSpring) { showSearch = true }
                    })
                    .transition(.scale.combined(with: .opacity))
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .animation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.28, dampingFraction: 0.88), value: showSearch)

            if showSearch, !searchSuggestions.isEmpty {
                SearchSuggestionsDropdown(
                        suggestions: searchSuggestions,
                        isRouting: isRouting,
                        onSelect: { item in
                            Task { await buildRoute(to: item) }
                        }
                    )
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
                }

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
                .padding(.bottom, 172)
            }
            .zIndex(2)
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

        if showRecentReportsSheet {
            RecentReportsBottomSheet(
                items: recentReportItems,
                canLoadMore: signalementsPage < signalementsTotalPages,
                isLoadingMore: isLoadingSignalements,
                onLoadMore: {
                    Task { await loadMoreRemoteSignalementsIfNeeded() }
                }
            ) {
                withAnimation(transitionSpring) {
                    showRecentReportsSheet = false
                }
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(8)
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

    private func recenterOnUser() {
        let coord = locationManager.displayCoordinate
        withAnimation(.easeInOut(duration: 0.6)) {
            mapPosition = .region(
                MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
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
    private func loadMoreRemoteSignalementsIfNeeded() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingSignalements else { return }
        guard signalementsPage < signalementsTotalPages else { return }

        isLoadingSignalements = true
        defer { isLoadingSignalements = false }

        do {
            let nextPage = signalementsPage + 1
            let response = try await SignalementService.liste(page: nextPage)
            signalementsPage = response.pagination?.page ?? nextPage
            signalementsTotalPages = response.pagination?.totalPages ?? signalementsTotalPages
            let existingIds = Set(remoteSignalements.map(\.id))
            let newItems = response.signalements.filter { !existingIds.contains($0.id) }
            remoteSignalements.append(contentsOf: newItems)
        } catch {
            print("Signalements pagination failed: \(error.localizedDescription)")
        }
    }

    private var recentReportItems: [RecentReportItem] {
        return remoteSignalements.prefix(10).map { signalement in
            RecentReportItem(
                id: signalement.id,
                line: signalement.ligne,
                title: signalement.typeProbleme,
                time: signalement.freshnessLabel,
                details: signalement.description,
                signalementId: signalement.id,
                status: signalement.status,
                source: signalement.sourceLabel,
                confidence: signalement.confidenceLabel,
                community: signalement.community
            )
        }
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
            Color((nav.currentPage == .signalements || nav.currentPage == .favorites || nav.currentPage == .profile || nav.currentPage == .profileMain) ? "#1B1B1B" : "#0B111E").ignoresSafeArea()

            if nav.currentPage != .signalements && nav.currentPage != .favorites && nav.currentPage != .profile && nav.currentPage != .profileMain {
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

private struct SearchCircleButton: View {
    @ScaledMetric(relativeTo: .body) private var buttonSize: CGFloat = 48
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(AppTheme.Palette.screen)
                .frame(width: buttonSize, height: buttonSize)
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
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
                .foregroundStyle(AppTheme.Palette.textPrimary)

            TextField("", text: $query, prompt: Text("Ou voulez-vous aller ?").foregroundStyle(AppTheme.Palette.textSecondary))
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textSecondary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: AppTheme.ButtonHeight.secondary)
        .background(AppTheme.Palette.surface)
        .clipShape(Capsule())
        .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
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
                            .foregroundStyle(AppTheme.Palette.info)

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name ?? "Lieu")
                                .font(AppTheme.Fonts.bodyStrong)
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                            Text(item.placemark.title ?? "")
                                .font(AppTheme.Fonts.caption)
                                .foregroundStyle(AppTheme.Palette.textSecondary)
                                .lineLimit(1)
                        }

                        Spacer()

                        if isRouting {
                            ProgressView()
                                .tint(AppTheme.Palette.textPrimary)
                                .scaleEffect(0.85)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                }
                .buttonStyle(.plain)

                if item != suggestions.last {
                    Divider().overlay(Color.white.opacity(0.08))
                }
            }
        }
        .background(AppTheme.Palette.screenElevated)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

private struct LocationFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Palette.screen)
                .frame(width: 42, height: AppTheme.ButtonHeight.secondary)
                .overlay(
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .rotationEffect(.degrees(18))
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
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
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .fill(AppTheme.Palette.screen)
                .frame(width: 42, height: AppTheme.ButtonHeight.secondary)
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
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

struct HomeDecisionCard: View {
    let data: TransportHomeDecisionData
    let isLoading: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .center) {
                Text(data.title)
                    .font(AppTheme.Fonts.title3)
                    .foregroundStyle(AppTheme.Palette.textPrimary)

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

            Text(data.nextDepartureSummary)
                .font(AppTheme.Fonts.bodyStrong)
                .foregroundStyle(AppTheme.Palette.info)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.screenElevated.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
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
        VStack(alignment: .leading, spacing: 10) {
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
                Text("Départ habituel \(departureTime)")
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.info)
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
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.screenElevated.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
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

    private let items: [(Color, String)] = [
        (AppTheme.Palette.alert, "Perturbation critique"),
        (AppTheme.Palette.warning, "Perturbation légère"),
        (AppTheme.Palette.success, "Trafic normal"),
        (AppTheme.Palette.info, "Vos arrêts favoris"),
        (AppTheme.Palette.brandStrong, "Lieu partenaire"),
        (AppTheme.Palette.brand, "Info spéciale")
    ]

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
                    ForEach(items.indices, id: \.self) { index in
                        HStack(spacing: 12) {
                            Circle()
                                .fill(items[index].0)
                                .frame(width: 30, height: 30)

                            Text(items[index].1)
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.88))

                            Spacer()
                        }
                    }
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
