import MapKit
import SwiftUI
import CoreLocation

struct HomeMapLayer: View {
    @Binding var mapPosition: MapCameraPosition
    let visibleLineShapes: [LineShape]
    let selectedStopLineShapes: [LineShape]
    let displayCoordinate: CLLocationCoordinate2D
    let heading: Double
    let routeMapSegments: [HomeView.RouteMapSegment]
    let routeOverlayRevision: Int
    let destinationCoordinate: CLLocationCoordinate2D?
    let officialSignalPoints: [HomeView.LiveSignalPoint]
    let routeOfficialSignalPoints: [HomeView.RouteOfficialSignalPoint]
    let activeClusters: [ClusterDTO]
    let selectedClusterIndex: Int?
    let cameraLatitudeDelta: Double
    let mapVehicles: [TransportVehicleDTO]
    let vehicleBearings: [String: Double]
    let mapStops: [TransportStopSummaryDTO]
    let favoriteStopIds: Set<String>
    let favoriteGareIds: Set<String>
    let favoriteOperatorStopKeys: Set<String>
    let selectedMapStopPreview: TransportStopSummaryDTO?
    let selectedMapStopSummary: TransportStopSummaryDTO?
    var loadingMapStopId: String? = nil
    let mapSncbStations: [SNCBStation]
    let selectedSncbStation: SNCBStation?
    let mapOperatorStops: [OperatorMapStop]
    let mapVilloStations: [VilloStation]
    let mapEventImpacts: [TransportEventImpactDTO]
    let onOpenPreview: (String) -> Void
    let onOpenStopPreview: (TransportStopSummaryDTO) -> Void
    let onSelectCluster: (ClusterDTO) -> Void
    let onSelectClusterCount: (CLLocationCoordinate2D) -> Void
    let onSelectSncbStation: (SNCBStation) -> Void
    let onSelectOperatorStop: (OperatorMapStop) -> Void
    let onSelectVilloStation: (VilloStation) -> Void
    let onSelectEventImpact: (TransportEventImpactDTO) -> Void
    let onSelectVehicle: (TransportVehicleDTO) -> Void
    let onCameraChanged: (MKCoordinateRegion) -> Void

    var body: some View {
        Map(position: $mapPosition) {
            lineShapeOverlays
            userLocationOverlay
            routeOverlays
            officialIncidentAnnotations
            communityClusterAnnotations
            stopAnnotations
            sncbStationAnnotations
            operatorStopAnnotations
            villoAnnotations
            eventAnnotations
            // Vehicles render LAST so their pins sit on top of every other
            // annotation — without this a tram that lands on the same pixel
            // as the user-location dot or a stop marker would visually vanish
            // even though it's actually there.
            vehicleAnnotations
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { }
        .environment(\.colorScheme, .light)
        // MapKit can keep stale polyline renderers when route overlays become
        // empty. Rebuilding the Map only on route changes gives a deterministic
        // cleanup without touching normal pan/zoom updates.
        .id(routeOverlayRevision)
        .ignoresSafeArea()
        .onMapCameraChange(frequency: .onEnd) { ctx in
            onCameraChanged(ctx.region)
        }
    }

    @MapContentBuilder
    private var lineShapeOverlays: some MapContent {
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
    }

    @MapContentBuilder
    private var userLocationOverlay: some MapContent {
        // 80 m circle instead of 200 m so a tram pin landing near the user
        // dot is not hidden by the translucent fill at city-wide zoom.
        MapCircle(center: displayCoordinate, radius: 80)
            .foregroundStyle(DS.Color.info.opacity(0.08))
            .stroke(DS.Color.info.opacity(0.22), lineWidth: 1)

        Annotation("", coordinate: displayCoordinate, anchor: .center) {
            UserLocationDotView(heading: heading)
        }
    }

    @MapContentBuilder
    private var routeOverlays: some MapContent {
        ForEach(routeMapSegments) { segment in
            MapPolyline(coordinates: segment.coordinates)
                .stroke(
                    segment.color,
                    style: StrokeStyle(lineWidth: segment.lineWidth, lineCap: .round, lineJoin: .round)
                )
        }

        if let destinationCoordinate {
            Annotation("", coordinate: destinationCoordinate, anchor: .bottom) {
                Image(systemName: "mappin.circle.fill")
                    .font(.system(size: 32))
                    .foregroundStyle(DS.Color.info)
                    .shadow(radius: 4)
            }
        }
    }

    @MapContentBuilder
    private var officialIncidentAnnotations: some MapContent {
        // routeOfficialSignalPoints stay un-clustered: they belong to the
        // active route surface so the user must see each one individually.
        ForEach(routeOfficialSignalPoints) { point in
            Annotation("", coordinate: point.coordinate, anchor: .bottom) {
                Button {
                    if let stop = point.stop {
                        onOpenStopPreview(stop)
                    }
                } label: {
                    OfficialSignalMarker(problemType: point.title)
                }
                .buttonStyle(.plain)
            }
        }
    }

    /// Distance (m) under which a signalement is treated as sitting *on* a
    /// displayed stop — close enough that the two markers would overlap. At
    /// that point we drop the standalone warning pin and badge the stop
    /// instead (the chosen UX: one clean marker per stop).
    private static let stopColocationMeters: CLLocationDistance = 35
    private static let officialMarkerDedupMeters: CLLocationDistance = 42

    /// Nearest displayed stop to a signal, within the overlap threshold. A
    /// matching backend id (when known) wins outright; otherwise we fall back
    /// to geographic proximity.
    private func colocatedStop(stopId: String?, lat: Double?, lng: Double?) -> TransportStopSummaryDTO? {
        if let stopId, let match = mapStops.first(where: { $0.id == stopId }) {
            return match
        }
        guard let lat, let lng else { return nil }
        let signalLoc = CLLocation(latitude: lat, longitude: lng)
        var nearest: TransportStopSummaryDTO?
        var nearestDist = Self.stopColocationMeters
        for stop in mapStops {
            guard let slat = stop.latitude, let slng = stop.longitude else { continue }
            let distance = signalLoc.distance(from: CLLocation(latitude: slat, longitude: slng))
            if distance <= nearestDist {
                nearestDist = distance
                nearest = stop
            }
        }
        return nearest
    }

    private func warningStyle(for cluster: ClusterDTO) -> StopWarningStyle {
        let rank: Int
        if cluster.isOfficial {
            rank = 3
        } else {
            switch cluster.confidence {
            case .high: rank = 3
            case .medium: rank = 2
            case .low: rank = 1
            }
        }
        return StopWarningStyle(
            color: SignalVisuals.communityColor(for: cluster),
            icon: SignalVisuals.icon(forType: cluster.typeProbleme),
            rank: rank
        )
    }

    private func warningStyle(for point: HomeView.LiveSignalPoint) -> StopWarningStyle {
        // Official STIB incidents are authoritative → top rank, danger colour.
        StopWarningStyle(
            color: DS.Color.danger,
            icon: SignalVisuals.icon(forType: point.typeProbleme),
            rank: 3
        )
    }

    private func colocatedSncbStation(lat: Double?, lng: Double?) -> SNCBStation? {
        guard let lat, let lng else { return nil }
        let signalLoc = CLLocation(latitude: lat, longitude: lng)
        var nearest: SNCBStation?
        var nearestDist: CLLocationDistance = 45
        for station in mapSncbStations {
            let distance = signalLoc.distance(from: CLLocation(latitude: station.lat, longitude: station.lng))
            if distance <= nearestDist {
                nearestDist = distance
                nearest = station
            }
        }
        return nearest
    }

    private func stationWarningStyle(for station: SNCBStation) -> StopWarningStyle? {
        var best: StopWarningStyle?
        let stationLoc = CLLocation(latitude: station.lat, longitude: station.lng)
        for cluster in activeClusters {
            guard let lat = cluster.latitude, let lng = cluster.longitude else { continue }
            let distance = stationLoc.distance(from: CLLocation(latitude: lat, longitude: lng))
            guard distance <= 45 else { continue }
            let style = warningStyle(for: cluster)
            if best == nil || style.rank > (best?.rank ?? 0) {
                best = style
            }
        }
        return best
    }

    private var absorbedSncbClusterIndices: Set<Int> {
        var absorbed = Set<Int>()
        for cluster in activeClusters {
            if colocatedSncbStation(lat: cluster.latitude, lng: cluster.longitude) != nil {
                absorbed.insert(cluster.clusterIndex)
            }
        }
        return absorbed
    }

    /// Highest-rank community signalement sitting on a De Lijn / TEC stop —
    /// drives the warning badge on its marker, mirroring STIB stops / SNCB gares.
    private func operatorStopWarningStyle(for stop: OperatorMapStop) -> StopWarningStyle? {
        var best: StopWarningStyle?
        let stopLoc = CLLocation(latitude: stop.lat, longitude: stop.lng)
        for cluster in activeClusters {
            guard let lat = cluster.latitude, let lng = cluster.longitude else { continue }
            guard stopLoc.distance(from: CLLocation(latitude: lat, longitude: lng)) <= 40 else { continue }
            let style = warningStyle(for: cluster)
            if best == nil || style.rank > (best?.rank ?? 0) {
                best = style
            }
        }
        return best
    }

    /// Clusters now shown as a badge on a De Lijn / TEC stop — hidden as a
    /// standalone pin so we don't draw two markers on the same spot.
    private var absorbedOperatorClusterIndices: Set<Int> {
        guard !mapOperatorStops.isEmpty else { return [] }
        var absorbed = Set<Int>()
        for cluster in activeClusters {
            guard let lat = cluster.latitude, let lng = cluster.longitude else { continue }
            let clusterLoc = CLLocation(latitude: lat, longitude: lng)
            if mapOperatorStops.contains(where: {
                CLLocation(latitude: $0.lat, longitude: $0.lng).distance(from: clusterLoc) <= 40
            }) {
                absorbed.insert(cluster.clusterIndex)
            }
        }
        return absorbed
    }

    /// Official alerts can arrive through two feeds at once: active clusters
    /// and traveller-information signal points. At street zoom the clusterer
    /// deliberately stops merging pins, so without this guard we draw a blue
    /// "official cluster" directly on top of the red STIB warning pin.
    private func isDuplicateOfficialCluster(_ cluster: ClusterDTO) -> Bool {
        guard cluster.isOfficial, let lat = cluster.latitude, let lng = cluster.longitude else { return false }
        return isNearOfficialSignal(latitude: lat, longitude: lng)
    }

    private func isNearOfficialSignal(latitude: Double, longitude: Double) -> Bool {
        let location = CLLocation(latitude: latitude, longitude: longitude)

        for point in routeOfficialSignalPoints {
            let distance = location.distance(
                from: CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
            )
            if distance <= Self.officialMarkerDedupMeters { return true }
        }

        for point in officialSignalPoints {
            let distance = location.distance(
                from: CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
            )
            if distance <= Self.officialMarkerDedupMeters { return true }
        }

        return false
    }

    private func isDuplicateRouteOfficialPoint(_ point: HomeView.LiveSignalPoint) -> Bool {
        let location = CLLocation(latitude: point.coordinate.latitude, longitude: point.coordinate.longitude)
        return routeOfficialSignalPoints.contains { routePoint in
            location.distance(
                from: CLLocation(latitude: routePoint.coordinate.latitude, longitude: routePoint.coordinate.longitude)
            ) <= Self.officialMarkerDedupMeters
        }
    }

    /// Resolves which displayed stops currently host an active signalement —
    /// community cluster OR official STIB incident. Returns the per-stop badge
    /// style (highest-rank issue wins when several share a stop) plus the
    /// signal ids to hide so no standalone pin is drawn over a badged stop.
    private var stopWarningColocation: (
        styles: [String: StopWarningStyle],
        absorbedClusterIndices: Set<Int>,
        absorbedOfficialIds: Set<String>
    ) {
        var styles: [String: StopWarningStyle] = [:]
        var absorbedClusters: Set<Int> = []
        var absorbedOfficial: Set<String> = []

        func register(_ stopId: String, _ style: StopWarningStyle) {
            if let existing = styles[stopId], existing.rank >= style.rank { return }
            styles[stopId] = style
        }

        for cluster in activeClusters {
            guard let match = colocatedStop(stopId: cluster.arretId, lat: cluster.latitude, lng: cluster.longitude) else { continue }
            register(match.id, warningStyle(for: cluster))
            absorbedClusters.insert(cluster.clusterIndex)
        }

        for point in officialSignalPoints {
            guard let match = colocatedStop(stopId: nil, lat: point.coordinate.latitude, lng: point.coordinate.longitude) else { continue }
            register(match.id, warningStyle(for: point))
            absorbedOfficial.insert(point.id)
        }

        return (styles, absorbedClusters, absorbedOfficial)
    }

    private var unifiedMarkers: [MapSignalCluster] {
        var inputs: [MapSignalClusterer.Input] = []
        let coloc = stopWarningColocation

        for cluster in activeClusters {
            // Skip clusters now represented as a badge on a stop marker.
            if coloc.absorbedClusterIndices.contains(cluster.clusterIndex) { continue }
            if absorbedSncbClusterIndices.contains(cluster.clusterIndex) { continue }
            if absorbedOperatorClusterIndices.contains(cluster.clusterIndex) { continue }
            if isDuplicateOfficialCluster(cluster) { continue }
            guard let lat = cluster.latitude, let lng = cluster.longitude else { continue }
            inputs.append(MapSignalClusterer.Input(
                id: "c-\(cluster.clusterIndex)",
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                typeProbleme: cluster.typeProbleme,
                origin: .community
            ))
        }

        for point in officialSignalPoints {
            // Skip official incidents now shown as a badge on a stop marker.
            if coloc.absorbedOfficialIds.contains(point.id) { continue }
            if isDuplicateRouteOfficialPoint(point) { continue }
            inputs.append(MapSignalClusterer.Input(
                id: "o-\(point.id)",
                coordinate: point.coordinate,
                typeProbleme: point.typeProbleme,
                origin: .official
            ))
        }

        return MapSignalClusterer.cluster(points: inputs, latitudeDelta: cameraLatitudeDelta)
    }

    @MapContentBuilder
    private var communityClusterAnnotations: some MapContent {
        ForEach(unifiedMarkers) { group in
            if group.count > 1 {
                Annotation("", coordinate: group.coordinate, anchor: .center) {
                    Button {
                        onSelectClusterCount(group.coordinate)
                    } label: {
                        ClusterCountMarker(count: group.count, origin: group.dominantOrigin)
                    }
                    .buttonStyle(.plain)
                }
            } else if let sampleId = group.sampleIds.first {
                singletonMarker(coordinate: group.coordinate, sampleId: sampleId)
            }
        }
    }

    @MapContentBuilder
    private func singletonMarker(coordinate: CLLocationCoordinate2D, sampleId: String) -> some MapContent {
        if sampleId.hasPrefix("c-"),
           let cluster = communityCluster(forSampleId: sampleId) {
            Annotation("", coordinate: coordinate, anchor: .bottom) {
                Button {
                    onSelectCluster(cluster)
                } label: {
                    ClusterMarker(cluster: cluster, isSelected: selectedClusterIndex == cluster.clusterIndex)
                }
                .buttonStyle(.plain)
            }
        } else if sampleId.hasPrefix("o-"),
                  let point = officialPoint(forSampleId: sampleId) {
            Annotation("", coordinate: coordinate, anchor: .bottom) {
                Button { onOpenPreview(point.id) } label: {
                    OfficialSignalMarker(problemType: point.typeProbleme)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func communityCluster(forSampleId id: String) -> ClusterDTO? {
        guard let index = Int(id.dropFirst(2)) else { return nil }
        return activeClusters.first(where: { $0.clusterIndex == index })
    }

    private func officialPoint(forSampleId id: String) -> HomeView.LiveSignalPoint? {
        let signalId = String(id.dropFirst(2))
        return officialSignalPoints.first(where: { $0.id == signalId })
    }

    @MapContentBuilder
    private var vehicleAnnotations: some MapContent {
        ForEach(mapVehicles) { vehicle in
            if let coordinate = positionedVehicleCoordinate(for: vehicle) {
                Annotation("", coordinate: coordinate, anchor: .center) {
                    Button {
                        onSelectVehicle(vehicle)
                    } label: {
                        VehicleMarker(
                            vehicle: vehicle,
                            bearing: vehicle.vehicleId.flatMap { vehicleBearings[$0] }
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    // MARK: - Vehicle positioning along the tracé
    //
    // Le backend cale chaque véhicule sur son arrêt de référence (`pointId`) et
    // fournit `distanceFromPoint` = distance réelle à cet arrêt. Plutôt que de
    // l'afficher figé SUR l'arrêt (trams empilés / cachés sous une carte), on
    // projette la coordonnée d'arrêt sur la polyline de la ligne et on avance de
    // `distanceFromPoint` mètres le long du tracé, du côté d'où vient le tram
    // (il approche son arrêt de référence). Le sens est déduit du cap connu
    // (`vehicleBearings`, calculé sur le déplacement réel entre 2 polls).
    // Repli SÛR sur la position d'origine si pas de cap / pas de tracé : on ne
    // place jamais un tram du mauvais côté.

    /// Coordonnée d'affichage du véhicule, replacé le long du tracé si possible.
    private func positionedVehicleCoordinate(for vehicle: TransportVehicleDTO) -> CLLocationCoordinate2D? {
        guard let lat = vehicle.latitude, let lng = vehicle.longitude else { return nil }
        let stopCoord = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        let offset = Double(vehicle.distanceFromPoint ?? 0)
        guard offset >= 25 else { return stopCoord }                       // quasi à l'arrêt
        guard let bearing = vehicle.vehicleId.flatMap({ vehicleBearings[$0] }) else { return stopCoord }
        guard let line = vehicle.line,
              let coords = bestShapeCoordinates(forLine: line, near: stopCoord) else { return stopCoord }

        return Self.pointAlongShape(coords, from: stopCoord, distance: offset, travelHeading: bearing) ?? stopCoord
    }

    /// Tracé de la ligne `line` passant le plus près de `coord` (gère les
    /// variantes/directions multiples).
    private func bestShapeCoordinates(forLine line: String, near coord: CLLocationCoordinate2D) -> [CLLocationCoordinate2D]? {
        guard let number = LineShapesLoader.normalizedLineNumber(from: line) else { return nil }
        let candidates = (selectedStopLineShapes + visibleLineShapes).filter {
            LineShapesLoader.normalizedLineNumber(from: $0.ligne) == number
        }
        guard !candidates.isEmpty else { return nil }
        return candidates
            .min { Self.minVertexDistance(coord, $0.coordinates) < Self.minVertexDistance(coord, $1.coordinates) }?
            .coordinates
    }

    /// Projette `from` sur la polyline (sommet le plus proche) puis avance de
    /// `distance` m du côté d'où vient le tram (tangente ≈ cap inverse, car il
    /// approche son arrêt de référence). nil si la polyline est trop courte.
    private static func pointAlongShape(
        _ coords: [CLLocationCoordinate2D],
        from: CLLocationCoordinate2D,
        distance: Double,
        travelHeading: Double
    ) -> CLLocationCoordinate2D? {
        guard coords.count >= 2 else { return nil }

        let p = CLLocation(latitude: from.latitude, longitude: from.longitude)
        var anchor = 0
        var bestD = Double.greatestFiniteMagnitude
        for (i, c) in coords.enumerated() {
            let d = p.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < bestD { bestD = d; anchor = i }
        }

        // Le tram est EN AMONT de son arrêt de référence → on marche dans le
        // sens opposé à sa circulation (tangente ≈ cap + 180°).
        let target = (travelHeading + 180).truncatingRemainder(dividingBy: 360)
        let fwd = tangentBearing(coords, at: anchor, forward: true)
        let bwd = tangentBearing(coords, at: anchor, forward: false)
        let goForward = angularDelta(fwd, target) <= angularDelta(bwd, target)

        return walkAlong(coords, fromIndex: anchor, distance: distance, forward: goForward)
    }

    private static func minVertexDistance(_ coord: CLLocationCoordinate2D, _ coords: [CLLocationCoordinate2D]) -> Double {
        let p = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        var best = Double.greatestFiniteMagnitude
        for c in coords {
            let d = p.distance(from: CLLocation(latitude: c.latitude, longitude: c.longitude))
            if d < best { best = d }
        }
        return best
    }

    private static func tangentBearing(_ coords: [CLLocationCoordinate2D], at i: Int, forward: Bool) -> Double {
        let j = forward ? min(i + 1, coords.count - 1) : max(i - 1, 0)
        guard i != j else { return 0 }
        return forward ? bearing(from: coords[i], to: coords[j]) : bearing(from: coords[j], to: coords[i])
    }

    private static func walkAlong(
        _ coords: [CLLocationCoordinate2D],
        fromIndex: Int,
        distance: Double,
        forward: Bool
    ) -> CLLocationCoordinate2D {
        var remaining = distance
        var current = coords[fromIndex]
        var idx = fromIndex
        while remaining > 0 {
            let nextIdx = forward ? idx + 1 : idx - 1
            guard nextIdx >= 0, nextIdx < coords.count else { return current }
            let next = coords[nextIdx]
            let segLen = CLLocation(latitude: current.latitude, longitude: current.longitude)
                .distance(from: CLLocation(latitude: next.latitude, longitude: next.longitude))
            if segLen >= remaining, segLen > 0 {
                let t = remaining / segLen
                return CLLocationCoordinate2D(
                    latitude: current.latitude + (next.latitude - current.latitude) * t,
                    longitude: current.longitude + (next.longitude - current.longitude) * t
                )
            }
            remaining -= segLen
            idx = nextIdx
            current = next
        }
        return current
    }

    private static func bearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    /// Plus petit écart angulaire (0-180) entre deux caps.
    private static func angularDelta(_ a: Double, _ b: Double) -> Double {
        let d = abs(a - b).truncatingRemainder(dividingBy: 360)
        return d > 180 ? 360 - d : d
    }

    @MapContentBuilder
    private var stopAnnotations: some MapContent {
        let warningStyles = stopWarningColocation.styles
        ForEach(mapStops) { stop in
            if let latitude = stop.latitude, let longitude = stop.longitude {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                    Button {
                        onOpenStopPreview(stop)
                    } label: {
                        HomeStopMarker(
                            stop: stop,
                            isSelected: selectedMapStopPreview?.id == stop.id || selectedMapStopSummary?.id == stop.id,
                            warningStyle: warningStyles[stop.id],
                            isFavorite: favoriteStopIds.contains(stop.id),
                            isLoading: loadingMapStopId == stop.id
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    @MapContentBuilder
    private var sncbStationAnnotations: some MapContent {
        ForEach(mapSncbStations) { station in
            Annotation("", coordinate: station.coordinate, anchor: .bottom) {
                Button {
                    onSelectSncbStation(station)
                } label: {
                    SNCBStationMarker(
                        station: station,
                        isSelected: selectedSncbStation?.id == station.id,
                        warningStyle: stationWarningStyle(for: station),
                        isFavorite: favoriteGareIds.contains(station.id)
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MapContentBuilder
    private var operatorStopAnnotations: some MapContent {
        ForEach(mapOperatorStops) { stop in
            Annotation("", coordinate: stop.coordinate, anchor: .bottom) {
                Button {
                    onSelectOperatorStop(stop)
                } label: {
                    OperatorStopMarker(
                        stop: stop,
                        warningStyle: operatorStopWarningStyle(for: stop),
                        isFavorite: favoriteOperatorStopKeys.contains("\(stop.op.rawValue):\(stop.id)")
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MapContentBuilder
    private var villoAnnotations: some MapContent {
        ForEach(mapVilloStations) { station in
            Annotation("", coordinate: station.coordinate, anchor: .bottom) {
                Button {
                    onSelectVilloStation(station)
                } label: {
                    VilloMapMarker(station: station)
                }
                .buttonStyle(.plain)
            }
        }
    }

    @MapContentBuilder
    private var eventAnnotations: some MapContent {
        ForEach(mapEventImpacts) { event in
            if let latitude = event.latitude, let longitude = event.longitude {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                    Button {
                        onSelectEventImpact(event)
                    } label: {
                        EventMapMarker(event: event)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
