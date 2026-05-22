import Foundation

/// Device-local favourites for individual SNCB departures. There's no backend
/// "favourite train" field, so we persist a compact key set in UserDefaults.
/// A key identifies a recurring departure (gare + day-type + time + line +
/// destination), so a Saturday train and its weekday twin stay distinct.
final class SNCBDepartureFavorites: ObservableObject {
    @Published private(set) var keys: Set<String>
    private let defaultsKey = "sncb.favorite.departures.v1"

    init() {
        let stored = UserDefaults.standard.stringArray(forKey: defaultsKey) ?? []
        keys = Set(stored)
    }

    static func key(stationId: String, day: SNCBDayType, departure: SNCBDeparture) -> String {
        "\(stationId)|\(day.rawValue)|\(departure.time)|\(departure.line)|\(departure.destination)"
    }

    func contains(_ key: String) -> Bool { keys.contains(key) }

    func toggle(_ key: String) {
        if keys.contains(key) {
            keys.remove(key)
        } else {
            keys.insert(key)
        }
        UserDefaults.standard.set(Array(keys), forKey: defaultsKey)
    }
}
