import CoreLocation
import Foundation

/// A De Lijn / TEC stop returned by the backend's viewport endpoint. These
/// networks have ~30k stops each, far too many to bundle like the SNCB gares —
/// so the app only ever fetches the handful inside the current map viewport,
/// and only when zoomed in.
struct OperatorMapStop: Identifiable, Hashable {
    let id: String
    let name: String
    let lat: Double
    let lng: Double
    let op: TransitOperator

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
}

enum OperatorStopService {
    private struct Response: Decodable {
        let stops: [Stop]
        struct Stop: Decodable {
            let id: String
            let name: String
            let lat: Double
            let lng: Double
        }
    }

    /// Stops for an operator inside a lat/lng bounding box. Backend-cached in
    /// memory; no Mobility API load. Returns [] on any failure.
    static func stops(
        operator op: TransitOperator,
        minLat: Double, maxLat: Double, minLng: Double, maxLng: Double,
        limit: Int = 250
    ) async -> [OperatorMapStop] {
        guard AppConfig.isBackendEnabled else { return [] }
        var components = URLComponents(string: "\(AppConfig.backendBaseURL)/api/operators/\(op.rawValue)/stops")
        components?.queryItems = [
            .init(name: "minLat", value: String(minLat)),
            .init(name: "maxLat", value: String(maxLat)),
            .init(name: "minLng", value: String(minLng)),
            .init(name: "maxLng", value: String(maxLng)),
            .init(name: "limit", value: String(limit)),
        ]
        guard let url = components?.url else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(Response.self, from: data)
            return response.stops.map {
                OperatorMapStop(id: $0.id, name: $0.name, lat: $0.lat, lng: $0.lng, op: op)
            }
        } catch {
            return []
        }
    }
}
