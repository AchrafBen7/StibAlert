import SwiftUI
import MapKit
import Combine
import AVFoundation

struct HomeView: View {
    @EnvironmentObject private var nav: AppNavigation
    @StateObject private var locationManager = HomeLocationManager()

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )
    @State private var showSearch = false
    @State private var showLegend = false
    @State private var showRecentReportsSheet = false
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

    private var homeSignalClusters: [SearchSignalCluster] {
        Array(SearchSignalCluster.mockClusters.prefix(5))
    }

    var body: some View {
        ZStack {
            Map(position: $mapPosition) {
                MapCircle(center: locationManager.displayCoordinate, radius: 400)
                    .foregroundStyle(Color(hex: "#0B111E").opacity(0.10))
                    .stroke(Color(hex: "#B5CFF8"), lineWidth: 1)
                Annotation("", coordinate: locationManager.displayCoordinate, anchor: .center) {
                    UserLocationDotView(heading: locationManager.heading)
                }
                if let route = currentRoute {
                    MapPolyline(route.polyline)
                        .stroke(Color(hex: "#B5CFF8"), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))
                }
                if let dest = destinationCoord {
                    Annotation("", coordinate: dest, anchor: .bottom) {
                        Image(systemName: "mappin.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(Color(hex: "#B5CFF8"))
                            .shadow(radius: 4)
                    }
                }
                ForEach(homeSignalClusters.indices, id: \.self) { index in
                    let cluster = homeSignalClusters[index]
                    Annotation("", coordinate: cluster.coordinate.coordinate, anchor: .bottom) {
                        HomeSignalMarker(cluster: cluster)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic))
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()
            .allowsHitTesting(!(showSearch && !searchSuggestions.isEmpty))

            VStack {
                HStack {
                    HamburgerButton(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { nav.showSideMenu = true }
                    })

                    Spacer()

                    if showSearch {
                        HomeSearchBar(
                            query: $searchQuery,
                            onClose: {
                                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
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
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showSearch = true }
                        })
                        .transition(.scale.combined(with: .opacity))
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .animation(.spring(response: 0.28, dampingFraction: 0.88), value: showSearch)

                if showSearch, !searchSuggestions.isEmpty {
                    SearchSuggestionsDropdown(
                        suggestions: searchSuggestions,
                        isRouting: isRouting,
                        onSelect: { item in
                            Task { await buildRoute(to: item) }
                        }
                    )
                    .padding(.leading, 76)
                    .padding(.trailing, 20)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zIndex(30)
                }

                Spacer()

                HStack {
                    Spacer()

                    VStack(spacing: 12) {
                        HelpFloatingButton {
                            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                                showLegend = true
                            }
                        }

                        LocationFloatingButton {
                            recenterOnUser()
                        }
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 118)
            }
            .zIndex(2)

            if nav.showSideMenu {
                WazeMenuOverlay(
                    isShowing: $nav.showSideMenu,
                    onNavigate: { page in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { nav.showSideMenu = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                nav.currentPage = page
                            }
                        }
                    },
                    onReport: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { nav.showSideMenu = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                nav.showReportSheet = true
                            }
                        }
                    }
                )
                .transition(.opacity)
                .zIndex(10)
            }

            if showLegend {
                MapLegendOverlay {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showLegend = false
                    }
                }
                .transition(.opacity)
                .zIndex(9)
            }

            if showRecentReportsSheet {
                RecentReportsBottomSheet {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
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
        .overlay(alignment: .bottom) {
            if nav.showReportSheet {
                ReportSheetView(isShowing: $nav.showReportSheet)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
            } else if nav.currentPage == .home && !showRecentReportsSheet && !nav.showSideMenu && routeOptions.isEmpty {
                Button {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        showRecentReportsSheet = true
                    }
                } label: {
                    Text("Derniers signalements")
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                        .foregroundStyle(.white)
                        .frame(maxWidth: 311)
                        .frame(height: 58)
                        .background(Color.black)
                        .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.bottom, 34)
                .zIndex(4)
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: nav.showReportSheet)
        .animation(.spring(response: 0.38, dampingFraction: 0.82), value: nav.currentPage == .home)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear { locationManager.start() }
        .onReceive(locationManager.$userCoordinate.compactMap { $0 }.first()) { coord in
            withAnimation(.easeInOut(duration: 0.8)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: coord,
                    span: MKCoordinateSpan(latitudeDelta: 0.015, longitudeDelta: 0.015)
                ))
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

    private let bg = Color(hex: "#141820")
    private let itemText = Color.white.opacity(0.88)
    private let iconColor = Color.white.opacity(0.7)

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
                    .font(.system(size: 13))
                    .foregroundStyle(Color.white.opacity(0.3))
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
                    .fill(Color.white.opacity(0.12))
                    .frame(width: 52, height: 52)
                    .overlay(
                        Image(systemName: "person.fill")
                            .font(.system(size: 22, weight: .medium))
                            .foregroundStyle(Color.white.opacity(0.8))
                    )
                VStack(alignment: .leading, spacing: 3) {
                    Text("user-48155848")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                    Text("Mon profil")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(Color(hex: "#4CAF7C"))
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
                    .font(.system(size: 16, weight: .regular))
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
                    colors: [Color(hex: "#B5CFF8").opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 28, height: 36)
                .offset(y: -16)
                .rotationEffect(.degrees(heading))

            Circle()
                .fill(Color(hex: "#0B111E"))
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(Color(hex: "#B5CFF8"), lineWidth: 1))
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
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: "#0B111E"))
                .frame(width: 48, height: 48)
                .overlay(VStack(spacing: 5) {
                    ForEach(0..<3, id: \.self) { _ in
                        RoundedRectangle(cornerRadius: 1.5).fill(Color.white).frame(width: 20, height: 2)
                    }
                })
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct SearchCircleButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Circle()
                .fill(Color(hex: "#0B111E"))
                .frame(width: 48, height: 48)
                .overlay(
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSearchBar: View {
    @Binding var query: String
    let onClose: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.white)

            TextField("", text: $query, prompt: Text("Ou voulez-vous aller ?").foregroundStyle(Color.white.opacity(0.76)))
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.78))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(Color(hex: "#1B1B1B"))
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
                            .foregroundStyle(Color(hex: "#B5CFF8"))

                        VStack(alignment: .leading, spacing: 3) {
                            Text(item.name ?? "Lieu")
                                .font(.custom("Montserrat-SemiBold", size: 14))
                                .foregroundStyle(.white)
                            Text(item.placemark.title ?? "")
                                .font(.custom("Montserrat-Regular", size: 11))
                                .foregroundStyle(Color.white.opacity(0.6))
                                .lineLimit(1)
                        }

                        Spacer()

                        if isRouting {
                            ProgressView()
                                .tint(.white)
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
        .background(Color(hex: "#141820"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 10, x: 0, y: 4)
    }
}

private struct LocationFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .frame(width: 42, height: 40)
                .overlay(
                    Image(systemName: "location.north.fill")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                        .rotationEffect(.degrees(18))
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct HelpFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.black)
                .frame(width: 42, height: 40)
                .overlay(
                    Image(systemName: "questionmark")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white)
                )
                .shadow(color: .black.opacity(0.25), radius: 8, x: 0, y: 2)
        }
        .buttonStyle(.plain)
    }
}

private struct HomeSignalMarker: View {
    let cluster: SearchSignalCluster

    private var backgroundColor: Color {
        switch cluster.level {
        case .low:
            return Color(hex: "#57E3B6")
        case .medium:
            return Color(hex: "#FF9B2F")
        case .high:
            return Color(hex: "#FF7A7A")
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(backgroundColor)
                .frame(width: cluster.count > 9 ? 24 : 20, height: 20)

            Text("\(cluster.count)")
                .font(.custom("DelaGothicOne-Regular", size: 7))
                .foregroundStyle(.black)
        }
    }
}

private struct MapLegendOverlay: View {
    let onDismiss: () -> Void

    private let items: [(Color, String)] = [
        (Color(hex: "#FF7A7A"), "Perturbation critique"),
        (Color(hex: "#FF922A"), "Perturbation légère"),
        (Color(hex: "#57E3B6"), "Trafic normal"),
        (Color(hex: "#7DB2FF"), "Vos arrêts favoris"),
        (Color(hex: "#EE73D8"), "Lieu partenaire"),
        (Color(hex: "#FFD34D"), "Info spéciale")
    ]

    var body: some View {
        ZStack {
            Color.black.opacity(0.6)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text("Que signifient les icônes ?")
                    .font(.custom("DelaGothicOne-Regular", size: 18))
                    .foregroundStyle(.black)
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
                                .font(.custom("Montserrat-Regular", size: 14))
                                .foregroundStyle(.black.opacity(0.88))

                            Spacer()
                        }
                    }
                }
                .padding(.horizontal, 28)

                Button("Je comprends", action: onDismiss)
                    .font(.custom("DelaGothicOne-Regular", size: 16))
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 63)
                    .background(Color.black)
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .padding(.horizontal, 18)
                    .padding(.top, 30)
                    .padding(.bottom, 20)
            }
            .frame(width: 357)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
        }
    }
}

private struct RecentReportsBottomSheet: View {
    let onDismiss: () -> Void

    private let items: [RecentReportItem] = [
        .init(line: "46", title: "Propreté", time: "Il y a 1 min", details: "Panne technique sur la ligne, service temporairement interrompu"),
        .init(line: "46", title: "Propreté", time: "Il y a 1 min", details: "Panne technique sur la ligne, service temporairement interrompu")
    ]

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
                        .font(.custom("DelaGothicOne-Regular", size: 20))
                        .foregroundStyle(.white)

                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(Color.white.opacity(0.9))

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.08))
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
                }
                .padding(.horizontal, 22)
                .padding(.bottom, 24)
            }
            .frame(maxWidth: .infinity)
            .background(Color(hex: "#1B1B1B"))
            .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
    let id = UUID()
    let line: String
    let title: String
    let time: String
    let details: String
}

private struct RecentReportCard: View {
    let item: RecentReportItem

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 10) {
                Text(item.line)
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(.black)
                    .frame(width: 30, height: 28)
                    .background(Color(hex: "#F29DC3"))
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                (
                    Text(item.title + " ")
                        .font(.custom("DelaGothicOne-Regular", size: 16))
                    + Text(item.time)
                        .font(.custom("Montserrat-SemiBold", size: 11))
                )
                .foregroundStyle(.black)

                Spacer()

                Circle()
                    .fill(Color(hex: "#91BEE5"))
                    .frame(width: 10, height: 10)
            }

            Text(item.details)
                .font(.custom("Montserrat-Regular", size: 13))
                .foregroundStyle(.black.opacity(0.88))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .background(Color(hex: "#BBDCFF"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
                            .font(.custom("Montserrat-SemiBold", size: 14))
                            .foregroundStyle(.black)
                        Spacer()
                        Text("\(others.count + 1) trajets disponible")
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(Color(hex: "#D0D0D0"))
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
                .background(Color.black.opacity(0.82))
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(.white.opacity(0.8))
                            .frame(width: 28, height: 28)
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 18)
                    .padding(.trailing, 18)
                    .opacity(isExpanded ? 1 : 0)
                }
                .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
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
                    .fill(isSelected ? Color.white : Color.black)
                    .frame(width: 42, height: 41)
                    .overlay(
                        Image(systemName: isSelected ? "point.topleft.down.curvedto.point.bottomright.up.fill" : "point.topleft.down.curvedto.point.bottomright.up")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(isSelected ? .black : .white)
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(option.durationText)
                        .font(.custom("DelaGothicOne-Regular", size: 16))
                        .foregroundStyle(.black)

                    HStack(spacing: 10) {
                        Text(option.transitSummary)
                        Text(option.walkingSummary)
                        Text(option.reliabilityText)
                            .foregroundStyle(Color(hex: "#52D8AB"))
                    }
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black)
                }

                Spacer()

                if isRecommended {
                    Text("Recommandé")
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .frame(height: 20)
                        .background(Color.black)
                        .clipShape(Capsule())
                }
            }
            .padding(.horizontal, 13)
            .frame(height: 83)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
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
                accentColor: Color(hex: "#E3FFF4"),
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
                accentColor: Color(hex: "#22D79C"),
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
                accentColor: Color(hex: "#FAAC5A"),
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
            Color(hex: "#1B1B1B").ignoresSafeArea()

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
                        .font(.custom("Montserrat-SemiBold", size: 14))
                        .foregroundStyle(.white)

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
                                        .font(.custom("Montserrat-SemiBold", size: 16))
                                }
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity)
                                .frame(height: 49)
                                .background(Color(hex: "#214ED8"))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                            .buttonStyle(.plain)

                            Button(action: onShowMap) {
                                Text("Voir sur la carte")
                                    .font(.custom("Montserrat-Regular", size: 16))
                                    .foregroundStyle(Color(hex: "#1B1B1B"))
                                    .frame(maxWidth: .infinity)
                                    .frame(height: 49)
                                    .background(Color.white)
                                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
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
            .font(.custom("Montserrat-Regular", size: 14))
            .foregroundStyle(.black)

            HStack {
                Text("Arrivée estimé :")
                Spacer()
                Text(arrivalText)
            }
            .font(.custom("Montserrat-Regular", size: 14))
            .foregroundStyle(.black)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
                            .foregroundStyle(.white)
                            .frame(width: 42, height: 40)
                            .background(Color.black.opacity(0.82))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
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
                    Color(hex: "#39A6FF").opacity(0.55),
                    style: StrokeStyle(lineWidth: 22, lineCap: .round)
                )
                .blur(radius: 4)

                VStack(spacing: 10) {
                    Spacer()

                    ForEach(0..<8, id: \.self) { index in
                        ARChevronShape()
                            .fill(Color(hex: "#48B2FF").opacity(0.92 - Double(index) * 0.08))
                            .frame(
                                width: max(54, 148 - CGFloat(index) * 12),
                                height: max(24, 56 - CGFloat(index) * 4)
                            )
                            .shadow(color: Color(hex: "#48B2FF").opacity(0.45), radius: 10, x: 0, y: 0)
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
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(.white)
                Spacer()
                Text(option.durationText)
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.white)
            }

            ZStack {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(hex: "#3A4365").opacity(0.94))

                Map(initialPosition: .rect(option.mapRectWithPadding)) {
                    MapPolyline(option.route.polyline)
                        .stroke(Color(hex: "#39A6FF"), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))

                    Annotation("", coordinate: userCoordinate, anchor: .center) {
                        ZStack {
                            Circle()
                                .fill(Color.white.opacity(0.14))
                                .frame(width: 52, height: 52)
                            Circle()
                                .fill(Color(hex: "#7F8DFF"))
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
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
            .frame(height: 170)
        }
        .padding(18)
        .background(Color(hex: "#2E3554").opacity(0.92))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
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
                    .foregroundStyle(Color(hex: "#48B2FF"))

                Text(directionText)
                    .font(.custom("Montserrat-SemiBold", size: 15))
                    .foregroundStyle(.white)

                Spacer()

                Text(instruction.distanceText)
                    .font(.custom("DelaGothicOne-Regular", size: 13))
                    .foregroundStyle(.white)
            }

            Text(instruction.primaryText)
                .font(.custom("Montserrat-SemiBold", size: 18))
                .foregroundStyle(.white)
                .fixedSize(horizontal: false, vertical: true)

            if let secondaryText = instruction.secondaryText {
                Text(secondaryText)
                    .font(.custom("Montserrat-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.82))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(Color.black.opacity(0.74))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
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
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(Color(hex: "#969BA6"))
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
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
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
                    .font(.custom("Montserrat-SemiBold", size: 12))
                    .foregroundStyle(.black)
                    .fixedSize(horizontal: false, vertical: true)

                if let lineBadge = card.lineBadge {
                    Text(lineBadge)
                        .font(.custom("Montserrat-SemiBold", size: 10))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(Color(hex: "#EFE048"))
                        .clipShape(RoundedRectangle(cornerRadius: 2, style: .continuous))
                }

                Spacer(minLength: 0)
            }

            Text(card.subtitle)
                .font(.custom("Montserrat-SemiBold", size: 12))
                .foregroundStyle(Color(hex: "#214ED8"))

            if let serviceInfo = card.serviceInfo {
                RouteTransitServiceCard(info: serviceInfo)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card.style == .mint ? Color(hex: "#DEFFF4") : .white)
        .clipShape(RoundedRectangle(cornerRadius: 7, style: .continuous))
    }
}

private struct RouteTransitServiceCard: View {
    let info: RouteTransitServiceInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(info.lineCode)
                .font(.custom("Montserrat-SemiBold", size: 14))
                .foregroundStyle(.white)
                .frame(width: 29, height: 28)
                .background(Color(hex: "#4C8B33"))
                .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.statusTitle)
                    .font(.custom("Montserrat-SemiBold", size: 12))
                    .foregroundStyle(Color(hex: "#FB9324"))
                Text(info.detail)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.white)
                Text("Prochain passage")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.white)
                    .padding(.top, 4)
                Text(info.waitTime)
                    .font(.custom("Montserrat-SemiBold", size: 14))
                    .foregroundStyle(.white)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(Color(hex: "#FB9324"))
                .padding(.top, 4)
        }
        .padding(10)
        .background(Color.black)
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
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
                    .foregroundColor(.white)
                Text("Rechercher un arrêt…")
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundColor(.white.opacity(0.6))
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 16)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(Color(hex: "#0B111E"))
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
                            .foregroundStyle(Color.white)
                            .frame(width: 48, height: 48)
                            .background(Color(hex: "#0B111E"))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)

                    HStack(spacing: 10) {
                        Image(systemName: isRouting ? "arrow.triangle.turn.up.right.circle.fill" : "magnifyingglass")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Color.white.opacity(0.6))
                        ZStack(alignment: .leading) {
                            if query.isEmpty {
                                Text("Où voulez-vous aller ?")
                                    .font(.system(size: 14))
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            TextField("", text: $query)
                                .font(.system(size: 14))
                                .foregroundStyle(Color.white)
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
                                    .foregroundStyle(Color.white.opacity(0.4))
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color(hex: "#1A1F2E"))
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
                                        .foregroundStyle(Color(hex: "#B5CFF8"))
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(item.name ?? "")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(Color.white)
                                        if let addr = item.placemark.title {
                                            Text(addr)
                                                .font(.system(size: 12))
                                                .foregroundStyle(Color.white.opacity(0.5))
                                                .lineLimit(1)
                                        }
                                    }
                                    Spacer()
                                    if isRouting {
                                        ProgressView()
                                            .tint(.white)
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
                    .background(Color(hex: "#141820"))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
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
