import SwiftUI
import GoogleMaps3D
import UIKit

struct SearchTransitMapView: View {
    let selectedScope: SearchScope
    let journey: SearchJourney?

    init(selectedScope: SearchScope, journey: SearchJourney?) {
        self.selectedScope = selectedScope
        self.journey = journey
        Map.apiKey = AppConfig.googleMaps3DAPIKey
    }

    private var visibleRoutes: [TransitRoute3D] {
        switch selectedScope {
        case .all, .stops:
            return TransitMapMockData.routes
        case .metro:
            return TransitMapMockData.routes.filter { $0.mode == .metro }
        case .tram:
            return TransitMapMockData.routes.filter { $0.mode == .tram }
        case .bus:
            return TransitMapMockData.routes.filter { $0.mode == .bus }
        }
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 0.22)) { timeline in
            SearchTransitMapScene(
                routes: visibleRoutes,
                journey: journey,
                date: timeline.date
            )
        }
    }
}

private struct SearchTransitMapScene: View {
    let routes: [TransitRoute3D]
    let journey: SearchJourney?
    let date: Date

    private var vehicleMarkers: [TransitVehicleMarkerInfo] {
        routes.flatMap { route in
            route.vehicles.map { vehicle in
                .init(
                    route: route,
                    vehicle: vehicle,
                    position: route.position(
                        for: vehicle,
                        at: date.timeIntervalSinceReferenceDate
                    )
                )
            }
        }
    }

    private var routeOverlay: [SearchJourney] {
        journey.map { [$0] } ?? []
    }

    private var nearbyVehicleLabels: Set<String> {
        Set(journey?.nearbyVehicles.map(\.label) ?? [])
    }

    private var nearbyRouteCodes: Set<String> {
        Set(journey?.nearbyVehicles.map(\.routeCode) ?? [])
    }

    private var journeyMarkers: [JourneyMarkerInfo] {
        guard let journey else { return [] }
        return [
            .init(
                kind: .origin,
                title: journey.origin.name,
                position: journey.origin.coordinate
            ),
            .init(
                kind: .destination,
                title: journey.destination.name,
                position: journey.destination.coordinate
            )
        ]
    }

    private var camera: Camera {
        guard let journey, !journey.path.isEmpty else {
            return .init(
                center: .init(
                    latitude: 50.84673,
                    longitude: 4.35247,
                    altitude: 260
                ),
                heading: 18,
                tilt: 58,
                range: 2400
            )
        }

        let latitudes = journey.path.map(\.latitude)
        let longitudes = journey.path.map(\.longitude)
        let minLat = latitudes.min() ?? 50.84673
        let maxLat = latitudes.max() ?? 50.84673
        let minLon = longitudes.min() ?? 4.35247
        let maxLon = longitudes.max() ?? 4.35247
        let centerLat = (minLat + maxLat) / 2
        let centerLon = (minLon + maxLon) / 2

        let latMeters = max(400, (maxLat - minLat) * 111_000)
        let lonMeters = max(400, (maxLon - minLon) * 111_000 * cos(centerLat * .pi / 180))
        let extent = max(latMeters, lonMeters)
        let range = min(max(extent * 2.4, 900), 5000)

        return .init(
            center: .init(
                latitude: centerLat,
                longitude: centerLon,
                altitude: 240
            ),
            heading: 12,
            tilt: 54,
            range: range
        )
    }

    private var mapIdentity: String {
        guard let journey else { return "default-map" }
        return "\(journey.origin.id)-\(journey.destination.id)-\(journey.path.count)"
    }

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            Map(
                initialCamera: camera,
                mode: .hybrid
            ) {
                ForEach(routes) { route in
                    Polyline(path: route.path)
                        .stroke(
                            .init(
                                strokeColor: route.strokeColor,
                                strokeWidth: nearbyRouteCodes.contains(route.code) ? 6.5 : 4.5,
                                outerColor: route.strokeColor.withAlphaComponent(nearbyRouteCodes.contains(route.code) ? 0.35 : 0.18),
                                outerWidth: nearbyRouteCodes.contains(route.code) ? 12 : 8
                            )
                        )
                        .contour(.init(geodesic: true, extruded: false, drawOccludedSegments: false))
                }

                ForEach(routeOverlay, id: \.destination.id) { journey in
                    Polyline(path: journey.path)
                        .stroke(
                            .init(
                                strokeColor: UIColor.white,
                                strokeWidth: 7,
                                outerColor: UIColor(red: 0.796, green: 0.757, blue: 0.678, alpha: 0.75),
                                outerWidth: 13
                            )
                        )
                        .contour(.init(geodesic: true, extruded: false, drawOccludedSegments: false))
                }

                ForEach(vehicleMarkers) { marker in
                    Marker(
                        position: marker.position,
                        label: marker.vehicle.label,
                        style: .pin(
                            .init(
                                backgroundColor: marker.route.color,
                                borderColor: marker.route.color.opacity(0.9),
                                scale: nearbyVehicleLabels.contains(marker.vehicle.label) ? 1.08 : 0.82
                            ) {
                                Image(systemName: marker.route.icon)
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        )
                    )
                }

                ForEach(journeyMarkers) { marker in
                    Marker(
                        position: marker.position,
                        label: marker.title,
                        style: .pin(
                            .init(
                                backgroundColor: marker.kind == .origin ? DesignSystem.Colors.success : DesignSystem.Colors.accentSand,
                                borderColor: .white.opacity(0.85),
                                scale: 1.0
                            ) {
                                Image(systemName: marker.kind == .origin ? "circle.fill" : "mappin.circle.fill")
                                    .font(.system(size: 11, weight: .bold))
                                    .foregroundStyle(.white)
                            }
                        )
                    )
                }
            }
            .id(mapIdentity)
            .ignoresSafeArea()

            VStack(alignment: .trailing, spacing: 8) {
                HStack(spacing: 6) {
                    Image(systemName: "cube.transparent")
                    Text("3D")
                }

                Text("Brussels")
            }
            .font(DesignSystem.Typography.labelSemibold)
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .padding(.trailing, 18)
            .padding(.bottom, 182)
        }
    }
}

struct TransitRoute3D: Identifiable {
    enum Mode {
        case metro
        case tram
        case bus
    }

    let id = UUID()
    let code: String
    let mode: Mode
    let color: Color
    let strokeColor: UIColor
    let icon: String
    let path: [LatLngAltitude]
    let vehicles: [TransitVehicle3D]

    func position(for vehicle: TransitVehicle3D, at time: TimeInterval) -> LatLngAltitude {
        let segments = zip(path, path.dropFirst()).map { ($0, $1) }
        guard !segments.isEmpty else { return path.first ?? .init(latitude: 50.84673, longitude: 4.35247) }

        let segmentLengths = segments.map { approximateDistance(from: $0.0, to: $0.1) }
        let totalLength = max(segmentLengths.reduce(0, +), 0.000_1)
        let cycleProgress = (vehicle.startOffset + time * vehicle.speed).truncatingRemainder(dividingBy: 1)
        let targetDistance = totalLength * cycleProgress

        var traversed = 0.0
        for (index, segment) in segments.enumerated() {
            let length = segmentLengths[index]
            if traversed + length >= targetDistance {
                let localProgress = length == 0 ? 0 : (targetDistance - traversed) / length
                return interpolate(from: segment.0, to: segment.1, progress: localProgress)
            }
            traversed += length
        }

        return path.last ?? segments[0].1
    }

    private func interpolate(from start: LatLngAltitude, to end: LatLngAltitude, progress: Double) -> LatLngAltitude {
        .init(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress,
            altitude: start.altitude + (end.altitude - start.altitude) * progress
        )
    }

    private func approximateDistance(from start: LatLngAltitude, to end: LatLngAltitude) -> Double {
        let latScale = 111_000.0
        let lonScale = 111_000.0 * cos(((start.latitude + end.latitude) / 2.0) * .pi / 180.0)
        let dx = (end.longitude - start.longitude) * lonScale
        let dy = (end.latitude - start.latitude) * latScale
        return sqrt(dx * dx + dy * dy)
    }
}

struct TransitVehicle3D: Identifiable {
    let id = UUID()
    let label: String
    let startOffset: Double
    let speed: Double
}

private struct TransitVehicleMarkerInfo: Identifiable {
    let id = UUID()
    let route: TransitRoute3D
    let vehicle: TransitVehicle3D
    let position: LatLngAltitude
}

private struct JourneyMarkerInfo: Identifiable {
    enum Kind {
        case origin
        case destination
    }

    let id = UUID()
    let kind: Kind
    let title: String
    let position: LatLngAltitude
}

enum TransitMapMockData {
    static let routes: [TransitRoute3D] = [
        .init(
            code: "M6",
            mode: .metro,
            color: Color(hex: "#1AA35F"),
            strokeColor: UIColor(red: 0.102, green: 0.639, blue: 0.373, alpha: 1),
            icon: "m.circle.fill",
            path: [
                .init(latitude: 50.8949, longitude: 4.3417),
                .init(latitude: 50.8758, longitude: 4.3455),
                .init(latitude: 50.8559, longitude: 4.3603),
                .init(latitude: 50.8466, longitude: 4.3572),
                .init(latitude: 50.8386, longitude: 4.3512),
            ],
            vehicles: [
                .init(label: "M6-1", startOffset: 0.12, speed: 0.017),
                .init(label: "M6-2", startOffset: 0.56, speed: 0.015),
            ]
        ),
        .init(
            code: "T7",
            mode: .tram,
            color: Color(hex: "#D7263D"),
            strokeColor: UIColor(red: 0.843, green: 0.149, blue: 0.239, alpha: 1),
            icon: "tram.fill",
            path: [
                .init(latitude: 50.8932, longitude: 4.3360),
                .init(latitude: 50.8771, longitude: 4.3442),
                .init(latitude: 50.8538, longitude: 4.3520),
                .init(latitude: 50.8310, longitude: 4.3674),
                .init(latitude: 50.8138, longitude: 4.3815),
            ],
            vehicles: [
                .init(label: "T7-1", startOffset: 0.08, speed: 0.013),
                .init(label: "T7-2", startOffset: 0.44, speed: 0.014),
            ]
        ),
        .init(
            code: "B95",
            mode: .bus,
            color: Color(hex: "#4557A1"),
            strokeColor: UIColor(red: 0.271, green: 0.341, blue: 0.631, alpha: 1),
            icon: "bus.fill",
            path: [
                .init(latitude: 50.8138, longitude: 4.3815),
                .init(latitude: 50.8283, longitude: 4.3736),
                .init(latitude: 50.8466, longitude: 4.3572),
                .init(latitude: 50.8559, longitude: 4.3603),
                .init(latitude: 50.8624, longitude: 4.3669),
            ],
            vehicles: [
                .init(label: "B95-1", startOffset: 0.20, speed: 0.015),
                .init(label: "B95-2", startOffset: 0.68, speed: 0.014),
            ]
        ),
    ]
}
