import SwiftUI

struct SearchView: View {
    @StateObject private var locationManager = SearchLocationManager()
    @StateObject private var autocompleteManager = SearchAutocompleteManager()
    @State private var selectedScope: SearchScope = .all
    @State private var origin = SearchJourneyMockData.defaultOrigin
    @State private var destination: SearchPlace?
    @State private var activeField: SearchField = .none
    @State private var query = ""
    @State private var journey: SearchJourney?
    @State private var isLoadingRoute = false
    @State private var routeNote: String?
    @State private var useCurrentLocation = true
    @State private var isResolvingSuggestion = false

    private var effectiveOrigin: SearchPlace {
        if useCurrentLocation, let current = locationManager.currentPlace {
            return current
        }

        return origin
    }

    private var visiblePlaces: [SearchPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = SearchJourneyMockData.places

        if activeField == .origin, let current = locationManager.currentPlace {
            base.removeAll { $0.id == current.id }
            base.insert(current, at: 0)
        }

        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var visibleSuggestions: [SearchPlaceSuggestion] {
        guard !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return autocompleteManager.suggestions
    }

    private var routeRequestKey: String {
        let originToken = "\(effectiveOrigin.id)-\(effectiveOrigin.coordinate.latitude)-\(effectiveOrigin.coordinate.longitude)"
        let destinationToken = destination.map {
            "\($0.id)-\($0.coordinate.latitude)-\($0.coordinate.longitude)"
        } ?? "none"
        return "\(originToken)|\(destinationToken)|\(selectedScope.title)"
    }

    var body: some View {
        ZStack {
            SearchTransitMapView(
                selectedScope: selectedScope,
                journey: journey
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.14),
                    Color.black.opacity(0.03),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                SearchTopBar(
                    query: $query,
                    destination: destination,
                    isExpanded: activeField != .none,
                    onOpenMenu: {},
                    onOpenSearch: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            activeField = .destination
                        }
                    },
                    onCloseSearch: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            activeField = .none
                            query = ""
                        }
                    }
                )
                .padding(.top, 8)
                .padding(.horizontal, DesignSystem.Spacing.md)

                if activeField != .none {
                    SearchDestinationSheet(
                        title: "Ou voulez-vous aller ?",
                        query: $query,
                        selectedField: activeField,
                        suggestions: visibleSuggestions,
                        places: visiblePlaces,
                        isResolvingSuggestion: isResolvingSuggestion,
                        locationDenied: locationManager.isDenied,
                        onUseCurrentLocation: {
                            useCurrentLocation = true
                            activeField = .none
                            query = ""
                        },
                        onSelectSuggestion: applySuggestion,
                        onSelect: applySelection
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            Button("Derniers signalements") {}
                .font(AppTheme.Fonts.clash(18))
                .foregroundStyle(.white)
                .frame(maxWidth: 311)
                .frame(height: 58)
                .background(Color(hex: "#0B111E"))
                .clipShape(Capsule())
                .padding(.bottom, 30)
        }
        .background(DesignSystem.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
        .task(id: routeRequestKey) {
            await rebuildJourney()
        }
        .onChange(of: query) { _, newValue in
            autocompleteManager.updateQuery(newValue)
        }
    }

    private func swapPlaces() {
        guard let destination else { return }

        let previousOrigin = effectiveOrigin
        origin = destination
        self.destination = previousOrigin
        useCurrentLocation = false
    }

    private func applySelection(_ place: SearchPlace) {
        switch activeField {
        case .origin:
            if place.id == SearchLocationManager.currentLocationID {
                useCurrentLocation = true
            } else {
                useCurrentLocation = false
                origin = place
            }
        case .destination:
            destination = place
        case .none:
            break
        }

        query = ""
        activeField = .none
    }

    private func applySuggestion(_ suggestion: SearchPlaceSuggestion) {
        isResolvingSuggestion = true

        Task {
            do {
                let place = try await autocompleteManager.resolve(suggestion)
                await MainActor.run {
                    applySelection(place)
                    isResolvingSuggestion = false
                }
            } catch {
                await MainActor.run {
                    isResolvingSuggestion = false
                }
            }
        }
    }

    private func rebuildJourney() async {
        guard let destination, destination.id != effectiveOrigin.id else {
            await MainActor.run {
                journey = nil
                isLoadingRoute = false
                routeNote = nil
            }
            return
        }

        await MainActor.run {
            isLoadingRoute = true
            routeNote = nil
        }

        do {
            let calculated = try await SearchRouteCalculator.calculate(
                from: effectiveOrigin,
                to: destination
            )

            await MainActor.run {
                journey = calculated
                isLoadingRoute = false
                routeNote = "Real route via Apple Maps"
            }
        } catch {
            let fallback = SearchJourneyMockData.journey(from: effectiveOrigin, to: destination)
            await MainActor.run {
                journey = fallback
                isLoadingRoute = false
                routeNote = "Fallback preview used"
            }
        }
    }
}

private struct SearchTopBar: View {
    @Binding var query: String
    let destination: SearchPlace?
    let isExpanded: Bool
    let onOpenMenu: () -> Void
    let onOpenSearch: () -> Void
    let onCloseSearch: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpenMenu) {
                SearchIconButton(icon: "line.3.horizontal")
            }
            .buttonStyle(.plain)

            Spacer()

            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    TextField("", text: $query, prompt: Text(destination?.name ?? "Ou voulez-vous aller ?").foregroundStyle(Color.white.opacity(0.72)))
                        .font(AppTheme.Fonts.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Button(action: onCloseSearch) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 14)
                .frame(width: 244, height: 40)
                .background(Color(hex: "#0B111E"))
                .clipShape(Capsule())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Button(action: onOpenSearch) {
                    SearchIconButton(icon: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isExpanded)
    }
}


private struct SearchIconButton: View {
    let icon: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Color(hex: "#0B111E"))
                .frame(width: 42, height: 40)

            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

private struct SearchDestinationSheet: View {
    let title: String
    @Binding var query: String
    let selectedField: SearchField
    let suggestions: [SearchPlaceSuggestion]
    let places: [SearchPlace]
    let isResolvingSuggestion: Bool
    let locationDenied: Bool
    let onUseCurrentLocation: () -> Void
    let onSelectSuggestion: (SearchPlaceSuggestion) -> Void
    let onSelect: (SearchPlace) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)

            Text(title)
                .font(AppTheme.Fonts.clash(18))
                .foregroundStyle(DesignSystem.Colors.primaryText)

            if selectedField == .origin {
                Button(action: onUseCurrentLocation) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(DesignSystem.Colors.success.opacity(0.14))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.success)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text("Utiliser ma position")
                                .font(DesignSystem.Typography.bodySemibold)
                                .foregroundStyle(DesignSystem.Colors.primaryText)

                            Text(locationDenied ? "L'acces a la localisation est refuse." : "Utilisez votre position actuelle comme depart.")
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(LinearGradient(
                        colors: [
                            DesignSystem.Colors.accentSoft,
                            Color.white
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    ))
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }

            HStack(spacing: 12) {
                Image(systemName: selectedField == .origin ? "location.fill" : "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                TextField(
                    selectedField == .origin ? "Rechercher un depart" : "Rechercher une destination",
                    text: $query
                )
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Suggestions")
                                .font(DesignSystem.Typography.labelSemibold)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(suggestions) { suggestion in
                                Button {
                                    onSelectSuggestion(suggestion)
                                } label: {
                                    HStack(spacing: 14) {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(DesignSystem.Colors.accent.opacity(0.10))
                                            .frame(width: 46, height: 46)
                                            .overlay(
                                                Image(systemName: "sparkle.magnifyingglass")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundStyle(DesignSystem.Colors.accent)
                                            )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(suggestion.title)
                                                .font(DesignSystem.Typography.bodySemibold)
                                                .foregroundStyle(DesignSystem.Colors.primaryText)

                                            Text(suggestion.subtitle)
                                                .font(DesignSystem.Typography.description)
                                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                                .multilineTextAlignment(.leading)
                                        }

                                        Spacer()

                                        if isResolvingSuggestion {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                    .padding(14)
                                    .background(DesignSystem.Colors.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    if !places.isEmpty {
                        Text("Bruxelles")
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, suggestions.isEmpty ? 0 : 4)
                    }

                    ForEach(places) { place in
                        Button {
                            onSelect(place)
                        } label: {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DesignSystem.Colors.accentSoft)
                                    .frame(width: 46, height: 46)
                                    .overlay(
                                        Image(systemName: place.id == SearchLocationManager.currentLocationID ? "location.fill" : "mappin.and.ellipse")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(DesignSystem.Colors.accent)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name)
                                        .font(DesignSystem.Typography.bodySemibold)
                                        .foregroundStyle(DesignSystem.Colors.primaryText)

                                    Text(place.subtitle)
                                        .font(DesignSystem.Typography.description)
                                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(DesignSystem.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 300)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }
}

private struct SearchJourneySummaryCard: View {
    let journey: SearchJourney
    let isLoading: Bool
    let routeNote: String?
    let onEditDestination: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(journey.isReal ? "Real route" : "Preview route")
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(journey.isReal ? DesignSystem.Colors.success : DesignSystem.Colors.accentSand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((journey.isReal ? DesignSystem.Colors.success : DesignSystem.Colors.accentSand).opacity(0.12))
                            .clipShape(Capsule())

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text("\(journey.origin.name) → \(journey.destination.name)")
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(2)

                    Text("\(journey.eta) min • \(journey.lineSummary)")
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    if let routeNote {
                        Text(routeNote)
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }

                    if !journey.alternatives.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 10) {
                                ForEach(journey.alternatives) { alternative in
                                    VStack(alignment: .leading, spacing: 4) {
                                        Text(alternative.title)
                                            .font(DesignSystem.Typography.labelSemibold)
                                            .foregroundStyle(DesignSystem.Colors.primaryText)
                                            .lineLimit(1)

                                        Text("\(alternative.eta) min")
                                            .font(DesignSystem.Typography.bodySemibold)
                                            .foregroundStyle(DesignSystem.Colors.accent)

                                        Text(alternative.lineSummary)
                                            .font(DesignSystem.Typography.description)
                                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                                            .lineLimit(2)
                                    }
                                    .frame(width: 180, alignment: .leading)
                                    .padding(12)
                                    .background(DesignSystem.Colors.cardBackground.opacity(0.82))
                                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }

                    if !journey.nearbyVehicles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nearby STIB vehicles")
                                .font(DesignSystem.Typography.labelSemibold)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(journey.nearbyVehicles) { vehicle in
                                        HStack(spacing: 7) {
                                            Image(systemName: vehicle.icon)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 22, height: 22)
                                                .background(vehicle.tint)
                                                .clipShape(Circle())

                                            Text("\(vehicle.routeCode) • \(vehicle.label)")
                                                .font(DesignSystem.Typography.labelSemibold)
                                                .foregroundStyle(DesignSystem.Colors.primaryText)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(DesignSystem.Colors.cardBackground.opacity(0.88))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()
            }

            Button("Change destination") {
                onEditDestination()
            }
            .buttonStyle(SecondaryButton())
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}

enum SearchScope: CaseIterable, Identifiable {
    case all
    case metro
    case tram
    case bus
    case stops

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .metro: return "Metro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        case .stops: return "Stops"
        }
    }
}

enum SearchField {
    case origin
    case destination
    case none
}

struct SearchPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: TransitCoordinate
}

struct SearchJourney {
    let origin: SearchPlace
    let destination: SearchPlace
    let path: [TransitCoordinate]
    let eta: Int
    let lineSummary: String
    let isReal: Bool
    let alternatives: [SearchRouteAlternative]
    let nearbyVehicles: [SearchNearbyTransit]
}

enum SearchJourneyMockData {
    static let places: [SearchPlace] = [
        .init(
            id: "central",
            name: "Bruxelles-Central",
            subtitle: "Historic core and fast interchange",
            coordinate: .init(latitude: 50.8466, longitude: 4.3572)
        ),
        .init(
            id: "arts-loi",
            name: "Arts-Loi",
            subtitle: "European quarter connection",
            coordinate: .init(latitude: 50.8455, longitude: 4.3697)
        ),
        .init(
            id: "rogier",
            name: "Rogier",
            subtitle: "Retail district and metro hub",
            coordinate: .init(latitude: 50.8559, longitude: 4.3603)
        ),
        .init(
            id: "heysel",
            name: "Heysel",
            subtitle: "Northern events and expo zone",
            coordinate: .init(latitude: 50.8949, longitude: 4.3417)
        ),
        .init(
            id: "ulb",
            name: "ULB Solbosch",
            subtitle: "Campus and southern tram corridor",
            coordinate: .init(latitude: 50.8138, longitude: 4.3815)
        )
    ]

    static let defaultOrigin = places[0]

    static func journey(from origin: SearchPlace, to destination: SearchPlace) -> SearchJourney {
        let path = curvedPath(from: origin.coordinate, to: destination.coordinate)
        let eta = estimatedMinutes(from: origin.coordinate, to: destination.coordinate)
        let lines = suggestedLineSummary(from: origin, to: destination)

        return .init(
            origin: origin,
            destination: destination,
            path: path,
            eta: eta,
            lineSummary: lines,
            isReal: false,
            alternatives: [],
            nearbyVehicles: SearchTransitCorridorAnalyzer.nearbyVehicles(for: path)
        )
    }

    private static func curvedPath(from start: TransitCoordinate, to end: TransitCoordinate) -> [TransitCoordinate] {
        let midLatitude = (start.latitude + end.latitude) / 2
        let midLongitude = (start.longitude + end.longitude) / 2
        let latDelta = end.latitude - start.latitude
        let lonDelta = end.longitude - start.longitude
        let offsetScale = max(0.004, min(0.012, sqrt(latDelta * latDelta + lonDelta * lonDelta) * 0.35))
        let control = TransitCoordinate(
            latitude: midLatitude + lonDelta * offsetScale,
            longitude: midLongitude - latDelta * offsetScale
        )

        return stride(from: 0.0, through: 1.0, by: 0.1).map { value in
            quadraticPoint(start: start, control: control, end: end, t: value)
        }
    }

    private static func quadraticPoint(
        start: TransitCoordinate,
        control: TransitCoordinate,
        end: TransitCoordinate,
        t: Double
    ) -> TransitCoordinate {
        let oneMinusT = 1 - t
        let latitude = oneMinusT * oneMinusT * start.latitude
            + 2 * oneMinusT * t * control.latitude
            + t * t * end.latitude
        let longitude = oneMinusT * oneMinusT * start.longitude
            + 2 * oneMinusT * t * control.longitude
            + t * t * end.longitude
        return .init(latitude: latitude, longitude: longitude)
    }

    private static func estimatedMinutes(from start: TransitCoordinate, to end: TransitCoordinate) -> Int {
        let latScale = 111_000.0
        let lonScale = 111_000.0 * cos(((start.latitude + end.latitude) / 2.0) * .pi / 180.0)
        let dx = (end.longitude - start.longitude) * lonScale
        let dy = (end.latitude - start.latitude) * latScale
        let kilometers = sqrt(dx * dx + dy * dy) / 1_000
        return max(8, Int((kilometers / 0.55).rounded()))
    }

    private static func suggestedLineSummary(from origin: SearchPlace, to destination: SearchPlace) -> String {
        let combos: [Set<String>: String] = [
            Set(["central", "arts-loi"]): "Metro 1 / 5",
            Set(["central", "rogier"]): "Metro 2 / 6",
            Set(["arts-loi", "ulb"]): "Tram 8 + Metro 2",
            Set(["rogier", "heysel"]): "Metro 6",
            Set(["central", "ulb"]): "Bus 95 + Tram 8",
        ]

        return combos[Set([origin.id, destination.id])] ?? "Metro + Tram mix"
    }
}
