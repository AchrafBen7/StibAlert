import CoreLocation
import Foundation

/// A favourited De Lijn / TEC stop. These networks aren't bundled (served by
/// viewport), so — unlike STIB favourites (backend) — we persist the full stop
/// info locally.
struct FavoriteOperatorStop: Codable, Identifiable, Hashable {
    let op: String
    let stopId: String
    let name: String
    let lat: Double
    let lng: Double

    var id: String { "\(op):\(stopId)" }
    var operatorType: TransitOperator { TransitOperator(rawValue: op) ?? .delijn }
    var coordinate: CLLocationCoordinate2D { CLLocationCoordinate2D(latitude: lat, longitude: lng) }
}

/// Device-local favourites for De Lijn / TEC stops. Shared singleton so the
/// Favoris tab and the add sheet observe the same set.
final class OperatorStopFavorites: ObservableObject {
    static let shared = OperatorStopFavorites()

    @Published private(set) var stops: [FavoriteOperatorStop]
    private let defaultsKey = "operator.favorite.stops.v1"

    private init() {
        if let data = UserDefaults.standard.data(forKey: defaultsKey),
           let decoded = try? JSONDecoder().decode([FavoriteOperatorStop].self, from: data) {
            stops = decoded
        } else {
            stops = []
        }
    }

    func contains(_ stopId: String) -> Bool {
        stops.contains { $0.stopId == stopId }
    }

    func toggle(_ stop: FavoriteOperatorStop) {
        if let index = stops.firstIndex(where: { $0.id == stop.id }) {
            stops.remove(at: index)
        } else {
            stops.append(stop)
        }
        persist()
    }

    func remove(_ stop: FavoriteOperatorStop) {
        stops.removeAll { $0.id == stop.id }
        persist()
    }

    func stops(for op: TransitOperator) -> [FavoriteOperatorStop] {
        stops
            .filter { $0.op == op.rawValue }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stops) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
    }
}
