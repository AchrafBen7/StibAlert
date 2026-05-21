import SwiftUI
import MapKit

struct HomeRoutePlannerSheet: View {
    @Binding var isPresented: Bool

    let userCoordinate: CLLocationCoordinate2D?
    let isRouting: Bool
    let onPlanRoute: (MKMapItem, MKMapItem, String) -> Void

    @State private var departureQuery = "Votre position"
    @State private var arrivalQuery = ""
    @State private var departureSuggestions: [MKMapItem] = []
    @State private var arrivalSuggestions: [MKMapItem] = []
    @State private var selectedDeparture: MKMapItem?
    @State private var selectedArrival: MKMapItem?
    @State private var recentPlaces: [HomeRouteRecentPlace] = HomeRouteRecentStore.load()
    @State private var savedPlaces: [HomeRouteSavedPlaceKind: HomeRouteRecentPlace] = HomeRouteSavedPlaceStore.load()
    @State private var pendingSavedPlace: HomeRouteSavedPlaceKind?
    @State private var isApplyingSelection = false
    @State private var searchTask: Task<Void, Never>?
    @State private var isResolving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: PlannerField?

    private enum PlannerField: Hashable {
        case departure
        case arrival
    }

    private let brussels = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    private var activeSuggestions: [MKMapItem] {
        focusedField == .departure ? departureSuggestions : arrivalSuggestions
    }

    private var isEditingDestination: Bool {
        focusedField == .arrival && !arrivalQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerRow
                    quickPlaces
                    routeFieldsCard

                    if !activeSuggestions.isEmpty {
                        suggestionsSection
                    } else if !isEditingDestination {
                        recentSection
                    }

                    if let errorMessage {
                        Text(errorMessage)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.statusMajor)
                            .padding(.horizontal, 4)
                    }
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 128)
            }
            .background(DS.Color.paper.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                bottomAction
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                focusedField = .arrival
            }
        }
        .preferredColorScheme(.light)
    }

    /// Lightweight header (back button + screen title). We dropped the
    /// previous full TextField search bar because it was bound to the same
    /// `$arrivalQuery` as the arrival row of the route card below — typing
    /// in one made the other echo it, which felt like a duplicate input.
    /// All typing now happens in the route card.
    private var headerRow: some View {
        HStack(spacing: 12) {
            Button {
                isPresented = false
            } label: {
                Image(systemName: "chevron.left")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
            }
            .buttonStyle(.plain)

            Text("Itinéraire")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Color.ink)

            Spacer()
        }
    }

    private var quickPlaces: some View {
        HStack(spacing: 18) {
            quickPlaceButton(
                icon: "house.fill",
                title: "Domicile",
                subtitle: savedPlaces[.home]?.subtitle ?? "Ajouter",
                isConfigured: savedPlaces[.home] != nil
            ) {
                useSavedPlace(.home)
            }
            quickPlaceButton(
                icon: "briefcase.fill",
                title: "Travail",
                subtitle: savedPlaces[.work]?.subtitle ?? "Ajouter",
                isConfigured: savedPlaces[.work] != nil
            ) {
                useSavedPlace(.work)
            }
            quickPlaceButton(icon: "ellipsis", title: "Plus", subtitle: "Adresses", isConfigured: true) {
                focusedField = .arrival
                pendingSavedPlace = nil
            }
        }
        .padding(.top, 8)
    }

    private func quickPlaceButton(icon: String, title: String, subtitle: String, isConfigured: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 42, height: 42)
                    .background(DS.Color.community.opacity(0.14))
                    .clipShape(Circle())
                VStack(alignment: .leading, spacing: 1) {
                    Text(title)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text(subtitle)
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(isConfigured ? DS.Color.inkMute : DS.Color.primary)
                        .lineLimit(1)
                }
            }
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var routeFieldsCard: some View {
        VStack(spacing: 0) {
            routeFieldRow(
                field: .departure,
                icon: "location.fill",
                text: $departureQuery,
                placeholder: "Adresse de départ",
                tint: DS.Color.community
            )

            HStack(spacing: 12) {
                VStack(spacing: 4) {
                    Circle().fill(DS.Color.inkMute.opacity(0.35)).frame(width: 3, height: 3)
                    Circle().fill(DS.Color.inkMute.opacity(0.35)).frame(width: 3, height: 3)
                    Circle().fill(DS.Color.inkMute.opacity(0.35)).frame(width: 3, height: 3)
                }
                .frame(width: 42)

                Rectangle()
                    .fill(DS.Color.ink.opacity(0.10))
                    .frame(height: 1)

                Button(action: swapRouteFields) {
                    Image(systemName: "arrow.up.arrow.down")
                        .font(.system(size: 17, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 42, height: 42)
                        .background(DS.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(DS.Color.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
            .padding(.leading, 6)
            .padding(.trailing, 10)

            routeFieldRow(
                field: .arrival,
                icon: "mappin.circle.fill",
                text: $arrivalQuery,
                placeholder: "Destination",
                tint: DS.Color.primary
            )
        }
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
        .shadow(DS.Shadow.floating)
    }

    private func routeFieldRow(
        field: PlannerField,
        icon: String,
        text: Binding<String>,
        placeholder: String,
        tint: Color
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 42, height: 42)

            TextField("", text: text, prompt: Text(placeholder).foregroundStyle(DS.Color.inkMute))
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
                .focused($focusedField, equals: field)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.search)
                .onSubmit {
                    if field == .departure {
                        focusedField = .arrival
                    } else {
                        Task { await submit() }
                    }
                }
                .onChange(of: text.wrappedValue) { _, newValue in
                    guard !isApplyingSelection else { return }
                    if field == .departure {
                        selectedDeparture = nil
                    } else {
                        selectedArrival = nil
                    }
                    handleQueryChange(newValue, for: field)
                }

            if !text.wrappedValue.isEmpty && !(field == .departure && text.wrappedValue == "Votre position") {
                Button {
                    clearField(field)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 58)
    }

    private var suggestionsSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Résultats")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .padding(.bottom, 8)

            ForEach(activeSuggestions, id: \.self) { item in
                Button {
                    selectSuggestion(item)
                } label: {
                    placeRow(
                        icon: "mappin.and.ellipse",
                        iconTint: DS.Color.primary,
                        title: item.name ?? "Adresse",
                        subtitle: item.placemark.title ?? "Bruxelles"
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var recentSection: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Récent")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .padding(.bottom, 8)

            if recentPlaces.isEmpty {
                placeRow(
                    icon: "clock",
                    iconTint: DS.Color.inkMute,
                    title: "Aucune recherche récente",
                    subtitle: "Tes derniers itinéraires apparaîtront ici."
                )
                .opacity(0.72)
            } else {
                ForEach(recentPlaces) { place in
                    Button {
                        selectRecent(place)
                    } label: {
                        placeRow(
                            icon: place.kind == .stop ? "tram.fill" : "clock",
                            iconTint: place.kind == .stop ? DS.Color.community : DS.Color.inkMute,
                            title: place.title,
                            subtitle: place.subtitle
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func placeRow(icon: String, iconTint: Color, title: String, subtitle: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(iconTint)
                .frame(width: 42, height: 42)
                .background(DS.Color.paper2)
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 19, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Text(subtitle)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(2)
            }

            Spacer()
        }
        .padding(.vertical, 13)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.ink.opacity(0.10))
                .frame(height: 1)
                .padding(.leading, 56)
        }
    }

    private var bottomAction: some View {
        VStack(spacing: 10) {
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 10) {
                    if isResolving || isRouting {
                        ProgressView()
                            .tint(DS.Color.primaryForeground)
                    } else {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 16, weight: .bold))
                    }

                    Text("Voir les itinéraires")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .buttonStyle(DS.PrimaryButtonStyle())
            .disabled(!canSubmit || isResolving || isRouting)
            .opacity(canSubmit ? 1 : 0.45)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var canSubmit: Bool {
        let arrivalReady = selectedArrival != nil
        let departureReady = selectedDeparture != nil
            || userCoordinate != nil
            || departureQuery.trimmingCharacters(in: .whitespacesAndNewlines) == "Votre position"
        return arrivalReady && departureReady
    }

    private func handleQueryChange(_ value: String, for field: PlannerField) {
        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !(field == .departure && trimmed == "Votre position") else {
            if field == .departure {
                departureSuggestions = []
            } else {
                arrivalSuggestions = []
            }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 230_000_000)
            guard !Task.isCancelled else { return }
            let results = await searchSuggestions(for: trimmed)
            await MainActor.run {
                if field == .departure {
                    departureSuggestions = results
                } else {
                    arrivalSuggestions = results
                }
            }
        }
    }

    private func clearField(_ field: PlannerField) {
        if field == .departure {
            departureQuery = ""
            selectedDeparture = nil
            departureSuggestions = []
        } else {
            arrivalQuery = ""
            selectedArrival = nil
            arrivalSuggestions = []
            pendingSavedPlace = nil
        }
        focusedField = field
    }

    private func selectSuggestion(_ item: MKMapItem) {
        applySelectionChange {
            if focusedField == .departure {
                selectedDeparture = item
                departureQuery = item.name ?? item.placemark.title ?? ""
                departureSuggestions = []
                focusedField = .arrival
            } else {
                selectedArrival = item
                arrivalQuery = item.name ?? item.placemark.title ?? ""
                arrivalSuggestions = []
                focusedField = nil
                if let pendingSavedPlace {
                    saveSavedPlace(item, kind: pendingSavedPlace)
                    self.pendingSavedPlace = nil
                }
                saveRecent(item)
            }
        }
    }

    private func selectRecent(_ place: HomeRouteRecentPlace) {
        applySelectionChange {
            let item = place.mapItem
            selectedArrival = item
            arrivalQuery = place.title
            arrivalSuggestions = []
            focusedField = nil
        }
    }

    private func swapRouteFields() {
        guard arrivalQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false else { return }
        applySelectionChange {
            let oldDepartureQuery = departureQuery
            let oldDeparture = selectedDeparture
            departureQuery = arrivalQuery
            selectedDeparture = selectedArrival
            arrivalQuery = oldDepartureQuery == "Votre position" ? "" : oldDepartureQuery
            selectedArrival = oldDeparture
            focusedField = arrivalQuery.isEmpty ? .arrival : nil
            pendingSavedPlace = nil
        }
    }

    @MainActor
    private func submit() async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        guard let destination = selectedArrival else {
            errorMessage = "Choisis une adresse dans les résultats pour éviter un mauvais itinéraire."
            focusedField = .arrival
            return
        }

        let source: MKMapItem
        let originName: String
        let trimmedDeparture = departureQuery.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedDeparture.isEmpty || trimmedDeparture == "Votre position" {
            guard let userCoordinate else {
                errorMessage = "Position actuelle indisponible."
                focusedField = .departure
                return
            }
            source = MKMapItem(placemark: MKPlacemark(coordinate: userCoordinate))
            source.name = "Votre position"
            originName = "Votre position"
        } else if let selectedDeparture {
            source = selectedDeparture
            originName = selectedDeparture.name ?? selectedDeparture.placemark.title ?? "Départ"
        } else {
            errorMessage = "Choisis une adresse de départ dans les résultats."
            focusedField = .departure
            return
        }

        saveRecent(destination)
        isPresented = false
        onPlanRoute(source, destination, originName)
    }

    private func searchSuggestions(for text: String) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: brussels,
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )

        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }

        var unique: [MKMapItem] = []
        var seen = Set<String>()
        for item in response.mapItems {
            let key = "\(item.name ?? "")|\(item.placemark.title ?? "")"
            if seen.insert(key).inserted {
                unique.append(item)
            }
        }
        return Array(unique.prefix(8))
    }

    private func resolve(query: String) async -> MKMapItem? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return await searchSuggestions(for: trimmed).first
    }

    private func saveRecent(_ item: MKMapItem) {
        let recent = HomeRouteRecentPlace(item: item)
        recentPlaces = HomeRouteRecentStore.prepending(recent, to: recentPlaces)
        HomeRouteRecentStore.save(recentPlaces)
    }

    private func useSavedPlace(_ kind: HomeRouteSavedPlaceKind) {
        if let place = savedPlaces[kind] {
            applySelectionChange {
                selectedArrival = place.mapItem
                arrivalQuery = place.title
                arrivalSuggestions = []
                pendingSavedPlace = nil
                focusedField = nil
            }
        } else {
            selectedArrival = nil
            arrivalQuery = ""
            arrivalSuggestions = []
            pendingSavedPlace = kind
            focusedField = .arrival
            errorMessage = "Recherche puis sélectionne ton \(kind.label.lowercased()) pour l’enregistrer."
        }
    }

    private func saveSavedPlace(_ item: MKMapItem, kind: HomeRouteSavedPlaceKind) {
        savedPlaces[kind] = HomeRouteRecentPlace(item: item)
        HomeRouteSavedPlaceStore.save(savedPlaces)
        errorMessage = "\(kind.label) enregistré."
    }

    private func applySelectionChange(_ updates: () -> Void) {
        isApplyingSelection = true
        updates()
        DispatchQueue.main.async {
            isApplyingSelection = false
        }
    }
}

private enum HomeRouteSavedPlaceKind: String, Codable, CaseIterable, Hashable {
    case home
    case work

    var label: String {
        switch self {
        case .home: return "Domicile"
        case .work: return "Travail"
        }
    }
}

private struct HomeRouteRecentPlace: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case place
        case stop
    }

    let id: String
    let title: String
    let subtitle: String
    let latitude: Double
    let longitude: Double
    let kind: Kind

    init(item: MKMapItem) {
        let coordinate = item.placemark.coordinate
        self.id = "\(coordinate.latitude)-\(coordinate.longitude)-\(item.name ?? item.placemark.title ?? "place")"
        self.title = item.name ?? item.placemark.title ?? "Adresse"
        self.subtitle = item.placemark.title ?? "Bruxelles"
        self.latitude = coordinate.latitude
        self.longitude = coordinate.longitude
        self.kind = .place
    }

    var mapItem: MKMapItem {
        let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        let item = MKMapItem(placemark: MKPlacemark(coordinate: coordinate))
        item.name = title
        return item
    }
}

private enum HomeRouteRecentStore {
    private static let key = "home.route.recent.places.v1"

    static func load() -> [HomeRouteRecentPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([HomeRouteRecentPlace].self, from: data) else {
            return []
        }
        return decoded
    }

    static func save(_ places: [HomeRouteRecentPlace]) {
        guard let data = try? JSONEncoder().encode(Array(places.prefix(12))) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }

    static func prepending(_ place: HomeRouteRecentPlace, to places: [HomeRouteRecentPlace]) -> [HomeRouteRecentPlace] {
        var next = places.filter { $0.id != place.id }
        next.insert(place, at: 0)
        return Array(next.prefix(12))
    }
}

private enum HomeRouteSavedPlaceStore {
    private static let key = "home.route.saved.places.v1"

    static func load() -> [HomeRouteSavedPlaceKind: HomeRouteRecentPlace] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode([String: HomeRouteRecentPlace].self, from: data) else {
            return [:]
        }

        return decoded.reduce(into: [:]) { result, entry in
            guard let kind = HomeRouteSavedPlaceKind(rawValue: entry.key) else { return }
            result[kind] = entry.value
        }
    }

    static func save(_ places: [HomeRouteSavedPlaceKind: HomeRouteRecentPlace]) {
        let encodable = places.reduce(into: [String: HomeRouteRecentPlace]()) { result, entry in
            result[entry.key.rawValue] = entry.value
        }
        guard let data = try? JSONEncoder().encode(encodable) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}
