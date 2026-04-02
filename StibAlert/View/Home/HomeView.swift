import SwiftUI
import MapKit
import Combine

struct HomeView: View {
    @EnvironmentObject private var nav: AppNavigation
    @StateObject private var locationManager = HomeLocationManager()

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )
    @State private var showMenu = false
    @State private var showSearch = false
    @State private var currentRoute: MKRoute? = nil
    @State private var destinationCoord: CLLocationCoordinate2D? = nil

    var body: some View {
        ZStack {
            // ── Full-screen dark map ──────────────────────────────────
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
            }
            .mapStyle(.standard(elevation: .realistic))
            .environment(\.colorScheme, .dark)
            .ignoresSafeArea()

            // ── Top buttons ───────────────────────────────────────────
            VStack {
                HStack(spacing: 12) {
                    HamburgerButton(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showMenu = true }
                    })
                    SearchPillButton(action: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showSearch = true }
                    })
                }
                .padding(.horizontal, 20)
                .padding(.top, 8)
                Spacer()
            }
            .zIndex(2)

            // ── Search overlay ────────────────────────────────────────
            if showSearch {
                SearchInputOverlay(isShowing: $showSearch) { route, dest in
                    currentRoute = route
                    destinationCoord = dest
                    let rect = route.polyline.boundingMapRect
                    withAnimation(.easeInOut(duration: 0.8)) {
                        mapPosition = .rect(rect.insetBy(dx: -rect.width * 0.2, dy: -rect.height * 0.2))
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
                .zIndex(11)
            }

            // ── Waze menu ────────────────────────────────────────────
            if showMenu {
                WazeMenuOverlay(
                    isShowing: $showMenu,
                    onNavigate: { page in
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showMenu = false }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
                            withAnimation(.spring(response: 0.38, dampingFraction: 0.82)) {
                                nav.currentPage = page
                            }
                        }
                    },
                    onReport: {
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) { showMenu = false }
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

            // ── Page overlays ────────────────────────────────────────
            if nav.currentPage != .home {
                pageOverlay
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                    .zIndex(6)
            }
        }
        // ── Report sheet ──────────────────────────────────────────────
        .overlay(alignment: .bottom) {
            if nav.showReportSheet {
                ReportSheetView(isShowing: $nav.showReportSheet)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .zIndex(5)
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
    }

    @ViewBuilder
    private var pageOverlay: some View {
        ZStack {
            Color(hex: "#0B111E").ignoresSafeArea()

            // Back button always at top-left
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

            switch nav.currentPage {
            case .signalements:
                SignalementsView().padding(.top, 60)
            case .favorites:
                FavoritesView().padding(.top, 60)
            case .profile:
                ProfileView().padding(.top, 60)
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
                item("clock.arrow.circlepath","Signalements récents")      { onNavigate(.signalements); onClose() }
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
