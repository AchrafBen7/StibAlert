import CoreLocation
import Foundation
import MapKit

/// Shared destination-resolution pipeline used by STIB·AI (typed chat) and
/// STIB·Micro (voice). Both flows take a free-form destination string and
/// need to turn it into an `MKMapItem` before calling the trip planner.
///
/// Resolution priority (3-tier) :
///   1. Local STIB stops catalogue (canonical : DELACROIX, BAILLI, TRÔNE…)
///      — fast, no network, deterministic for transit destinations.
///   2. Backend `/api/geocode` (Google forward geocoding, biased Belgium)
///      — best coverage for addresses / monuments / POIs.
///   3. Apple `MKLocalSearch` as a last-resort fallback if Google is
///      unreachable (quota, timeout, missing key, offline).
///
/// Kept stateless so it can be called from both `HomeView` (planning flow)
/// and any future surface (widget, intent, share extension…).
enum STIBAIDestinationResolver {
    /// Resolve a destination string to an `MKMapItem`. `near` biases the
    /// MKLocalSearch fallback to the user's vicinity so a vague query lands
    /// on the closest match, not a random POI 20 km away.
    static func resolve(_ text: String, near origin: CLLocationCoordinate2D) async -> MKMapItem? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        // 1) Catalogue STIB local
        if let stop = await NearbyStopService.searchStopByName(trimmed) {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: stop.coordinate))
            item.name = stop.name
            return item
        }

        // 2) Google forward geocoding (backend)
        if let g = await GeocodeService.search(trimmed) {
            let item = MKMapItem(placemark: MKPlacemark(coordinate: g.coordinate))
            item.name = g.name
            return item
        }

        // 3) Fallback MKLocalSearch — Apple's geocoder is the weakest link
        // in Belgium (fuzzy substring matches on names) but it's the safety
        // net if the previous tiers fail.
        let query = trimmed.localizedCaseInsensitiveContains("bruxelles")
            ? trimmed
            : "\(trimmed), Bruxelles"
        let req = MKLocalSearch.Request()
        req.naturalLanguageQuery = query
        req.resultTypes = [.address, .pointOfInterest]
        req.region = MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )

        guard let response = try? await MKLocalSearch(request: req).start() else {
            return nil
        }

        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        return response.mapItems
            .filter { $0.placemark.location != nil }
            .min { lhs, rhs in
                let l = lhs.placemark.location.map { originLocation.distance(from: $0) } ?? .greatestFiniteMagnitude
                let r = rhs.placemark.location.map { originLocation.distance(from: $0) } ?? .greatestFiniteMagnitude
                return l < r
            }
    }
}
