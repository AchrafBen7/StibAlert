import Foundation
import SwiftUI
import CoreLocation
import MapKit
import GoogleMaps3D

@MainActor
final class SearchLocationManager: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    static let currentLocationID = "current-location"

    @Published var currentPlace: SearchPlace?
    @Published var isLocating = false
    @Published var isDenied = false

    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
        manager.distanceFilter = 50
        requestLocationAccess()
    }

    func requestLocationAccess() {
        guard CLLocationManager.locationServicesEnabled() else { return }

        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .authorizedAlways, .authorizedWhenInUse:
            requestCurrentLocation()
        case .denied, .restricted:
            isDenied = true
        @unknown default:
            break
        }
    }

    func requestCurrentLocation() {
        guard CLLocationManager.locationServicesEnabled() else { return }
        isLocating = true
        manager.requestLocation()
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse:
            isDenied = false
            requestCurrentLocation()
        case .denied, .restricted:
            isDenied = true
            isLocating = false
        case .notDetermined:
            break
        @unknown default:
            break
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else {
            isLocating = false
            return
        }

        Task {
            await updateCurrentPlace(from: location)
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: any Error) {
        isLocating = false
    }

    private func updateCurrentPlace(from location: CLLocation) async {
        defer { isLocating = false }

        let coordinate = LatLngAltitude(
            latitude: location.coordinate.latitude,
            longitude: location.coordinate.longitude
        )

        let placemark = try? await geocoder.reverseGeocodeLocation(location).first
        let subtitle = [
            placemark?.name,
            placemark?.locality
        ]
        .compactMap { $0 }
        .joined(separator: " • ")

        currentPlace = SearchPlace(
            id: Self.currentLocationID,
            name: "My location",
            subtitle: subtitle.isEmpty ? "Current position in Brussels" : subtitle,
            coordinate: coordinate
        )
    }
}

enum SearchRouteCalculator {
    static func calculate(from origin: SearchPlace, to destination: SearchPlace) async throws -> SearchJourney {
        do {
            return try await calculate(from: origin, to: destination, transportType: .transit)
        } catch {
            return try await calculate(from: origin, to: destination, transportType: .walking)
        }
    }

    private static func calculate(
        from origin: SearchPlace,
        to destination: SearchPlace,
        transportType: MKDirectionsTransportType
    ) async throws -> SearchJourney {
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: origin.coordinate.coordinate))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: destination.coordinate.coordinate))
        request.transportType = transportType

        let directions = MKDirections(request: request)
        let response = try await directions.calculate()
        guard let route = response.routes.first else {
            throw NSError(domain: "SearchRouteCalculator", code: 0)
        }

        let alternatives = response.routes.dropFirst().prefix(2).map {
            SearchRouteAlternative(
                title: $0.name.isEmpty ? "Alternative route" : $0.name,
                eta: max(1, Int(($0.expectedTravelTime / 60).rounded())),
                lineSummary: $0.displaySummary
            )
        }

        let nearbyVehicles = SearchTransitCorridorAnalyzer.nearbyVehicles(for: route.polyline.latLngAltitudes)

        return SearchJourney(
            origin: origin,
            destination: destination,
            path: route.polyline.latLngAltitudes,
            eta: max(1, Int((route.expectedTravelTime / 60).rounded())),
            lineSummary: route.displaySummary,
            isReal: true,
            alternatives: Array(alternatives),
            nearbyVehicles: nearbyVehicles
        )
    }
}

@MainActor
final class SearchAutocompleteManager: NSObject, ObservableObject, @preconcurrency MKLocalSearchCompleterDelegate {
    @Published var suggestions: [SearchPlaceSuggestion] = []

    private let completer = MKLocalSearchCompleter()

    override init() {
        super.init()
        completer.delegate = self
        completer.resultTypes = [.address, .pointOfInterest]
        completer.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.84673, longitude: 4.35247),
            span: MKCoordinateSpan(latitudeDelta: 0.22, longitudeDelta: 0.22)
        )
    }

    func updateQuery(_ query: String) {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            suggestions = []
            completer.queryFragment = ""
            return
        }

        completer.queryFragment = trimmed
    }

    func resolve(_ suggestion: SearchPlaceSuggestion) async throws -> SearchPlace {
        let request = MKLocalSearch.Request(completion: suggestion.completion)
        let response = try await MKLocalSearch(request: request).start()
        guard let item = response.mapItems.first else {
            throw NSError(domain: "SearchAutocompleteManager", code: 0)
        }

        let coordinate = item.placemark.coordinate
        let subtitle = [
            item.placemark.name,
            item.placemark.locality
        ]
        .compactMap { $0 }
        .joined(separator: " • ")

        return SearchPlace(
            id: "search-\(coordinate.latitude)-\(coordinate.longitude)-\(suggestion.title)",
            name: suggestion.title,
            subtitle: subtitle.isEmpty ? suggestion.subtitle : subtitle,
            coordinate: LatLngAltitude(latitude: coordinate.latitude, longitude: coordinate.longitude)
        )
    }

    func completerDidUpdateResults(_ completer: MKLocalSearchCompleter) {
        suggestions = completer.results.prefix(5).map {
            SearchPlaceSuggestion(
                title: $0.title,
                subtitle: $0.subtitle,
                completion: $0
            )
        }
    }

    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: any Error) {
        suggestions = []
    }
}

enum SearchTransitCorridorAnalyzer {
    static func nearbyVehicles(for path: [LatLngAltitude]) -> [SearchNearbyTransit] {
        guard !path.isEmpty else { return [] }

        return TransitMapMockData.routes.flatMap { route in
            let nearest = minimumDistance(between: path, and: route.path)
            guard nearest < 650 else { return [SearchNearbyTransit]() }

            return route.vehicles.map {
                SearchNearbyTransit(
                    label: $0.label,
                    routeCode: route.code,
                    icon: route.icon,
                    tint: route.color
                )
            }
        }
    }

    private static func minimumDistance(between lhs: [LatLngAltitude], and rhs: [LatLngAltitude]) -> Double {
        lhs.flatMap { a in
            rhs.map { b in
                distance(from: a, to: b)
            }
        }
        .min() ?? .greatestFiniteMagnitude
    }

    private static func distance(from start: LatLngAltitude, to end: LatLngAltitude) -> Double {
        let latScale = 111_000.0
        let lonScale = 111_000.0 * cos(((start.latitude + end.latitude) / 2.0) * .pi / 180.0)
        let dx = (end.longitude - start.longitude) * lonScale
        let dy = (end.latitude - start.latitude) * latScale
        return sqrt(dx * dx + dy * dy)
    }
}

private extension LatLngAltitude {
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}

private extension MKPolyline {
    var latLngAltitudes: [LatLngAltitude] {
        let coords = coordinates
        guard !coords.isEmpty else { return [] }
        return coords.map {
            LatLngAltitude(latitude: $0.latitude, longitude: $0.longitude)
        }
    }

    var coordinates: [CLLocationCoordinate2D] {
        var coords = Array(
            repeating: CLLocationCoordinate2D(latitude: 0, longitude: 0),
            count: pointCount
        )
        getCoordinates(&coords, range: NSRange(location: 0, length: pointCount))
        return coords
    }
}

private extension MKRoute {
    var displaySummary: String {
        let stepSummary = steps
            .map(\.instructions)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .prefix(2)
            .joined(separator: " • ")

        if !name.isEmpty {
            return name
        }

        if !stepSummary.isEmpty {
            return stepSummary
        }

        return "Real route preview"
    }
}

struct SearchPlaceSuggestion: Identifiable {
    let id = UUID()
    let title: String
    let subtitle: String
    let completion: MKLocalSearchCompletion
}

struct SearchRouteAlternative: Identifiable {
    let id = UUID()
    let title: String
    let eta: Int
    let lineSummary: String
}

struct SearchNearbyTransit: Identifiable {
    let id = UUID()
    let label: String
    let routeCode: String
    let icon: String
    let tint: Color
}
