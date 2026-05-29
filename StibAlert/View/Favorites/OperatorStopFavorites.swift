import CoreLocation
import Foundation

extension Notification.Name {
    /// #3 — Émise quand les favoris multi-opérateurs changent localement,
    /// pour déclencher la synchro serveur (écoutée par AppRoot si connecté).
    static let operatorFavoritesDidChange = Notification.Name("operatorFavoritesDidChange")
}

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
    /// Vrai pendant l'hydratation serveur → on ne reposte pas la notif de
    /// changement (sinon boucle hydrate → sync → hydrate).
    private var isHydrating = false

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

    // MARK: - Server sync (#3)

    /// Payload De Lijn/TEC pour la synchro serveur (exclut SNCB, géré ailleurs).
    func snapshotDTO() -> [OperatorFavoriteDTO] {
        stops.map { OperatorFavoriteDTO(op: $0.op, stopId: $0.stopId, name: $0.name, lat: $0.lat, lng: $0.lng) }
    }

    /// Fusionne les favoris serveur (De Lijn/TEC) avec le cache local — union,
    /// le serveur fait autorité sur la présence. N'émet pas de notif (évite la
    /// boucle de synchro).
    func hydrate(from serverFavorites: [OperatorFavoriteDTO]) {
        let incoming = serverFavorites
            .filter { $0.op == "delijn" || $0.op == "tec" }
            .compactMap { dto -> FavoriteOperatorStop? in
                guard let lat = dto.lat, let lng = dto.lng else { return nil }
                return FavoriteOperatorStop(op: dto.op, stopId: dto.stopId, name: dto.name ?? "Arrêt", lat: lat, lng: lng)
            }
        guard !incoming.isEmpty || !stops.isEmpty else { return }
        var merged: [String: FavoriteOperatorStop] = [:]
        for s in stops { merged[s.id] = s }
        for s in incoming { merged[s.id] = s }
        let newStops = Array(merged.values)
        guard newStops.count != stops.count || Set(newStops.map(\.id)) != Set(stops.map(\.id)) else { return }
        isHydrating = true
        stops = newStops
        if let data = try? JSONEncoder().encode(stops) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        isHydrating = false
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(stops) {
            UserDefaults.standard.set(data, forKey: defaultsKey)
        }
        if !isHydrating {
            NotificationCenter.default.post(name: .operatorFavoritesDidChange, object: nil)
        }
    }
}
