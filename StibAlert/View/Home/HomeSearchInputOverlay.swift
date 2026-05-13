import MapKit
import SwiftUI

struct SearchPillButton: View {
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

struct SearchInputOverlay: View {
    @Binding var isShowing: Bool
    let onRouteFound: (MKRoute, CLLocationCoordinate2D) -> Void

    @State private var query = ""
    @State private var suggestions: [MKMapItem] = []
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
                searchBar
                    .padding(.horizontal, 20)
                    .padding(.top, 8)

                if !suggestions.isEmpty {
                    suggestionsList
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

    private var searchBar: some View {
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
                            guard !newVal.isEmpty else {
                                suggestions = []
                                return
                            }
                            searchTask = Task {
                                try? await Task.sleep(nanoseconds: 300_000_000)
                                guard !Task.isCancelled else { return }
                                await searchSuggestions(for: newVal)
                            }
                        }
                }
                if !query.isEmpty {
                    Button {
                        query = ""
                        suggestions = []
                    } label: {
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
    }

    private var suggestionsList: some View {
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
    }

    private func dismiss() {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            isShowing = false
        }
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
