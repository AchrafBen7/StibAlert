import Foundation

/// Device-local favourite gares. SNCB gares are a static local dataset (not
/// backend arrêts), so — unlike STIB favourite stops — they're persisted here
/// in UserDefaults. Shared singleton so the gare page, the map and the
/// directory all observe the same set.
final class SNCBGareFavorites: ObservableObject {
    static let shared = SNCBGareFavorites()

    @Published private(set) var ids: Set<String>
    private let defaultsKey = "sncb.favorite.gares.v1"

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
        UserDefaults.standard.set(Array(ids), forKey: defaultsKey)
    }

    /// The favourited gares, resolved against the static station list.
    var stations: [SNCBStation] {
        SNCBStationService.allStations.filter { ids.contains($0.id) }
    }
}
