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
    let destinationCoordinate: CLLocationCoordinate2D?
    let officialSignalPoints: [HomeView.LiveSignalPoint]
    let routeOfficialSignalPoints: [HomeView.RouteOfficialSignalPoint]
    let activeClusters: [ClusterDTO]
    let selectedClusterIndex: Int?
    let cameraLatitudeDelta: Double
    let mapVehicles: [TransportVehicleDTO]
    let vehicleBearings: [String: Double]
    let mapStops: [TransportStopSummaryDTO]
    let selectedMapStopPreview: TransportStopSummaryDTO?
    let selectedMapStopSummary: TransportStopSummaryDTO?
    let mapVilloStations: [VilloStation]
    let mapEventImpacts: [TransportEventImpactDTO]
    let onOpenPreview: (String) -> Void
    let onOpenStopPreview: (TransportStopSummaryDTO) -> Void
    let onSelectCluster: (ClusterDTO) -> Void
    let onSelectClusterCount: (CLLocationCoordinate2D) -> Void
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
            villoAnnotations
            eventAnnotations
            // Vehicles render LAST so their pins sit on top of every other
            // annotation — without this a tram that lands on the same pixel
            // as the user-location dot or a stop marker would visually vanish
            // even though it's actually there.
            vehicleAnnotations
        }
        .mapStyle(.standard(elevation: .realistic))
        .environment(\.colorScheme, .light)
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
            .foregroundStyle(DS.Color.foreground.opacity(0.07))
            .stroke(DS.Color.info.opacity(0.6), lineWidth: 1)

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
            if let lat = vehicle.latitude, let lng = vehicle.longitude {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .center) {
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
                            warningStyle: warningStyles[stop.id]
                        )
                    }
                    .buttonStyle(.plain)
                }
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
