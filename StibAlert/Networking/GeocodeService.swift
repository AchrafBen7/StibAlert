import CoreLocation
import Foundation

/// Backend-hosted forward geocoding (Google) wrapper, biased to Brussels.
/// Used by STIB·AI (typed chat) and STIB·Micro (voice) to resolve a free-form
/// destination like "Avenue des Désirs" to coordinates before calling the trip
/// planner.
///
/// The destination resolution priority is:
///   1) `NearbyStopService.searchStopByName` — canonical STIB stop
///   2) `GeocodeService.search` — Google (this file) for addresses/POIs
///   3) `MKLocalSearch` — last-resort fallback if Google times out / no key
///
/// Google is preferred over Apple's MKLocalSearch in Belgium because Apple
/// has been observed returning random POI matches ("Kathleen Dandoy",
/// "Rue de la Croix de Fer" on partial words) where Google returns the real
/// address.
struct GeocodeResult: Decodable {
    let lat: Double
    let lng: Double
    let name: String
    let formattedAddress: String
    let types: [String]

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

enum GeocodeService {
    static func search(_ query: String) async -> GeocodeResult? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, AppConfig.isBackendEnabled else { return nil }
        guard let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return nil
        }
        do {
            return try await APIClient.shared.request("/api/geocode?q=\(encoded)")
        } catch {
            // 404 = nothing found (normal), other = transient. Either way we
            // fall back to MKLocalSearch on the caller side.
            return nil
        }
    }
}
