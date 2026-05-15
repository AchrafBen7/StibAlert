import MapKit
import SwiftUI

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
    let onCameraChanged: (MKCoordinateRegion) -> Void

    var body: some View {
        Map(position: $mapPosition) {
            lineShapeOverlays
            userLocationOverlay
            routeOverlays
            officialIncidentAnnotations
            communityClusterAnnotations
            vehicleAnnotations
            stopAnnotations
            villoAnnotations
            eventAnnotations
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
        MapCircle(center: displayCoordinate, radius: 200)
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
        ForEach(officialSignalPoints) { point in
            Annotation("", coordinate: point.coordinate, anchor: .bottom) {
                Button { onOpenPreview(point.id) } label: {
                    OfficialSignalMarker(problemType: point.typeProbleme)
                }
                .buttonStyle(.plain)
            }
        }

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

    private var clusteredCommunityMarkers: [MapSignalCluster] {
        let inputs: [MapSignalClusterer.Input] = activeClusters.compactMap { cluster in
            guard let lat = cluster.latitude, let lng = cluster.longitude else { return nil }
            return MapSignalClusterer.Input(
                id: String(cluster.clusterIndex),
                coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng),
                typeProbleme: cluster.typeProbleme
            )
        }
        return MapSignalClusterer.cluster(points: inputs, latitudeDelta: cameraLatitudeDelta)
    }

    @MapContentBuilder
    private var communityClusterAnnotations: some MapContent {
        ForEach(clusteredCommunityMarkers) { group in
            if group.count > 1 {
                Annotation("", coordinate: group.coordinate, anchor: .center) {
                    Button {
                        onSelectClusterCount(group.coordinate)
                    } label: {
                        ClusterCountMarker(count: group.count)
                    }
                    .buttonStyle(.plain)
                }
            } else if let cluster = singleCluster(forSampleId: group.sampleIds.first) {
                Annotation("", coordinate: group.coordinate, anchor: .bottom) {
                    Button {
                        onSelectCluster(cluster)
                    } label: {
                        ClusterMarker(cluster: cluster, isSelected: selectedClusterIndex == cluster.clusterIndex)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func singleCluster(forSampleId id: String?) -> ClusterDTO? {
        guard let id, let index = Int(id) else { return nil }
        return activeClusters.first(where: { $0.clusterIndex == index })
    }

    @MapContentBuilder
    private var vehicleAnnotations: some MapContent {
        ForEach(mapVehicles) { vehicle in
            if let lat = vehicle.latitude, let lng = vehicle.longitude {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: lat, longitude: lng), anchor: .center) {
                    VehicleMarker(
                        vehicle: vehicle,
                        bearing: vehicle.vehicleId.flatMap { vehicleBearings[$0] }
                    )
                }
            }
        }
    }

    @MapContentBuilder
    private var stopAnnotations: some MapContent {
        ForEach(mapStops) { stop in
            if let latitude = stop.latitude, let longitude = stop.longitude {
                Annotation("", coordinate: CLLocationCoordinate2D(latitude: latitude, longitude: longitude), anchor: .bottom) {
                    Button {
                        onOpenStopPreview(stop)
                    } label: {
                        HomeStopMarker(
                            stop: stop,
                            isSelected: selectedMapStopPreview?.id == stop.id || selectedMapStopSummary?.id == stop.id
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
