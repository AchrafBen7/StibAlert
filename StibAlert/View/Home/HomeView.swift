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
    }

    private enum HomeSurfaceMode: Equatable {
        case unavailable
        case stopDetail
        case routeDetail
        case routePreview
        case stopPreview
        case signalementPreview
        case mapIdle
    }

    @EnvironmentObject var nav: AppNavigation
    // internal (not private) — utilisé par l'extension HomeViewOverlays
    // pour le commuteOverlay (Smart Commute LITE).
    @EnvironmentObject var session: AuthSession
    @EnvironmentObject private var connectivity: NetworkConnectivityMonitor
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @StateObject var locationManager = HomeLocationManager()
    @StateObject private var realtimeSignalements = SignalementsRealtimeService()
    @StateObject var vehicleTracker = VehicleTrackingService()
    @ObservedObject private var lineShapesLoader = LineShapesLoader.shared
    @ObservedObject private var gareFavorites = SNCBGareFavorites.shared
    @ObservedObject private var operatorFavorites = OperatorStopFavorites.shared

    @State private var mapPosition: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )
    @State private var showSearch = false
    @State var showLegend = false
    @State var showRoutePlanner = false
    @State private var showStibAI = false
    @State private var showVoiceOverlay = false
    @StateObject var tripTracker = ActiveTripTracker()
    @State var selectedSignalementPreview: SignalementDTO? = nil
    @State private var lastFetchedAt: Date? = nil
    @State private var currentRoute: MKRoute? = nil
    @State private var currentRouteCoordinates: [CLLocationCoordinate2D] = []
    @State private var destinationCoord: CLLocationCoordinate2D? = nil
    @State private var routeOverlayRevision = 0
    // internal — utilisé par l'extension HomeViewOverlays (commuteOverlay
    // n'affiche pas la card si une route est déjà sélectionnée).
    @State var routeOptions: [HomeRouteOption] = []
    @State private var routeModeSummaries: [RouteModeSummary] = []
    @State private var selectedRouteID: UUID?
    @State private var isRouteSheetExpanded = false
    @State private var selectedRouteDetail: HomeRouteOption?
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
    @State var selectedMapStopPreview: TransportStopSummaryDTO?
    @State var selectedMapStopSummary: TransportStopSummaryDTO?
    @State var selectedMapStopDetail: TransportStopDTO?
    @State var selectedStopLineNumber: String?
    @State var isLoadingMapStopDetail = false
    // C5 — 200 ms debounce sur les taps de markers/clusters carte. Évite
    // que 2 sheets se superposent quand le user re-tap pendant le fetch.
    @State private var mapTapLockedUntil: Date?
    @State private var mapStopDetailError: String?
    @State private var eventImpacts: [TransportEventImpactDTO] = []
    @State private var selectedEventImpact: TransportEventImpactDTO?
    // S1 — Toggles persistants via @AppStorage. Avant : @State remis à
    // true à chaque mount de HomeView → user qui décochait Villo se
    // retrouvait avec Villo affiché à la prochaine session. Désormais
    // mémorisé entre les launches.
    @AppStorage(AppStorageKeys.mapLayerShowVilloStations) private var showVilloStations = true
    @AppStorage(AppStorageKeys.mapLayerShowEventImpacts) private var showEventImpacts = true
    @AppStorage(AppStorageKeys.mapLayerShowStibStops) private var showStibStops = true
    @AppStorage(AppStorageKeys.mapLayerShowSncbStations) private var showSncbStations = true
    @State private var selectedVilloStation: VilloStation?
    @State private var selectedSncbStation: SNCBStation?
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
    @State private var cameraLongitudeDelta: Double = 0.04
    @State private var catalogMapStops: [NearbyStop] = []
    @State private var mapStopsTask: Task<Void, Never>? = nil
    // De Lijn / TEC stops are fetched by viewport (≈30k each — too many to bundle).
    @State private var operatorMapStops: [OperatorMapStop] = []
    @State private var operatorStopsTask: Task<Void, Never>? = nil
    @State private var lastOperatorStopsCoordinate: CLLocationCoordinate2D? = nil
    @State private var selectedOperatorStop: OperatorMapStop? = nil
    @AppStorage(AppStorageKeys.mapLayerShowDelijnStops) private var showDelijnStops = true
    @AppStorage(AppStorageKeys.mapLayerShowTecStops) private var showTecStops = true
    @AppStorage(AppStorageKeys.commuteNudgeDismissed) var commuteNudgeDismissed = false
    @State private var interactionMode: InteractionMode = .map

    @State private var activeClusters: [ClusterDTO] = []
    @State var selectedClusterIndex: Int? = nil
    @State var selectedVehicle: TransportVehicleDTO? = nil

    /// Session-long cache: STIB direction code → human terminus name.
    /// Built incrementally from observed `nextDepartures` at every stop the
    /// user opens (cf. `learnDirectionTerminus(for:)`). Survives across stop
    /// changes so a tram tapped at BUISSONNETS still knows it goes to
    /// VANDERKINDERE because we learned that mapping at a previous stop.
    @State var directionTerminusCache: [String: String] = [:]
    @State private var clustersTask: Task<Void, Never>? = nil
    @State private var lastClustersFetchCoordinate: CLLocationCoordinate2D? = nil

    @State private var hasAutoShownDecision = false
    @State var proactiveAlertCluster: ClusterDTO? = nil
    @State var tripDestination: TripDestination? = nil
    @State private var showDestinationPicker = false
    /// Trip prepared from the voice flow (geocoded + planned), kept around so
    /// the "Voir la route sur la carte" button can apply it instantly without
    /// re-running MKLocalSearch + the planner.
    @State private var pendingVoiceTrip: (destination: MKMapItem, options: [HomeRouteOption])?

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
        // Apply the user's problem-type filter and ALSO drop reports whose
        // time-decayed confidence has rotted below 0.18. Without this, a
        // 6-hour-old "Incivilité" stays pinned to the map indefinitely; the
        // half-life formula in `SignalementDTO.liveConfidence` lets the map
        // self-clean as reports age out by category.
        // Note: official STIB signals bypass the confidence floor — STIB
        // disruptions are authoritative and shouldn't be hidden by client
        // heuristics.
        let typeMatched: [SignalementDTO]
        if let filter = problemFilter {
            typeMatched = remoteSignalements.filter { $0.typeProbleme == filter.title }
        } else {
            typeMatched = remoteSignalements
        }
        return typeMatched.filter { s in
            if s.source?.lowercased().contains("stib") == true { return true }
            return s.liveConfidence >= 0.18
        }
    }

    private var liveSignalPoints: [LiveSignalPoint] {
        let normalized = selectedStopLineNumber.map(normalizedLineNumber)
        return filteredSignalements.compactMap { s in
            guard let lat = s.latitude, let lng = s.longitude else { return nil }
            // C3 — Focus mode : on ne filtre PAS les signalements OFFICIELS
            // STIB (source == stib_officiel) car ce sont des perturbations
            // autoritaires (grèves, accidents majeurs) que l'utilisateur DOIT
            // voir même en focus mode. Avant : un signalement officiel sur
            // une autre ligne disparaissait silencieusement → l'utilisateur
            // croyait "tout va bien" alors qu'une grève bloquait le réseau.
            let isOfficial = s.source?.lowercased() == "stib_officiel"
            if let normalized, !isOfficial,
               normalizedLineNumber(s.ligne) != normalized {
                return nil
            }
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
        // Hide community clusters entirely in focus mode — keeping them would
        // re-introduce noise we just stripped from the rest of the map.
        guard !isFocusModeActive else { return [] }
        let communityPoints = liveSignalPoints.filter { $0.source != "stib_officiel" }
        return MapSignalClusterer.cluster(
            points: communityPoints.map { MapSignalClusterer.Input(id: $0.id, coordinate: $0.coordinate, typeProbleme: $0.typeProbleme, origin: .community) },
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
        // Route preview wins — we want the single tracked vehicle for that trip.
        if let selectedRouteOption {
            return Set(selectedRouteOption.displayLineCodes)
        }
        // Otherwise, when the user has focused a line through the mini stop
        // card, poll vehicle positions for that whole line so we can render
        // the tram/bus icons on its tracé.
        if let selectedStopLineNumber {
            return [selectedStopLineNumber]
        }
        return []
    }

    private var visibleLineShapes: [LineShape] {
        // Tracés de lignes désactivés en affichage permanent : ils
        // surchargeaient la carte (toutes les lignes visibles tracées au zoom)
        // et la ralentissaient pour peu de valeur. On ne montre plus le tracé
        // d'une ligne QUE lorsqu'un arrêt est sélectionné (selectedStopLineShapes).
        // Le loader reste actif pour ce cas et pour les itinéraires.
        return []
    }

    private var selectedStopLineShapes: [LineShape] {
        guard selectedRouteOption == nil, let selectedStopLineNumber else { return [] }
        return lineShapesLoader.shapes(matchingNumbers: [selectedStopLineNumber])
    }

    private var mapVehicles: [TransportVehicleDTO] {
        if let selectedRouteOption {
            guard cameraLatitudeDelta <= 0.12 else { return [] }
            if let trackedVehicle = trackedVehicle(for: selectedRouteOption) {
                return [trackedVehicle]
            }
            return []
        }
        // Mini stop card focus mode — show every vehicle the tracker reports
        // for the focused line so the user can watch them move along the tracé.
        // No zoom guard here: the whole point of the focus mode is "show me
        // where the trams are right now", even when the line spans Brussels.
        if selectedStopLineNumber != nil {
            return vehicleTracker.vehicles.filter {
                $0.latitude != nil && $0.longitude != nil
            }
        }
        return []
    }

    /// Lignes considérées BLOQUÉES en direct par la communauté + l'officiel,
    /// injectées dans le calcul d'itinéraire (`recommendRoute(lignesBloquees:)`)
    /// pour FERMER LA BOUCLE Waze : un signalement fiable réroute réellement,
    /// au lieu d'être un simple badge sur la carte.
    ///
    /// On ne retient QUE les clusters assez fiables pour justifier un détour —
    /// sinon une seule rumeur "à vérifier" exclurait une ligne à tort :
    ///   • officiel STIB, OU
    ///   • confiance medium/high, OU statut "confirmed",
    ///   • non résolus.
    /// Les types non bloquants (propreté, incivilité) n'excluent pas la ligne :
    /// seuls les incidents qui empêchent le trajet comptent.
    private var liveBlockedLines: [String] {
        let blockingTypes: Set<String> = [
            "panne", "interruption", "accident", "travaux", "déviation",
            "perturbation", "arrêt non desservi",
        ]
        var lines = Set<String>()
        for cluster in activeClusters {
            guard !cluster.resolved, cluster.status != "resolved" else { continue }
            let reliable = cluster.isOfficial
                || cluster.confidence == .high
                || cluster.confidence == .medium
                || cluster.confidenceStatus == "confirmed"
            guard reliable else { continue }
            // Type bloquant uniquement (un "propreté" ne ferme pas la ligne).
            let type = cluster.typeProbleme.lowercased()
            guard cluster.isOfficial || blockingTypes.contains(type) else { continue }
            let code = normalizedLineNumber(cluster.ligne)
            if !code.isEmpty { lines.insert(code) }
        }
        return Array(lines)
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
        // Focus mode: hide every stop pin so the map shows only the line
        // tracé + its live vehicles. The user's selected stop is still
        // implicit at the centre of the camera, and the search header card
        // already names it.
        if isFocusModeActive {
            return []
        }

        return baseMapStops
    }

    /// True when the user has tapped a stop and we're showing the mini header
    /// card. We use this to strip the map of everything that's not the
    /// focused line (signalements, villo, clusters, other-line stops, etc.).
    private var isFocusModeActive: Bool {
        selectedRouteOption == nil && selectedStopLineNumber != nil
    }

    /// Quantized user-latitude bucket (≈110 m per integer step). Used as a
    /// stable `.task(id:)` so the offline-tile refresher does not re-fire on
    /// every GPS update — only when the user has actually moved ~100 m.
    private var coarseUserLatitudeBucket: Int? {
        guard let lat = locationManager.userCoordinate?.latitude else { return nil }
        return Int(lat * 1000)
    }

    /// Mapping from STIB direction code (e.g. "9051") to the human terminus
    /// name (e.g. "VANDERKINDERE"). Backed by `directionTerminusCache`, which
    /// is filled progressively by `learnDirectionTerminus(for:)` every time
    /// a stop is loaded — so even at one-way loop stops (BUISSONNETS) the
    /// vehicle popup can still label trams going the other way once we've
    /// seen the mapping at any bidirectional stop on the line.
    var vehicleDestinationByDirection: [String: String] {
        directionTerminusCache
    }

    /// Update the global direction→terminus cache from a freshly-loaded
    /// stop detail. The rule: if a tracked vehicle is currently AT this
    /// stop (or within 80 m) with direction code X, and the stop's
    /// nextDepartures show line L going to destination D, then X → D.
    @MainActor
    private func learnDirectionTerminus(for detail: TransportStopDTO) {
        let stopName = detail.stop.name.uppercased()
        let stopCoord: CLLocation? = {
            guard let lat = detail.stop.latitude, let lng = detail.stop.longitude else { return nil }
            return CLLocation(latitude: lat, longitude: lng)
        }()
        var learned = directionTerminusCache
        for departure in detail.nextDepartures {
            guard let destination = departure.destination?
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .uppercased(), !destination.isEmpty else { continue }
            let lineNorm = normalizedLineNumber(departure.line)
            let matchingVehicle = vehicleTracker.vehicles.first { v in
                guard let vLine = v.line, normalizedLineNumber(vLine) == lineNorm else { return false }
                if v.stopNom?.uppercased() == stopName { return true }
                if let stopCoord, let vLat = v.latitude, let vLng = v.longitude {
                    return stopCoord.distance(from: CLLocation(latitude: vLat, longitude: vLng)) <= 80
                }
                return false
            }
            if let direction = matchingVehicle?.direction, learned[direction] != destination {
                learned[direction] = destination
            }
        }
        if learned != directionTerminusCache {
            directionTerminusCache = learned
        }
    }

    /// The user's saved favourite stops as map annotations.
    private var favoriteMapStops: [TransportStopSummaryDTO] {
        (session.currentUser?.favorisDetails ?? []).compactMap { fav in
            guard let lat = fav.latitude, let lng = fav.longitude else { return nil }
            return TransportStopSummaryDTO(
                id: fav.id,
                stopId: nil,
                name: fav.nom,
                latitude: lat,
                longitude: lng,
                lines: fav.lignesDesservies ?? []
            )
        }
    }

    /// Backend stop ids the user has favourited — drives the star + larger
    /// marker on the map.
    private var favoriteStopIds: Set<String> {
        Set((session.currentUser?.favorisDetails ?? []).map(\.id))
    }

    private var favoriteGareIds: Set<String> { gareFavorites.ids }

    private var favoriteOperatorStopKeys: Set<String> {
        Set(operatorFavorites.stops.map(\.id))
    }

    private var favoriteOperatorMapStops: [OperatorMapStop] {
        operatorFavorites.stops.map {
            OperatorMapStop(
                id: $0.stopId,
                name: $0.name,
                lat: $0.lat,
                lng: $0.lng,
                op: $0.operatorType
            )
        }
    }

    /// Favourite stops are always on the map (starred), unioned on top of the
    /// regular zoom-gated set so they show even when zoomed out / layer-filtered.
    private var baseMapStops: [TransportStopSummaryDTO] {
        let favorites = favoriteMapStops
        let regular = regularMapStops
        guard !favorites.isEmpty else { return regular }
        var seen = Set(favorites.map(\.id))
        return favorites + regular.filter { seen.insert($0.id).inserted }
    }

    private var regularMapStops: [TransportStopSummaryDTO] {
        // Favourites filter: show the user's saved stops regardless of zoom
        // (few markers → no clutter). This is "montre-moi mes favoris".
        if activeMapFilter == .favorites { return favoriteMapStops }
        // Legend layer toggle.
        guard showStibStops else { return [] }
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

        // Perf zoom — plafonne le nombre de pins. MapKit re-layoute TOUTES les
        // annotations à la fin d'un geste de zoom ; au-delà de ~70 stops le
        // geste saccade. On garde les plus proches du centre de la caméra
        // (distance Manhattan, suffisante pour un classement et sans alloc).
        let cappedMerged = Self.capNearest(merged, to: cameraCenterCoordinate, limit: 70)

        switch activeMapFilter {
        case .favorites:
            // Handled at the top of baseMapStops (favoriteMapStops); kept for
            // switch exhaustiveness.
            return favoriteMapStops
        case .perturbations:
            let affectedLines = Set(remoteSignalements.filter { $0.status != "resolved" }.map { $0.ligne })
            guard !affectedLines.isEmpty else { return cappedMerged }
            return cappedMerged.filter { !$0.lines.filter { affectedLines.contains($0) }.isEmpty }
        case .none:
            return cappedMerged
        }
    }

    /// Garde les `limit` arrêts les plus proches du centre caméra (cap de rendu).
    private static func capNearest(_ stops: [TransportStopSummaryDTO], to center: CLLocationCoordinate2D, limit: Int) -> [TransportStopSummaryDTO] {
        guard stops.count > limit else { return stops }
        return stops.sorted { a, b in
            let da = abs((a.latitude ?? 0) - center.latitude) + abs((a.longitude ?? 0) - center.longitude)
            let db = abs((b.latitude ?? 0) - center.latitude) + abs((b.longitude ?? 0) - center.longitude)
            return da < db
        }.prefix(limit).map { $0 }
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
        guard !isFocusModeActive else { return [] }
        guard showVilloStations, cameraLatitudeDelta <= 0.03 else { return [] }
        return VilloStationService.nearbyStations(
            around: locationManager.displayCoordinate,
            radiusMeters: 1800,
            limit: 30 // PERF — moins d'annotations Villo à composer (chauffe).
        ).map(\.station)
    }

    private var mapSncbStations: [SNCBStation] {
        guard !isFocusModeActive else { return [] }
        // Favourite gares are always shown (starred), regardless of zoom.
        let favorites = gareFavorites.stations
        if activeMapFilter == .favorites { return favorites }
        guard showSncbStations else { return [] }
        // Same zoom gate as STIB stops (mapStops) so non-favourite gares only
        // appear once you're zoomed in — otherwise the network crowds the map.
        let zoomed = cameraLatitudeDelta <= 0.07
            ? SNCBStationService.mapStations(around: cameraCenterCoordinate, cameraLatitudeDelta: cameraLatitudeDelta)
            : []
        guard !favorites.isEmpty else { return zoomed }
        var seen = Set<String>()
        return (favorites + zoomed).filter { seen.insert($0.id).inserted }
    }

    /// De Lijn / TEC stops to render — viewport-fetched and gated to a *deeper*
    /// zoom than STIB/SNCB (these networks have ~30k stops each, so they only
    /// appear once the user is really zoomed in).
    private var mapOperatorStops: [OperatorMapStop] {
        guard !isFocusModeActive else { return [] }
        let favorites = favoriteOperatorMapStops
        if activeMapFilter == .favorites { return favorites }
        guard cameraLatitudeDelta <= 0.018 else { return favorites }
        let regular = operatorMapStops.filter {
            ($0.op == .delijn && showDelijnStops) || ($0.op == .tec && showTecStops)
        }
        guard !favorites.isEmpty else { return regular }
        var seen = Set(favorites.map { "\($0.op.rawValue):\($0.id)" })
        return favorites + regular.filter { seen.insert("\($0.op.rawValue):\($0.id)").inserted }
    }

    private var mapEventImpacts: [TransportEventImpactDTO] {
        guard !isFocusModeActive else { return [] }
        // S2 — gate resserré de 0.14 → 0.07 : à zoom moyen (0.05-0.07) les
        // événements (concerts, matchs) se mélangeaient aux stops STIB et
        // signalements. À 0.07 et en dessous (vue Bruxelles centre), ils
        // restent visibles ; au-delà ils disparaissent au profit de la
        // hiérarchie réseau.
        guard showEventImpacts, cameraLatitudeDelta <= 0.07 else { return [] }
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
        !routeOptions.isEmpty || selectedRouteDetail != nil
    }

    private var homeSurfaceMode: HomeSurfaceMode {
        guard isHomeSurfaceInteractive else { return .unavailable }
        if interactionMode == .stopDetail, selectedMapStopSummary != nil { return .stopDetail }
        if interactionMode == .routeDetail, selectedRouteDetail != nil { return .routeDetail }
        if interactionMode == .routePreview, !routeOptions.isEmpty { return .routePreview }
        if interactionMode == .stopPreview, selectedMapStopPreview != nil, selectedMapStopSummary == nil { return .stopPreview }
        if selectedSignalementPreview != nil, !showLegend, routeOptions.isEmpty { return .signalementPreview }
        return .mapIdle
    }

    var shouldShowSearchHeader: Bool {
        switch homeSurfaceMode {
        case .mapIdle, .routePreview, .signalementPreview, .stopPreview:
            // .stopPreview now renders a mini stop card *inside* the search
            // header overlay instead of the bottom preview sheet, so we keep
            // the header slot visible to host it.
            return true
        case .unavailable, .stopDetail, .routeDetail:
            return false
        }
    }

    var shouldShowSignalementPreview: Bool {
        homeSurfaceMode == .signalementPreview
    }

    var shouldShowPulseBar: Bool {
        // Hide the + floating button while the cluster sheet is open —
        // otherwise it overlaps the "C'est résolu" / "Toujours bloqué" CTAs
        // at the bottom of the cluster card.
        homeSurfaceMode == .mapIdle && selectedClusterIndex == nil
    }

    var shouldShowTabBar: Bool {
        !nav.showReportSheet
        && !isStopDetailPresented
        && !nav.hidesTabBar
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
        // Disabled — the big bottom preview card has been replaced by the
        // mini stop card embedded in the search header overlay. Set this back
        // to `homeSurfaceMode == .stopPreview` to restore the legacy sheet.
        false
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

    var transitionSpring: Animation {
        AppMotion.spring(reduceMotion: reduceMotion)
    }

    private var stibAILocationLabel: String {
        if let stop = selectedMapStopDetail?.stop.name ?? selectedMapStopPreview?.name {
            return "📍 \(stop)"
        }
        if locationManager.userCoordinate != nil {
            return "📍 autour de moi"
        }
        return "📍 localisation non active"
    }

    private var stibAIContextSnapshot: STIBAIContext {
        let position = locationManager.userCoordinate.map(GeoPoint.init)
        let currentStop = stibAICurrentStartStop()
        let nearby = stibAINearbyStops(currentStopId: currentStop?.id)
        let activeReports = remoteSignalements
            .filter { $0.status != "resolved" }
            .prefix(14)
            .map { signalement in
                CommunityReport(
                    line: signalement.ligne,
                    stop: arretName(for: signalement),
                    type: signalement.displayTypeProbleme,
                    ageMin: signalement.effectiveFreshnessMinutes
                )
            }

        let affectedLines = Array(Set(remoteSignalements.filter { $0.status != "resolved" }.map(\.ligne))).sorted()
        let overviewIncidents = (selectedMapStopDetail?.activeIncidents ?? transportOverview?.activeIncidents ?? [])

        return STIBAIContext(
            position: position,
            currentStartStop: currentStop,
            activeTrip: stibAIActiveTrip(),
            network: NetworkState(
                level: transportOverview?.severity ?? selectedMapStopDetail?.severity ?? "unknown",
                headline: transportOverview?.perturbationSummary?.shortText
                    ?? selectedMapStopDetail?.perturbationSummary?.shortText
                    ?? "Données réseau chargées depuis l'app.",
                affectedLines: affectedLines
            ),
            disruptedLines: affectedLines,
            travellersInfo: overviewIncidents.prefix(10).map { incident in
                TravellerInfo(
                    priority: nil,
                    type: incident.type,
                    title: incident.type ?? "Perturbation",
                    description: incident.description,
                    lines: incident.line.map { [$0] },
                    points: incident.stop?.id.map { [$0] }
                )
            },
            nearbyStops: nearby,
            followedLines: session.currentUser?.favoriteLines,
            reports: Array(activeReports),
            proposedDestination: selectedRouteOption?.destinationName,
            proposedRoutes: stibAIProposedRoutes()
        )
    }

    @MainActor
    private func stibAIContextSnapshot(for userMessage: String) async -> STIBAIContext {
        var context = stibAIContextSnapshot
        guard context.proposedRoutes == nil else { return context }

        // Fast path : regex client-side (gratuit, instantané).
        var destinationText = STIBAIDestinationExtractor.extract(from: userMessage)

        // Fallback : si le regex échoue ET que le message ressemble à une
        // demande d'itinéraire, on demande au backend (Gemini) d'extraire la
        // destination — bien plus tolérant aux phrasings exotiques. Sans
        // cette branche, l'IA refusait avec "j'ai besoin d'une destination
        // plus précise" sur les phrases que le regex ne capture pas.
        if destinationText == nil, Self.looksLikeTripRequest(userMessage) {
            destinationText = await STIBAIVoiceClient.extractDestinationOnly(text: userMessage, context: context)
        }

        guard let destinationText else { return context }

        context.proposedDestination = destinationText
        guard let destination = await resolveSTIBAIDestination(destinationText) else {
            return context
        }

        let options = await stibAIRouteOptions(to: destination)
        if let proposedRoutes = stibAIProposedRoutes(from: options) {
            context.proposedDestination = destination.name ?? destinationText
            context.proposedRoutes = proposedRoutes
        }
        return context
    }

    /// Heuristique pour limiter le fallback backend aux questions qui ont
    /// l'air d'une demande de trajet. Sans ça, "y a-t-il des perturbations ?"
    /// ferait un appel Gemini inutile à chaque message.
    private static func looksLikeTripRequest(_ text: String) -> Bool {
        let lower = text.lowercased()
        let triggers = [
            "aller", "trajet", "itinéraire", "itineraire", "route", "chemin",
            "rendre", "arriver", "amène", "amene", "meilleur", "comment je vais",
            "comment aller", "direction de", "se rendre", "y aller", "destination",
        ]
        return triggers.contains { lower.contains($0) }
    }

    private func stibAICurrentStartStop() -> NearStop? {
        if let detail = selectedMapStopDetail {
            return NearStop(
                id: detail.stop.id,
                name: detail.stop.name,
                distance: stibAIDistance(to: detail.stop),
                lines: detail.stop.lines,
                mode: stibAIMode(for: detail.stop.lines)
            )
        }
        if let preview = selectedMapStopPreview {
            return NearStop(
                id: preview.id,
                name: preview.name,
                distance: stibAIDistance(to: preview),
                lines: preview.lines,
                mode: stibAIMode(for: preview.lines)
            )
        }
        return stibAINearbyStops(currentStopId: nil).first
    }

    private func stibAINearbyStops(currentStopId: String?) -> [NearStop] {
        let coordinate = locationManager.userCoordinate ?? locationManager.displayCoordinate
        return baseMapStops
            .filter { summary in
                guard let lat = summary.latitude, let lng = summary.longitude else { return false }
                let distance = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
                    .distance(from: CLLocation(latitude: lat, longitude: lng))
                return distance <= 1800 || summary.id == currentStopId
            }
            .sorted { stibAIDistance(to: $0) < stibAIDistance(to: $1) }
            .prefix(8)
            .map { summary in
                NearStop(
                    id: summary.id,
                    name: summary.name,
                    distance: stibAIDistance(to: summary),
                    lines: summary.lines,
                    mode: stibAIMode(for: summary.lines)
                )
            }
    }

    private func stibAIActiveTrip() -> ActiveTrip? {
        guard let option = selectedRouteOption else { return nil }
        let steps = option.backendAlternative?.steps ?? []
        return ActiveTrip(
            fromName: option.originName,
            toName: option.destinationName,
            lines: Array(Set(steps.compactMap(\.line))).sorted(),
            stopIds: steps.compactMap(\.stopName)
        )
    }

    private func stibAIProposedRoutes() -> [ProposedRoute]? {
        let options = routeOptions.isEmpty ? selectedRouteOption.map { [$0] } ?? [] : routeOptions
        return stibAIProposedRoutes(from: options)
    }

    private func stibAIProposedRoutes(from options: [HomeRouteOption]) -> [ProposedRoute]? {
        guard !options.isEmpty else { return nil }
        return options.prefix(3).map { option in
            let backend = option.backendAlternative
            let steps = backend?.steps?.sorted { $0.order < $1.order }.map { step in
                RouteStep(
                    line: step.line,
                    fromName: step.stopName ?? step.instruction,
                    toName: step.arrivalStopName ?? step.destination ?? option.destinationName,
                    minutes: step.durationMinutes,
                    disrupted: !(step.alerts ?? []).isEmpty,
                    reason: step.alerts?.first?.description ?? step.alerts?.first?.title
                )
            }
            return ProposedRoute(
                totalMin: backend?.totalDurationMinutes ?? Int(option.durationText.filter(\.isNumber)) ?? nil,
                walkMin: backend?.walkingMinutes,
                transitMin: backend.map { max($0.totalDurationMinutes - $0.walkingMinutes, 0) },
                fromStop: option.originName,
                toStop: option.destinationName,
                accessFromMeters: nil,
                accessToMeters: nil,
                steps: steps,
                transfers: backend?.transfers,
                hasDisruption: backend?.severity != "normal",
                disruptionReasons: backend?.officialAlerts?.compactMap { $0.description ?? $0.title },
                walkOnly: backend == nil && option.transitSummary.localizedCaseInsensitiveContains("pied"),
                info: [option.transitSummary, option.walkingSummary, option.reliabilityText]
            )
        }
    }

    private func stibAIDistance(to summary: TransportStopSummaryDTO) -> Double {
        guard let lat = summary.latitude, let lng = summary.longitude else { return 0 }
        let origin = locationManager.userCoordinate ?? locationManager.displayCoordinate
        return CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: lat, longitude: lng))
    }

    private func stibAIMode(for lines: [String]) -> String? {
        let normalized = lines.map { $0.uppercased() }
        if normalized.contains(where: { $0 == "1" || $0 == "2" || $0 == "5" || $0 == "6" }) { return "metro" }
        if normalized.contains(where: { $0.hasPrefix("T") || ["3", "4", "7", "8", "9", "10", "18", "19", "25", "39", "44", "51", "55", "62", "81", "82", "92", "93", "97"].contains($0) }) { return "tram" }
        return lines.isEmpty ? nil : "bus"
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
        .overlay(alignment: .top) { activeTripIndicatorOverlay }
        .overlay(alignment: .top) { commuteOverlay }
        .overlay(alignment: .top) { proactiveAlertOverlay }
        .overlay(alignment: .top) { allClearChipOverlay }
        .overlay(alignment: .bottom) { signalementPreviewOverlay }
        .overlay(alignment: .bottom) { clusterDetailOverlay }
        .overlay(alignment: .bottom) { vehicleDetailOverlay }
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
                    let coord = destination.placemark.coordinate
                    let label = destination.name ?? destination.placemark.title
                    tripDestination = HomeView.TripDestination(coordinate: coord, label: label)
                }
            )
        }
        .fullScreenCover(isPresented: $showStibAI) {
            STIBAIView(
                locationLabel: stibAILocationLabel,
                contextProvider: { message in
                    await stibAIContextSnapshot(for: message)
                },
                onClose: { showStibAI = false }
            )
        }
        .fullScreenCover(isPresented: $showVoiceOverlay) {
            VoiceOverlay(
                contextProvider: { message in
                    await stibAIContextSnapshot(for: message)
                },
                prepareTrip: { name in
                    await prepareVoiceTrip(name)
                },
                applyTrip: {
                    applyPreparedVoiceTrip()
                },
                onClose: {
                    pendingVoiceTrip = nil
                    showVoiceOverlay = false
                },
                onSwitchToText: {
                    // N12 — Si mic refusé, on ferme l'overlay vocal et on
                    // bascule sur la chat STIB·AI dans la foulée.
                    pendingVoiceTrip = nil
                    showVoiceOverlay = false
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 250_000_000)
                        showStibAI = true
                    }
                }
            )
        }
        .onReceive(locationManager.$userCoordinate) { coord in
            tripTracker.onLocationUpdate(coord)
        }
        .sheet(item: $selectedVilloStation) { station in
            HomeVilloStationSheet(station: station)
                .presentationDetents([.height(260), .medium])
                .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedSncbStation) { station in
            HomeSncbStationSheet(
                station: station,
                onReport: {
                    selectedSncbStation = nil
                    nav.showReportSheet = true
                }
            )
            .presentationDetents([.height(280), .medium])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedOperatorStop) { stop in
            HomeOperatorStopSheet(stop: stop, onReport: {
                selectedOperatorStop = nil
                nav.showReportSheet = true
            })
        }
        // .onChange fires when the user picks a destination in the route
        // planner ; we consume `tripDestination` immediately + lance buildRoute.
        .onChange(of: tripDestination) { _, destination in
            guard let destination else { return }
            tripDestination = nil
            let target = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate))
            target.name = destination.label ?? "Destination"
            Task { await buildRoute(to: target) }
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
            nav.hidesTabBar = false
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
            // Focus mode (stop mini-card) needs every tram on the line, not
            // just the ones within 1.5 km of the user. Route preview keeps the
            // proximity filter — it only tracks one specific vehicle anyway.
            vehicleTracker.proximityFilterEnabled = (selectedRouteOption != nil)
            vehicleTracker.updateLines(newLines)
        }
        .task { await loadRemoteSignalements() }
        .task { await loadEventImpacts() }
        .task { lineShapesLoader.loadIfNeeded() }
        .task { await refreshCatalogMapStops(force: true) }
        .task { await loadActiveClusters(around: cameraCenterCoordinate) }
        .task(id: coarseUserLatitudeBucket) {
            // Refresh offline map snapshot if user has moved significantly.
            // Runs only when connectivity is good (no point caching half-loaded tiles).
            // Using a quantized bucket (≈110 m grid) instead of raw lat avoids
            // the SwiftUI "onChange(of: Optional<Double>) tried to update
            // multiple times per frame" warning when the GPS reports many
            // updates per second.
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
            guard newValue == .home else { return }
            nav.hidesTabBar = false
            if nav.pendingMapStopFocusBackendId != nil {
                Task { await applyPendingMapStopFocusIfPossible() }
            }
        }
        .onChange(of: nav.pendingMapStopFocusBackendId) { _, newValue in
            guard nav.currentPage == .home, newValue != nil else { return }
            Task { await applyPendingMapStopFocusIfPossible() }
        }
        // BUG #3 — observe pendingClusterFocusIndex (set par AppRoot quand
        // un push communityCluster est tappé). On ouvre le ClusterDetailSheet
        // via le state existant selectedClusterIndex en s'assurant qu'on
        // close les autres bottom sheets d'abord (cf. mutex C1).
        .onChange(of: nav.pendingClusterFocusIndex) { _, newValue in
            guard let index = newValue else { return }
            dismissOtherBottomDetails(except: .cluster)
            withAnimation(transitionSpring) {
                selectedClusterIndex = index
            }
            nav.pendingClusterFocusIndex = nil
        }
        .onReceive(locationManager.$userCoordinate.compactMap { $0 }) { coord in
            if !hasAutoCenteredOnUser || isFollowingUser {
                suppressNextCameraInteraction = true
                withAnimation(.easeOut(duration: 0.35)) {
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
            routeOverlayRevision: routeOverlayRevision,
            destinationCoordinate: destinationCoord,
            // Focus mode strips every overlay from the map so the only
            // markers left are the focused line's stops and its live vehicles.
            officialSignalPoints: isFocusModeActive ? [] : officialSignalPoints,
            routeOfficialSignalPoints: routeOfficialSignalPoints,
            activeClusters: isFocusModeActive ? [] : activeClusters,
            selectedClusterIndex: selectedClusterIndex,
            cameraLatitudeDelta: cameraLatitudeDelta,
            mapVehicles: mapVehicles,
            vehicleBearings: vehicleTracker.vehicleBearings,
            mapStops: mapStops,
            favoriteStopIds: favoriteStopIds,
            favoriteGareIds: favoriteGareIds,
            favoriteOperatorStopKeys: favoriteOperatorStopKeys,
            selectedMapStopPreview: selectedMapStopPreview,
            selectedMapStopSummary: selectedMapStopSummary,
            loadingMapStopId: loadingMapStopId,
            mapSncbStations: mapSncbStations,
            selectedSncbStation: selectedSncbStation,
            mapOperatorStops: mapOperatorStops,
            mapVilloStations: mapVilloStations,
            mapEventImpacts: mapEventImpacts,
            onOpenPreview: openPreview(for:),
            onOpenStopPreview: openStopPreview(for:),
            onSelectCluster: { cluster in
                guard acquireMapTapLock() else { return }
                withAnimation(transitionSpring) {
                    dismissOtherBottomDetails(except: .cluster)
                    selectedClusterIndex = cluster.clusterIndex
                }
            },
            onSelectClusterCount: { center in
                zoomCameraIn(to: center, factor: 0.4)
            },
            onSelectSncbStation: { station in
                guard acquireMapTapLock() else { return }
                dismissOtherBottomDetails(except: .sncbStation)
                selectedSncbStation = station
            },
            onSelectOperatorStop: { stop in
                guard acquireMapTapLock() else { return }
                dismissOtherBottomDetails(except: .operatorStop)
                selectedOperatorStop = stop
            },
            onSelectVilloStation: { station in
                guard acquireMapTapLock() else { return }
                dismissOtherBottomDetails(except: .villoStation)
                selectedVilloStation = station
            },
            onSelectEventImpact: { event in
                guard acquireMapTapLock() else { return }
                dismissOtherBottomDetails(except: .eventImpact)
                selectedEventImpact = event
            },
            onSelectVehicle: { vehicle in
                guard acquireMapTapLock() else { return }
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    dismissOtherBottomDetails(except: .vehicle)
                    selectedVehicle = vehicle
                }
            },
            onCameraChanged: { region in
                // Skip sub-threshold updates: the visibility predicates use
                // bands of 0.03/0.05/0.12/0.18, so anything finer than 0.005
                // does not change the rendered set but does re-evaluate every
                // computed that reads cameraLatitudeDelta (causing 30+
                // body invalidations per scroll).
                let newDelta = region.span.latitudeDelta
                if abs(newDelta - cameraLatitudeDelta) > 0.005 {
                    cameraLatitudeDelta = newDelta
                }
                cameraLongitudeDelta = region.span.longitudeDelta
                cameraCenterCoordinate = region.center
                handleMapCameraInteraction()
                scheduleOperatorStopsRefresh()
            }
        )
    }

    private func handleMapCameraInteraction() {
            if suppressNextCameraInteraction {
                suppressNextCameraInteraction = false
            } else {
                isFollowingUser = false
                // Interagir avec la carte (pan/zoom) ferme le clavier de
                // recherche — geste instinctif quand on tape une adresse. Le
                // bouton « Terminé » au-dessus du clavier reste l'autre issue.
                dismissKeyboard()
            }
            scheduleCatalogMapStopsRefresh()
            scheduleActiveClustersRefresh()
    }

    /// Ferme le clavier globalement, sans dépendre d'un @FocusState précis
    /// (le champ de recherche gère son focus localement).
    private func dismissKeyboard() {
        UIApplication.shared.sendAction(
            #selector(UIResponder.resignFirstResponder), to: nil, from: nil, for: nil
        )
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
              proactiveAlertCluster == nil,
              nav.currentPage == .home,
              !nav.showReportSheet else { return }

        guard let user = session.currentUser else { return }
        let favoriteLines = Set((user.favoriteLines ?? []).compactMap { rawLine -> String? in
            let normalized = rawLine.uppercased()
            return normalized.contains(":") ? nil : normalized
        })
        let hasRoutine = user.routine?.enabled == true
        guard !favoriteLines.isEmpty || hasRoutine else { return }

        let affectedCluster = activeClusters.first { cluster in
            let line = cluster.ligne.uppercased()
            if favoriteLines.contains(line) { return true }
            if let homeStopId = user.routine?.homeStopId, cluster.arretId == homeStopId { return true }
            if let workStopId = user.routine?.workStopId, cluster.arretId == workStopId { return true }
            return false
        }

        guard let affectedCluster else { return }

        hasAutoShownDecision = true
        try? await Task.sleep(nanoseconds: 600_000_000)
        withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
            proactiveAlertCluster = affectedCluster
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
        // Mic / AI / Location / + are all rendered in HomeBottomChromeOverlay's
        // pulse-bar row now (one homogeneous line above the tab bar).
        EmptyView()
    }

    // MARK: - ZStack overlays (legend, sheets, AR, page)

    @ViewBuilder private var zstackOverlays: some View {
        if showLegend {
            MapLegendOverlay(
                showStibStops: $showStibStops,
                showSncbStations: $showSncbStations,
                showDelijnStops: $showDelijnStops,
                showTecStops: $showTecStops,
                showVilloStations: $showVilloStations,
                showEventImpacts: $showEventImpacts
            ) {
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
            communitySignalements: remoteSignalements,
            onDismiss: {
                // Recadre sur l'arrêt consulté avant de fermer (cf.
                // dismissStopPreview) : on retrouve son arrêt bien centré.
                let focusedStop = selectedMapStopPreview ?? selectedMapStopSummary
                enterInteractionMode(.map)
                if let focusedStop {
                    focusMap(on: focusedStop)
                }
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
            blockedLines: currentTransportRecommendation?.request.lignesBloquees ?? [],
            selectedRouteID: $selectedRouteID,
            isRouteSheetExpanded: $isRouteSheetExpanded,
            selectedRouteDetail: selectedRouteDetail,
            shouldShowRouteSheet: shouldShowRouteSheet,
            shouldShowRouteDetail: shouldShowRouteDetail,
            onSelect: applyRouteOption(_:),
            onCloseRouteSheet: closeRouteSurface,
            onBackFromRouteDetail: showRoutePreviewFromDetail,
            onCloseRouteDetail: closeRouteSurface,
            onShowRouteMap: showRoutePreviewFromDetail
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
        case .stopDetail:
            selectedMapStopPreview = nil
            selectedRouteDetail = nil
        case .routePreview:
            clearStopSelection()
            selectedRouteDetail = nil
        case .routeDetail:
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
    func openVoiceFromHome() {
        showVoiceOverlay = true
    }

    @MainActor
    func openStibAIFromHome() {
        showStibAI = true
    }

    /// Internal wrapper so the bottom-chrome extension can recenter without
    /// touching the private recenterOnUser() implementation.
    @MainActor
    func recenterFromHome() {
        recenterOnUser()
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
    func selectStopLineRoute(_ line: String) {
        let normalized = normalizedLineNumber(line)
        guard !normalized.isEmpty else { return }
        withAnimation(.easeInOut(duration: 0.25)) {
            selectedStopLineNumber = normalized
        }
        focusMap(onLineShapesFor: normalized)
    }

    /// Opens the full standalone `ArretDetailPage` from the mini header card.
    /// We promote the currently-selected stop from "preview" to "detail" mode
    /// so the search header collapses and the full page slides in.
    @MainActor
    func openStopDetailFromMiniCard(for stop: TransportStopSummaryDTO) {
        withAnimation(.spring(response: 0.35, dampingFraction: 0.84)) {
            selectedMapStopSummary = stop
            selectedMapStopPreview = nil
            if selectedStopLineNumber == nil {
                selectedStopLineNumber = firstDisplayableLine(from: stop.lines)
            }
            interactionMode = .stopDetail
        }
        // Detail data may already be loaded from the mini card; load only if
        // the cached payload is for a different stop (sibling fetch was for
        // the previous tap).
        if selectedMapStopDetail?.stop.id != stop.id {
            loadStopDetail(for: stop)
        }
    }

    /// Closes the mini stop card and returns the map to its idle state.
    /// Unlike `enterInteractionMode(.map)` this preserves any route surface,
    /// only the stop-pin selection is unwound.
    @MainActor
    func dismissStopPreview() {
        // En fermant la fiche, on RECADRE sur l'arrêt qu'on consultait : pendant
        // le focus l'utilisateur a souvent baladé la carte (voir le tracé, les
        // véhicules…), et il s'attend à retrouver SON arrêt bien centré, pas la
        // dernière position de la caméra. On capture la coordonnée avant de
        // vider la sélection.
        let focusedStop = selectedMapStopPreview ?? selectedMapStopSummary
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedMapStopPreview = nil
            selectedMapStopDetail = nil
            selectedStopLineNumber = nil
            isLoadingMapStopDetail = false
            if interactionMode == .stopPreview {
                interactionMode = .map
            }
        }
        if let focusedStop {
            focusMap(on: focusedStop)
        }
    }

    @MainActor
    func clearRouteSelection(keepDestination: Bool) {
        tripTracker.stop()
        routeOptions = []
        routeModeSummaries = []
        selectedRouteID = nil
        currentRoute = nil
        currentRouteCoordinates = []
        routeOverlayRevision += 1
        if !keepDestination {
            destinationCoord = nil
            // Closing the route surface should wipe the destination chip
            // shown in the search header — the search bar reads from
            // `searchQuery` and was leaving the previous destination there
            // even after the user dismissed the route.
            searchQuery = ""
            searchSuggestions = []
        }
        currentTransportRecommendation = nil
        isRouteSheetExpanded = false
        selectedRouteDetail = nil
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

    func focusMapOnFavorites() {
        let stibCoordinates = favoriteMapStops.compactMap { stop -> CLLocationCoordinate2D? in
            guard let latitude = stop.latitude, let longitude = stop.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let stationCoordinates = gareFavorites.stations.map(\.coordinate)
        let operatorCoordinates = favoriteOperatorMapStops.map(\.coordinate)
        let coordinates = stibCoordinates + stationCoordinates + operatorCoordinates

        guard !coordinates.isEmpty else {
            nav.currentPage = .favorites
            return
        }

        isFollowingUser = false
        suppressNextCameraInteraction = true

        if coordinates.count == 1, let coordinate = coordinates.first {
            cameraCenterCoordinate = coordinate
            cameraLatitudeDelta = 0.018
            withAnimation(.easeInOut(duration: 0.55)) {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.018, longitudeDelta: 0.018)
                    )
                )
            }
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        guard !rect.isNull else { return }
        withAnimation(.easeInOut(duration: 0.65)) {
            mapPosition = .rect(
                rect.insetBy(
                    dx: -max(rect.width * 0.28, 850),
                    dy: -max(rect.height * 0.28, 850)
                )
            )
        }
    }

    func focusMapOnPerturbations() {
        let reportCoordinates = remoteSignalements.compactMap { signalement -> CLLocationCoordinate2D? in
            guard signalement.status != "resolved",
                  let latitude = signalement.latitude,
                  let longitude = signalement.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let clusterCoordinates = activeClusters.compactMap { cluster -> CLLocationCoordinate2D? in
            guard let latitude = cluster.latitude, let longitude = cluster.longitude else { return nil }
            return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
        }
        let coordinates = reportCoordinates + clusterCoordinates

        guard !coordinates.isEmpty else {
            openReportsFromHome()
            return
        }

        isFollowingUser = false
        suppressNextCameraInteraction = true

        if coordinates.count == 1, let coordinate = coordinates.first {
            cameraCenterCoordinate = coordinate
            cameraLatitudeDelta = 0.02
            withAnimation(.easeInOut(duration: 0.55)) {
                mapPosition = .region(
                    MKCoordinateRegion(
                        center: coordinate,
                        span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                    )
                )
            }
            return
        }

        var rect = MKMapRect.null
        for coordinate in coordinates {
            let point = MKMapPoint(coordinate)
            let pointRect = MKMapRect(x: point.x, y: point.y, width: 0, height: 0)
            rect = rect.isNull ? pointRect : rect.union(pointRect)
        }

        guard !rect.isNull else {
            openReportsFromHome()
            return
        }

        withAnimation(.easeInOut(duration: 0.65)) {
            mapPosition = .rect(
                rect.insetBy(
                    dx: -max(rect.width * 0.22, 1_000),
                    dy: -max(rect.height * 0.22, 1_000)
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

    /// Centres the camera on a specific vehicle so the user can spot the
    /// "Plus proche" tram even when they've panned the map away from the
    /// focused stop. Triggered from the mini-card's closest-vehicle row.
    @MainActor
    func panMap(to vehicle: TransportVehicleDTO) {
        guard let lat = vehicle.latitude, let lng = vehicle.longitude else { return }
        let coordinate = CLLocationCoordinate2D(latitude: lat, longitude: lng)
        isFollowingUser = false
        suppressNextCameraInteraction = true
        withAnimation(.easeInOut(duration: 0.55)) {
            mapPosition = .region(MKCoordinateRegion(
                center: coordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
            ))
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
        // The FAVORIS chip reflects every saved place the map can show:
        // backend STIB stops + local SNCB gares + local De Lijn/TEC stops.
        let stibStops = session.currentUser?.favorisDetails?.count ?? 0
        return stibStops + gareFavorites.ids.count + operatorFavorites.stops.count
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
                // STIB models every physical stop as 2 separate stop IDs —
                // one per direction. Fetching only the tapped pin gives us
                // departures for a single direction (the other side of the
                // street is silent). Look up sibling stop IDs sharing the
                // same name within 80 m and merge their nextDepartures so
                // the mini-card shows both directions.
                let siblingIds = self.siblingStopIds(for: stop)
                async let primary = TransportService.stop(id: lookupId)
                let siblings = await withTaskGroup(of: [TransportDepartureDTO].self) { group in
                    for sid in siblingIds {
                        group.addTask {
                            (try? await TransportService.stop(id: sid))?.nextDepartures ?? []
                        }
                    }
                    var all: [TransportDepartureDTO] = []
                    for await deps in group { all.append(contentsOf: deps) }
                    return all
                }
                let primaryDetail = try await primary
                let merged = Self.mergeDepartures(
                    primaryDetail.nextDepartures + siblings
                )
                let detail = TransportStopDTO(
                    stop: primaryDetail.stop,
                    severity: primaryDetail.severity,
                    confidence: primaryDetail.confidence,
                    realtimeStatus: primaryDetail.realtimeStatus,
                    officialDataStatus: primaryDetail.officialDataStatus,
                    officialDataMessage: primaryDetail.officialDataMessage,
                    perturbationSummary: primaryDetail.perturbationSummary,
                    label: primaryDetail.label,
                    color: primaryDetail.color,
                    activeIncidents: primaryDetail.activeIncidents,
                    nextDepartures: merged,
                    recommendedAlternatives: primaryDetail.recommendedAlternatives
                )
                await MainActor.run {
                    let matchesPreview = selectedMapStopPreview?.id == stop.id
                    let matchesDetail = selectedMapStopSummary?.id == stop.id
                    if matchesPreview || matchesDetail {
                        selectedMapStopDetail = detail
                        selectDefaultStopLineIfNeeded(from: detail)
                        learnDirectionTerminus(for: detail)
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

    /// Returns the backend stop IDs of every catalog stop sharing the same
    /// (normalised) name and within ~150 m of the tapped stop, excluding the
    /// stop itself. Used to fetch the other-direction quay of the same
    /// physical platform. We strip parenthetical suffixes ("(direction X)",
    /// "(quai 1)", …) and accented chars so MONTGOMERY and MONTGOMERY (quai
    /// 1) merge as siblings.
    private func siblingStopIds(for stop: TransportStopSummaryDTO) -> [String] {
        guard let stopLat = stop.latitude, let stopLng = stop.longitude else { return [] }
        let origin = CLLocation(latitude: stopLat, longitude: stopLng)
        let normalizedName = Self.normalizedStopName(stop.name)
        return catalogMapStops.compactMap { ns -> String? in
            guard Self.normalizedStopName(ns.name) == normalizedName else { return nil }
            guard let coord = ns.coordinate, let backendId = ns.backendId else { return nil }
            guard backendId != stop.id, backendId != stop.stopId else { return nil }
            let distance = origin.distance(from: CLLocation(latitude: coord.latitude, longitude: coord.longitude))
            return distance <= 150 ? backendId : nil
        }
    }

    /// Strip parenthetical qualifiers and accented characters so two quays of
    /// the same physical stop collapse to a single key even when STIB labels
    /// them differently per direction.
    private static func normalizedStopName(_ raw: String) -> String {
        let withoutParens = raw.replacingOccurrences(
            of: #"\s*\([^)]*\)\s*"#,
            with: "",
            options: .regularExpression
        )
        return withoutParens
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
    }

    /// De-duplicate departures by `(line, destination, minutes)` then sort
    /// chronologically. Realtime entries win over scheduled when both exist
    /// for the same key.
    private static func mergeDepartures(_ all: [TransportDepartureDTO]) -> [TransportDepartureDTO] {
        var bucket: [String: TransportDepartureDTO] = [:]
        for d in all {
            let key = "\(d.line.uppercased())|\(d.destination?.uppercased() ?? "")|\(d.minutes)"
            if let existing = bucket[key] {
                if existing.source != "realtime", d.source == "realtime" {
                    bucket[key] = d
                }
            } else {
                bucket[key] = d
            }
        }
        return bucket.values.sorted { $0.minutes < $1.minutes }
    }

    @MainActor
    private func openStopPreview(for stop: TransportStopSummaryDTO) {
        guard acquireMapTapLock() else { return }
        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
            selectedMapStopPreview = stop
            selectedStopLineNumber = firstDisplayableLine(from: stop.lines)
            enterInteractionMode(.stopPreview)
        }
        loadStopDetail(for: stop)
        if let selectedStopLineNumber {
            focusMap(onLineShapesFor: selectedStopLineNumber)
        }
    }

    /// Returns true if a fresh map-tap is allowed, or false if a previous tap
    /// fired within the last 200 ms. Acquiring the lock extends it.
    @MainActor
    private func acquireMapTapLock() -> Bool {
        let now = Date()
        if let until = mapTapLockedUntil, until > now { return false }
        mapTapLockedUntil = now.addingTimeInterval(0.2)
        return true
    }

    var loadingMapStopId: String? {
        guard isLoadingMapStopDetail else { return nil }
        return selectedMapStopPreview?.id ?? selectedMapStopSummary?.id
    }

    @MainActor
    private func openStopDetail(for stop: TransportStopSummaryDTO) {
        guard acquireMapTapLock() else { return }
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

    @MainActor
    func closeProactiveAlert() {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            proactiveAlertCluster = nil
        }
    }

    @MainActor
    func openProactiveAlertCluster(_ cluster: ClusterDTO) {
        closeProactiveAlert()
        selectedClusterIndex = cluster.clusterIndex
        if let latitude = cluster.latitude, let longitude = cluster.longitude {
            withAnimation(.easeInOut(duration: 0.35)) {
                mapPosition = .region(MKCoordinateRegion(
                    center: CLLocationCoordinate2D(latitude: latitude, longitude: longitude),
                    span: MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
                ))
            }
        }
    }

    func confirmProactiveAlertStillBlocked(_ cluster: ClusterDTO) async {
        do {
            _ = try await ClusterService.confirmStillBlocked(cluster.clusterIndex)
            await MainActor.run {
                closeProactiveAlert()
                lastClustersFetchCoordinate = nil
                scheduleActiveClustersRefresh()
            }
        } catch {
            ErrorReporting.capture(error, tag: "home.proactiveAlert.stillBlocked", context: [
                "clusterIndex": "\(cluster.clusterIndex)"
            ])
        }
    }

    func confirmProactiveAlertResolved(_ cluster: ClusterDTO) async {
        do {
            _ = try await ClusterService.confirmResolved(cluster.clusterIndex)
            await MainActor.run {
                closeProactiveAlert()
                lastClustersFetchCoordinate = nil
                scheduleActiveClustersRefresh()
            }
        } catch {
            ErrorReporting.capture(error, tag: "home.proactiveAlert.resolved", context: [
                "clusterIndex": "\(cluster.clusterIndex)"
            ])
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

    /// Debounced viewport fetch for De Lijn / TEC stops — only fires when the
    /// user is zoomed in past the operator gate, and skips if the camera hasn't
    /// moved much since the last fetch.
    private func scheduleOperatorStopsRefresh() {
        guard cameraLatitudeDelta <= 0.018, showDelijnStops || showTecStops else {
            operatorStopsTask?.cancel()
            operatorMapStops = []
            lastOperatorStopsCoordinate = nil
            return
        }
        if let last = lastOperatorStopsCoordinate,
           centerDistanceMeters(from: last, to: cameraCenterCoordinate) < 300,
           !operatorMapStops.isEmpty {
            return
        }
        operatorStopsTask?.cancel()
        operatorStopsTask = Task {
            try? await Task.sleep(nanoseconds: 220_000_000)
            guard !Task.isCancelled else { return }
            await refreshOperatorStops()
        }
    }

    @MainActor
    private func refreshOperatorStops() async {
        guard cameraLatitudeDelta <= 0.018 else { operatorMapStops = []; return }
        let latSpan = max(cameraLatitudeDelta, 0.001)
        let lngSpan = max(cameraLongitudeDelta, 0.001)
        let minLat = cameraCenterCoordinate.latitude - latSpan / 2
        let maxLat = cameraCenterCoordinate.latitude + latSpan / 2
        let minLng = cameraCenterCoordinate.longitude - lngSpan / 2
        let maxLng = cameraCenterCoordinate.longitude + lngSpan / 2

        var combined: [OperatorMapStop] = []
        if showDelijnStops {
            combined += await OperatorStopService.stops(operator: .delijn, minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, limit: 200)
        }
        if showTecStops {
            combined += await OperatorStopService.stops(operator: .tec, minLat: minLat, maxLat: maxLat, minLng: minLng, maxLng: maxLng, limit: 200)
        }
        guard !Task.isCancelled else { return }
        operatorMapStops = combined
        lastOperatorStopsCoordinate = cameraCenterCoordinate
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
    func mergeIncomingSignalement(_ signalement: SignalementDTO) {
        if let index = remoteSignalements.firstIndex(where: { $0.id == signalement.id }) {
            remoteSignalements[index] = signalement
        } else {
            remoteSignalements.insert(signalement, at: 0)
        }
    }

    /// « zoek » / Entrée dans la search bar : calcule un itinéraire DEPUIS la
    /// position de l'utilisateur vers la saisie, puis affiche les alternatives
    /// — sans ouvrir la page Route. On route vers la meilleure suggestion déjà
    /// calculée (arrêt STIB ou adresse Apple) ; si la liste n'est pas encore
    /// prête, on géocode la requête à la volée. C'est le `tripDestination`
    /// pipeline (le même que la sélection d'une suggestion) qui fait le reste.
    @MainActor
    func submitSearchToRoute() {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }

        // 1) Si une suggestion est déjà disponible, on prend la meilleure.
        if let best = searchSuggestions.first {
            tripDestination = TripDestination(
                coordinate: best.placemark.coordinate,
                label: best.name ?? best.placemark.title
            )
            return
        }

        // 2) Sinon, résolution à la volée : arrêt STIB d'abord, puis géocodage.
        Task { @MainActor in
            if let stop = await NearbyStopService.searchStopByName(query) {
                tripDestination = TripDestination(coordinate: stop.coordinate, label: stop.name)
                return
            }
            let req = MKLocalSearch.Request()
            req.naturalLanguageQuery = query
            req.resultTypes = [.address, .pointOfInterest]
            req.region = MKCoordinateRegion(
                center: cameraCenterCoordinate,
                span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
            )
            if let item = (try? await MKLocalSearch(request: req).start())?.mapItems.first {
                tripDestination = TripDestination(
                    coordinate: item.placemark.coordinate,
                    label: item.name ?? item.placemark.title
                )
            }
        }
    }

    @MainActor
    private func searchSuggestions(for text: String) async {
        // STIB stops d'abord (préfixe accepté → "del" → DELACROIX) puis
        // MKLocalSearch pour les adresses / monuments. Avant on n'avait que
        // MKLocalSearch et l'utilisateur tapait "delacroix" → résultats
        // pourris ("Croix-Rouge", "Kathleen Dandoy"). Les arrêts STIB doivent
        // dominer la liste pour une app de mobilité.
        async let stibTask = NearbyStopService.topStopsByName(text, limit: 5)

        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = text
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.25, longitudeDelta: 0.25)
        )
        async let mkTask = (try? await MKLocalSearch(request: req).start())?.mapItems ?? []

        let (stibStops, mkItems) = await (stibTask, mkTask)

        var merged: [MKMapItem] = []
        var seen = Set<String>()

        // 1) STIB stops en tête, convertis en MKMapItem pour rester compatibles
        //    avec le picker existant.
        for stop in stibStops {
            let placemark = MKPlacemark(coordinate: stop.coordinate)
            let item = MKMapItem(placemark: placemark)
            item.name = stop.name
            let key = "stib|\(stop.name)"
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }

        // 2) MKLocalSearch en dessous, en évitant de re-suggérer un arrêt déjà
        //    proposé en tête.
        for item in mkItems {
            let key = "\(item.name ?? "")|\(item.placemark.title ?? "")"
            // Skip si le nom est déjà dans la liste STIB (case-insensitive).
            if stibStops.contains(where: { $0.name.compare(item.name ?? "", options: .caseInsensitive) == .orderedSame }) {
                continue
            }
            if seen.insert(key).inserted {
                merged.append(item)
            }
        }

        searchSuggestions = Array(merged.prefix(8))
    }

    @MainActor
    private func resolveSTIBAIDestination(_ text: String) async -> MKMapItem? {
        await STIBAIDestinationResolver.resolve(text, near: locationManager.displayCoordinate)
    }

    @MainActor
    private func stibAIRouteOptions(to destination: MKMapItem) async -> [HomeRouteOption] {
        let source = MKMapItem(placemark: MKPlacemark(coordinate: locationManager.displayCoordinate))
        async let recommendationTask = fetchBackendRecommendation(source: source, destination: destination)
        async let transitRoutesTask = fetchMKRoutes(source: source, destination: destination, transportType: .transit)
        async let walkingRoutesTask = fetchMKRoutes(source: source, destination: destination, transportType: .walking)

        let recommendation = await recommendationTask
        let transitRoutes = await transitRoutesTask
        let walkingRoutes = await walkingRoutesTask
        let destinationName = destination.name ?? destination.placemark.title ?? "Destination"
        let fallbackOptions = buildFallbackRouteOptions(
            transitRoutes: transitRoutes,
            walkingRoutes: walkingRoutes,
            originName: "Votre position",
            destinationName: destinationName
        )

        return buildBackendFirstRouteOptions(
            recommendation: recommendation,
            fallbackOptions: fallbackOptions,
            originName: "Votre position",
            destinationName: destinationName
        )
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
            destination: destinationQuery,
            lignesBloquees: liveBlockedLines
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
            destination: destinationQuery,
            lignesBloquees: liveBlockedLines
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

    /// Geocode the destination string returned by the voice assistant (e.g.
    /// "Flagey", "Gare Centrale") around the user's location, then hand it to
    /// the existing `tripDestination` pipeline so the route is built + shown
    /// on the map just like a manual search.
    /// Voice-flow step 1 of 2: geocode the spoken destination + compute the
    /// real route options (transit + walking), without changing any UI state.
    /// The planned trip is stashed in `pendingVoiceTrip` so the user can
    /// confirm it via "Voir la route sur la carte" without a second search.
    /// Returns the proposedRoutes for the backend's 2nd AI call so Gemini can
    /// describe the actual lines/stops instead of fabricating them.
    /// Smart Commute LITE — lance le trajet quotidien à partir de la
    /// routine sauvegardée. Résout les 2 stop IDs en coords via
    /// `TransportService.stop`, puis pipe sur `buildRoute` (existant).
    /// Pas de nouveau code routing. Si la résolution rate (stop archivé,
    /// backend down), on ne fait rien — l'utilisateur retentera ou
    /// passera par le planner.
    /// C1 — Mutex sur les bottom sheets. Avant : 4 states indépendants (cluster,
    /// vehicle, signalement preview, operator stop, sncb station, villo,
    /// event impact) pouvaient être set en même temps → 2+ overlays bottom
    /// rendus l'un par-dessus l'autre sans dismiss. Maintenant on appelle ce
    /// helper avant chaque "présentation" pour clear le reste.
    @MainActor
    func dismissOtherBottomDetails(except: BottomDetailKind) {
        if except != .signalementPreview { selectedSignalementPreview = nil }
        if except != .cluster { selectedClusterIndex = nil }
        if except != .vehicle { selectedVehicle = nil }
        if except != .operatorStop { selectedOperatorStop = nil }
        if except != .sncbStation { selectedSncbStation = nil }
        if except != .villoStation { selectedVilloStation = nil }
        if except != .eventImpact { selectedEventImpact = nil }
    }

    enum BottomDetailKind {
        case signalementPreview, cluster, vehicle, operatorStop, sncbStation, villoStation, eventImpact
    }

    @MainActor
    func launchCommute(direction: CommuteQuickLaunchCard.Direction, routine: CommuteRoutineDTO) async {
        let (originId, destinationId, originName, destinationName) = direction == .toWork
            ? (routine.homeStopId, routine.workStopId, routine.homeLabel, routine.workLabel)
            : (routine.workStopId, routine.homeStopId, routine.workLabel, routine.homeLabel)
        guard let originId, let destinationId else { return }
        // Print event pour valider l'adoption (sans backend analytics).
        print("commute_quick_launch_tapped direction=\(direction == .toWork ? "toWork" : "toHome")")

        async let originDTO = try? TransportService.stop(id: originId)
        async let destinationDTO = try? TransportService.stop(id: destinationId)
        let (origin, destination) = await (originDTO, destinationDTO)

        guard let origin = origin?.stop,
              let destination = destination?.stop,
              let oLat = origin.latitude, let oLng = origin.longitude,
              let dLat = destination.latitude, let dLng = destination.longitude else {
            // Fallback : utilise la position courante pour l'origine, et tente
            // une recherche de nom pour la destination.
            if let destStop = destination?.stop,
               let dLat = destStop.latitude, let dLng = destStop.longitude {
                let destItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: dLat, longitude: dLng)))
                destItem.name = destinationName
                await buildRoute(to: destItem)
            }
            return
        }

        let originItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: oLat, longitude: oLng)))
        originItem.name = originName
        let destItem = MKMapItem(placemark: MKPlacemark(coordinate: CLLocationCoordinate2D(latitude: dLat, longitude: dLng)))
        destItem.name = destinationName
        await buildRoute(from: originItem, to: destItem, originName: originName)
    }

    @MainActor
    private func prepareVoiceTrip(_ name: String) async -> [ProposedRoute]? {
        guard let destination = await STIBAIDestinationResolver.resolve(
            name,
            near: locationManager.userCoordinate ?? cameraCenterCoordinate
        ) else {
            pendingVoiceTrip = nil
            return nil
        }
        let options = await stibAIRouteOptions(to: destination)
        guard !options.isEmpty else {
            pendingVoiceTrip = nil
            return nil
        }
        pendingVoiceTrip = (destination, options)
        return stibAIProposedRoutes(from: options)
    }

    /// Voice-flow step 2 of 2: surface the already-planned trip on the map.
    /// No async work — `prepareVoiceTrip` did the heavy lifting.
    @MainActor
    private func applyPreparedVoiceTrip() {
        guard let trip = pendingVoiceTrip else { return }
        pendingVoiceTrip = nil
        showVoiceOverlay = false

        destinationCoord = trip.destination.placemark.coordinate
        searchSuggestions = []
        searchQuery = trip.destination.name ?? ""

        let preferredOption = preferredRouteOption(in: trip.options)

        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
            routeOptions = trip.options
            routeModeSummaries = buildModeSummaries(recommendation: nil, options: trip.options)
            selectedRouteID = preferredOption?.id
            isRouteSheetExpanded = false
            enterInteractionMode(.routePreview)
        }

        if let preferredOption {
            applyRouteOption(preferredOption)
        }
    }

    private func applyRouteOption(_ option: HomeRouteOption) {
        currentRoute = option.route
        currentRouteCoordinates = option.routeCoordinates
        selectedRouteID = option.id
        routeOverlayRevision += 1
        enterInteractionMode(.routePreview)

        withAnimation(.easeOut(duration: 0.35)) {
            mapPosition = .rect(routeFramingRect(for: option))
        }

        // Start the voice trip announcer on this option.
        tripTracker.start(option: option)
    }

    /// Frame a route so it sits in the visible upper area of the map rather
    /// than centred behind the results sheet (which covers the lower third).
    /// We add light breathing room, then extend the rect downward so the route
    /// content rises above the sheet — otherwise the user had to pan down to
    /// "find" their trip.
    private func routeFramingRect(for option: HomeRouteOption) -> MKMapRect {
        let coords = option.routeCoordinates
        let base: MKMapRect = coords.count > 1
            ? MKPolyline(coordinates: coords, count: coords.count).boundingMapRect
            : option.mapRectWithPadding
        let padded = base.insetBy(dx: -base.width * 0.18, dy: -base.height * 0.18)
        // Grow the bottom (south) so the route fits in roughly the top 60% of
        // the viewport — clear of the collapsed recommendations sheet.
        let extraBottom = padded.height * 0.7
        return MKMapRect(x: padded.origin.x, y: padded.origin.y, width: padded.width, height: padded.height + extraBottom)
    }

    @ViewBuilder
    private var pageOverlay: some View {
        ZStack {
            Color(hex: (nav.currentPage == .signalements || nav.currentPage == .reports || nav.currentPage == .schedules || nav.currentPage == .favorites || nav.currentPage == .profile) ? "#1B1B1B" : "#0B111E").ignoresSafeArea()

            if nav.currentPage != .signalements && nav.currentPage != .reports && nav.currentPage != .schedules && nav.currentPage != .favorites && nav.currentPage != .profile {
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
            case .schedules:
                SchedulesView()
            case .favorites:
                FavoritesView()
            case .profile:
                ProfileView()
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
