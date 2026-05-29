import Foundation

/// Device-local favourite gares. SNCB gares are a static local dataset (not
/// backend arrêts), so — unlike STIB favourite stops — they're persisted here
/// in UserDefaults. Shared singleton so the gare page, the map and the
/// directory all observe the same set.
final class SNCBGareFavorites: ObservableObject {
    static let shared = SNCBGareFavorites()

    @Published private(set) var ids: Set<String>
    private let defaultsKey = "sncb.favorite.gares.v1"
    private var isHydrating = false

    private init() {
        ids = Set(UserDefaults.standard.stringArray(forKey: defaultsKey) ?? [])
    }

    func contains(_ id: String) -> Bool { ids.contains(id) }

    func toggle(_ id: String) {
        if ids.contains(id) {
            ids.remove(id)
        } else {
            ids.insert(id)
        }
        persist()
    }

    /// The favourited gares, resolved against the static station list.
    var stations: [SNCBStation] {
        SNCBStationService.allStations.filter { ids.contains($0.id) }
    }

    // MARK: - Server sync (#3)

    /// Payload SNCB pour la synchro serveur — nom + coords résolus via le
    /// catalogue local des gares.
    func snapshotDTO() -> [OperatorFavoriteDTO] {
        let byId = Dictionary(uniqueKeysWithValues: SNCBStationService.allStations.map { ($0.id, $0) })
        return ids.map { id in
            let station = byId[id]
            return OperatorFavoriteDTO(
                op: "sncb",
                stopId: id,
                name: station?.displayName,
                lat: station?.coordinate.latitude,
                lng: station?.coordinate.longitude
            )
        }
    }

    /// Fusionne les gares favorites serveur avec le cache local (union).
    func hydrate(from serverFavorites: [OperatorFavoriteDTO]) {
        let incoming = Set(serverFavorites.filter { $0.op == "sncb" }.map(\.stopId)).filter { !$0.isEmpty }
        guard !incoming.isEmpty else { return }
        let merged = ids.union(incoming)
        guard merged != ids else { return }
        isHydrating = true
        ids = merged
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
        isHydrating = false
    }

    private func persist() {
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
        if !isHydrating {
            NotificationCenter.default.post(name: .operatorFavoritesDidChange, object: nil)
        }
    }
}
