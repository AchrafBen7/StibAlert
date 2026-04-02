import SwiftUI
import MapKit
import UIKit

struct SearchTransitMapView: View {
    let selectedScope: SearchScope
    let journey: SearchJourney?

    var body: some View {
        TimelineView(.periodic(from: .now, by: 4)) { context in
            SearchTransitMapRepresentable(
                routes: visibleRoutes,
                journey: journey,
                date: context.date,
                signalClusters: SearchSignalCluster.mockClusters
            )
        }
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
}

private struct SearchTransitMapRepresentable: UIViewRepresentable {
    let routes: [TransitRoute3D]
    let journey: SearchJourney?
    let date: Date
    let signalClusters: [SearchSignalCluster]

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeUIView(context: Context) -> MKMapView {
        let mapView = MKMapView(frame: .zero)
        mapView.delegate = context.coordinator
        mapView.showsCompass = false
        mapView.showsScale = false
        mapView.pointOfInterestFilter = .includingAll
        mapView.mapType = .standard
        mapView.overrideUserInterfaceStyle = .dark
        mapView.isPitchEnabled = true
        mapView.isRotateEnabled = false
        mapView.showsUserLocation = true
        mapView.setCamera(defaultCamera(), animated: false)
        return mapView
    }

    func updateUIView(_ mapView: MKMapView, context: Context) {
        context.coordinator.apply(
            routes: routes,
            journey: journey,
            date: date,
            signalClusters: signalClusters,
            to: mapView
        )
    }

    private func defaultCamera() -> MKMapCamera {
        let camera = MKMapCamera()
        camera.centerCoordinate = CLLocationCoordinate2D(latitude: 50.84673, longitude: 4.35247)
        camera.pitch = 42
        camera.altitude = 5000
        camera.heading = 10
        return camera
    }

    final class Coordinator: NSObject, MKMapViewDelegate {
        func apply(routes: [TransitRoute3D], journey: SearchJourney?, date: Date, signalClusters: [SearchSignalCluster], to mapView: MKMapView) {
            mapView.removeOverlays(mapView.overlays)
            let removableAnnotations = mapView.annotations.filter { !($0 is MKUserLocation) }
            mapView.removeAnnotations(removableAnnotations)

            let nearbyRouteCodes = Set(journey?.nearbyVehicles.map(\.routeCode) ?? [])

            if journey != nil {
                for route in routes {
                    let polyline = MKPolyline(coordinates: route.path.map(\.coordinate), count: route.path.count)
                    polyline.title = nearbyRouteCodes.contains(route.code) ? "highlight:\(route.code)" : "route:\(route.code)"
                    mapView.addOverlay(polyline)
                }
            }

            if let journey, !journey.path.isEmpty {
                let polyline = MKPolyline(coordinates: journey.path.map(\.coordinate), count: journey.path.count)
                polyline.title = "journey"
                mapView.addOverlay(polyline)

                mapView.addAnnotations([
                    SearchMapAnnotation(
                        coordinate: journey.origin.coordinate.coordinate,
                        title: journey.origin.name,
                        kind: .origin
                    ),
                    SearchMapAnnotation(
                        coordinate: journey.destination.coordinate.coordinate,
                        title: journey.destination.name,
                        kind: .destination
                    )
                ])
            }

            let signalAnnotations = signalClusters.map {
                SearchMapAnnotation(
                    coordinate: $0.coordinate.coordinate,
                    title: "\($0.count)",
                    subtitle: nil,
                    kind: .signal($0.level, $0.count)
                )
            }
            mapView.addAnnotations(signalAnnotations)

            updateCamera(on: mapView, journey: journey, routes: routes)
        }

        private func updateCamera(on mapView: MKMapView, journey: SearchJourney?, routes: [TransitRoute3D]) {
            if let journey, !journey.path.isEmpty {
                let rect = mapRect(for: journey.path)
                mapView.setVisibleMapRect(
                    rect,
                    edgePadding: UIEdgeInsets(top: 170, left: 48, bottom: 220, right: 48),
                    animated: true
                )
                return
            }

            let allPoints = routes.flatMap(\.path)
            guard !allPoints.isEmpty else { return }
            let rect = mapRect(for: allPoints)
            mapView.setVisibleMapRect(
                rect,
                edgePadding: UIEdgeInsets(top: 160, left: 36, bottom: 180, right: 36),
                animated: false
            )
        }

        private func mapRect(for points: [TransitCoordinate]) -> MKMapRect {
            let mapPoints = points.map { MKMapPoint($0.coordinate) }
            guard let first = mapPoints.first else { return .world }

            return mapPoints.dropFirst().reduce(
                MKMapRect(origin: first, size: MKMapSize(width: 0, height: 0))
            ) { partial, point in
                partial.union(MKMapRect(origin: point, size: MKMapSize(width: 0, height: 0)))
            }
        }

        func mapView(_ mapView: MKMapView, rendererFor overlay: MKOverlay) -> MKOverlayRenderer {
            guard let polyline = overlay as? MKPolyline else {
                return MKOverlayRenderer(overlay: overlay)
            }

            let renderer = MKPolylineRenderer(polyline: polyline)
            renderer.lineJoin = .round
            renderer.lineCap = .round

            switch polyline.title ?? "" {
            case "journey":
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.92)
                renderer.lineWidth = 5
            case let title where title.hasPrefix("highlight:"):
                renderer.strokeColor = UIColor(DesignSystem.Colors.accentSand)
                renderer.alpha = 0.55
                renderer.lineWidth = 4
            default:
                renderer.strokeColor = UIColor.white.withAlphaComponent(0.14)
                renderer.lineWidth = 2.5
            }

            return renderer
        }

        func mapView(_ mapView: MKMapView, viewFor annotation: MKAnnotation) -> MKAnnotationView? {
            guard let annotation = annotation as? SearchMapAnnotation else { return nil }

            switch annotation.kind {
            case .signal:
                let identifier = "search-signal-annotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? SearchSignalAnnotationView
                    ?? SearchSignalAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.configure(with: annotation)
                return view
            case .origin, .destination:
                let identifier = "search-marker-annotation"
                let view = mapView.dequeueReusableAnnotationView(withIdentifier: identifier) as? MKMarkerAnnotationView
                    ?? MKMarkerAnnotationView(annotation: annotation, reuseIdentifier: identifier)
                view.annotation = annotation
                view.glyphTintColor = .white
                view.markerTintColor = annotation.tintColor
                view.titleVisibility = .hidden
                view.subtitleVisibility = .hidden
                view.displayPriority = .defaultHigh

                switch annotation.kind {
                case .origin:
                    view.glyphImage = UIImage(systemName: "circle.fill")
                case .destination:
                    view.glyphImage = UIImage(systemName: "mappin.circle.fill")
                default:
                    break
                }
                return view
            case .vehicle:
                return nil
            }
        }
    }
}

private final class SearchMapAnnotation: NSObject, MKAnnotation {
    enum Kind {
        case origin
        case destination
        case vehicle(Color)
        case signal(SearchSignalCluster.Level, Int)
    }

    let coordinate: CLLocationCoordinate2D
    let title: String?
    let subtitle: String?
    let kind: Kind

    init(coordinate: CLLocationCoordinate2D, title: String?, subtitle: String? = nil, kind: Kind) {
        self.coordinate = coordinate
        self.title = title
        self.subtitle = subtitle
        self.kind = kind
    }

    var tintColor: UIColor {
        switch kind {
        case .origin:
            return UIColor(DesignSystem.Colors.success)
        case .destination:
            return UIColor(DesignSystem.Colors.accentSand)
        case .vehicle(let color):
            return UIColor(color)
        case .signal(let level, _):
            return level.color
        }
    }
}

private final class SearchSignalAnnotationView: MKAnnotationView {
    private let bubbleView = UIView()
    private let countLabel = UILabel()
    private let pointerLayer = CAShapeLayer()

    override init(annotation: MKAnnotation?, reuseIdentifier: String?) {
        super.init(annotation: annotation, reuseIdentifier: reuseIdentifier)
        frame = CGRect(x: 0, y: 0, width: 34, height: 34)
        centerOffset = CGPoint(x: 0, y: -17)

        bubbleView.frame = CGRect(x: 3, y: 0, width: 28, height: 28)
        bubbleView.layer.cornerRadius = 14
        bubbleView.clipsToBounds = true
        addSubview(bubbleView)

        countLabel.font = UIFont.systemFont(ofSize: 12, weight: .bold)
        countLabel.textAlignment = .center
        countLabel.textColor = .black
        countLabel.frame = bubbleView.bounds
        bubbleView.addSubview(countLabel)

        layer.addSublayer(pointerLayer)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func configure(with annotation: SearchMapAnnotation) {
        guard case let .signal(level, count) = annotation.kind else { return }

        bubbleView.backgroundColor = level.color
        countLabel.text = "\(count)"

        let width: CGFloat = count > 9 ? 32 : 28
        frame = CGRect(x: 0, y: 0, width: width + 6, height: 34)
        bubbleView.frame = CGRect(x: 3, y: 0, width: width, height: 28)
        bubbleView.layer.cornerRadius = 14
        countLabel.frame = bubbleView.bounds

        let path = UIBezierPath()
        let midX = bubbleView.frame.midX
        path.move(to: CGPoint(x: midX - 6, y: 25))
        path.addLine(to: CGPoint(x: midX, y: 34))
        path.addLine(to: CGPoint(x: midX + 6, y: 25))
        path.close()
        pointerLayer.path = path.cgPath
        pointerLayer.fillColor = level.color.cgColor
    }
}

struct SearchSignalCluster {
    enum Level {
        case low
        case medium
        case high

        var color: UIColor {
            switch self {
            case .low:
                return UIColor(Color(hex: "#9DFD7C"))
            case .medium:
                return UIColor(Color(hex: "#FCBF81"))
            case .high:
                return UIColor(Color(hex: "#FAB3B2"))
            }
        }
    }

    let coordinate: TransitCoordinate
    let count: Int

    var level: Level {
        switch count {
        case ..<3:
            return .low
        case 3..<8:
            return .medium
        default:
            return .high
        }
    }

    static let mockClusters: [SearchSignalCluster] = [
        .init(coordinate: .init(latitude: 50.8764, longitude: 4.3340), count: 0),
        .init(coordinate: .init(latitude: 50.8646, longitude: 4.3378), count: 4),
        .init(coordinate: .init(latitude: 50.8532, longitude: 4.3332), count: 14),
        .init(coordinate: .init(latitude: 50.8470, longitude: 4.3362), count: 10),
        .init(coordinate: .init(latitude: 50.8558, longitude: 4.3538), count: 1),
        .init(coordinate: .init(latitude: 50.8655, longitude: 4.3578), count: 1),
        .init(coordinate: .init(latitude: 50.8445, longitude: 4.3675), count: 0),
        .init(coordinate: .init(latitude: 50.8363, longitude: 4.3473), count: 5),
        .init(coordinate: .init(latitude: 50.8587, longitude: 4.3796), count: 0),
        .init(coordinate: .init(latitude: 50.8692, longitude: 4.3638), count: 0)
    ]
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
    let icon: String
    let path: [TransitCoordinate]
    let vehicles: [TransitVehicle3D]

    func position(for vehicle: TransitVehicle3D, at time: TimeInterval) -> TransitCoordinate {
        let segments = zip(path, path.dropFirst()).map { ($0, $1) }
        guard !segments.isEmpty else {
            return path.first ?? .init(latitude: 50.84673, longitude: 4.35247)
        }

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

    func vehicleAnnotations(at time: TimeInterval) -> [(label: String, coordinate: TransitCoordinate)] {
        vehicles.map { vehicle in
            (vehicle.label, position(for: vehicle, at: time))
        }
    }

    private func interpolate(from start: TransitCoordinate, to end: TransitCoordinate, progress: Double) -> TransitCoordinate {
        .init(
            latitude: start.latitude + (end.latitude - start.latitude) * progress,
            longitude: start.longitude + (end.longitude - start.longitude) * progress
        )
    }

    private func approximateDistance(from start: TransitCoordinate, to end: TransitCoordinate) -> Double {
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

enum TransitMapMockData {
    static let routes: [TransitRoute3D] = [
        .init(
            code: "M6",
            mode: .metro,
            color: Color(hex: "#1AA35F"),
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
            icon: "tram.fill",
            path: [
                .init(latitude: 50.8138, longitude: 4.3815),
                .init(latitude: 50.8269, longitude: 4.3654),
                .init(latitude: 50.8392, longitude: 4.3482),
                .init(latitude: 50.8559, longitude: 4.3603),
                .init(latitude: 50.8728, longitude: 4.3925),
            ],
            vehicles: [
                .init(label: "T7-1", startOffset: 0.28, speed: 0.012),
                .init(label: "T7-2", startOffset: 0.71, speed: 0.014),
            ]
        ),
        .init(
            code: "B95",
            mode: .bus,
            color: Color(hex: "#C8BCA7"),
            icon: "bus.fill",
            path: [
                .init(latitude: 50.8138, longitude: 4.3815),
                .init(latitude: 50.8239, longitude: 4.3738),
                .init(latitude: 50.8345, longitude: 4.3649),
                .init(latitude: 50.8466, longitude: 4.3572),
                .init(latitude: 50.8552, longitude: 4.3486),
            ],
            vehicles: [
                .init(label: "B95-1", startOffset: 0.19, speed: 0.018),
                .init(label: "B95-2", startOffset: 0.62, speed: 0.016),
            ]
        )
    ]
}
