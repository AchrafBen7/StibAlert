import Foundation
import CoreLocation

struct VilloStation: Decodable, Identifiable, Equatable {
    struct Position: Decodable, Equatable {
        let lat: Double
        let lng: Double
    }

    let number: Int
    let name: String
    let address: String
    let position: Position
    let status: String
    let bikeStands: Int
    let availableBikes: Int
    let availableBikeStands: Int
    let banking: Bool
    let lastUpdate: Int64?

    var id: Int { number }
    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: position.lat, longitude: position.lng)
    }

    var displayName: String {
        let parts = name.split(separator: "-", maxSplits: 1).map { $0.trimmingCharacters(in: .whitespaces) }
        return parts.count == 2 ? parts[1] : name
    }

    var statusLabel: String {
        switch status.uppercased() {
        case "OPEN": return "Ouverte"
        case "CLOSED": return "Fermée"
        default: return status.capitalized
        }
    }

    var availabilityLabel: String {
        "\(availableBikes) vélos • \(availableBikeStands) places"
    }

    var isOperational: Bool {
        status.uppercased() == "OPEN"
    }

    var occupancyStateLabel: String {
        if !isOperational { return "Station fermée" }
        if availableBikes == 0 { return "Aucun vélo disponible" }
        if availableBikeStands == 0 { return "Plus de places libres" }
        if availableBikes <= 3 { return "Peu de vélos disponibles" }
        return "Station bien disponible"
    }

    enum CodingKeys: String, CodingKey {
        case number, name, address, position, status, banking
        case bikeStands = "bike_stands"
        case availableBikes = "available_bikes"
        case availableBikeStands = "available_bike_stands"
        case lastUpdate = "last_update"
    }
}

struct VilloNearbySuggestion: Equatable {
    let station: VilloStation
    let distanceMeters: Int
    let contextLabel: String
}

enum VilloStationService {
    private static let bundledFileName = "villo_stations"
    private static let stationsCache: [VilloStation] = loadStations()

    static var allStations: [VilloStation] {
        stationsCache
    }

    static func nearbyStations(
        around coordinate: CLLocationCoordinate2D,
        radiusMeters: Double = 300,
        limit: Int = 3
    ) -> [(station: VilloStation, distanceMeters: Int)] {
        stationsCache
            .map { station in
                let distance = distanceMeters(from: coordinate, to: station.coordinate)
                return (station, Int(distance.rounded()))
            }
            .filter { $0.distanceMeters <= Int(radiusMeters.rounded()) }
            .sorted {
                if $0.distanceMeters == $1.distanceMeters {
                    return $0.station.availableBikes > $1.station.availableBikes
                }
                return $0.distanceMeters < $1.distanceMeters
            }
            .prefix(limit)
            .map { $0 }
    }

    static func bestSuggestion(
        near coordinate: CLLocationCoordinate2D?,
        contextLabel: String,
        preferBikes: Bool
    ) -> VilloNearbySuggestion? {
        guard let coordinate else { return nil }
        let candidates = nearbyStations(around: coordinate, radiusMeters: 450, limit: 8)
            .filter { $0.station.isOperational }
            .filter { preferBikes ? $0.station.availableBikes > 0 : $0.station.availableBikeStands > 0 }

        guard let best = candidates.sorted(by: {
            if preferBikes {
                if $0.station.availableBikes == $1.station.availableBikes {
                    return $0.distanceMeters < $1.distanceMeters
                }
                return $0.station.availableBikes > $1.station.availableBikes
            } else {
                if $0.station.availableBikeStands == $1.station.availableBikeStands {
                    return $0.distanceMeters < $1.distanceMeters
                }
                return $0.station.availableBikeStands > $1.station.availableBikeStands
            }
        }).first else {
            return nil
        }

        return VilloNearbySuggestion(
            station: best.station,
            distanceMeters: best.distanceMeters,
            contextLabel: contextLabel
        )
    }

    static func routeSuggestions(for steps: [TransportRouteStepDTO]?) -> [VilloNearbySuggestion] {
        guard let steps, !steps.isEmpty else { return [] }
        let departureCoordinate = firstMeaningfulCoordinate(in: steps)
        let arrivalCoordinate = lastMeaningfulCoordinate(in: steps)

        var suggestions: [VilloNearbySuggestion] = []
        if let departure = bestSuggestion(near: departureCoordinate, contextLabel: "Au départ", preferBikes: true) {
            suggestions.append(departure)
        }
        if let arrival = bestSuggestion(near: arrivalCoordinate, contextLabel: "À l’arrivée", preferBikes: false),
           !suggestions.contains(where: { $0.station.id == arrival.station.id }) {
            suggestions.append(arrival)
        }
        return suggestions
    }

    private static func loadStations() -> [VilloStation] {
        guard let url = Bundle.main.url(forResource: bundledFileName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return []
        }

        let decoder = JSONDecoder()
        return (try? decoder.decode([VilloStation].self, from: data)) ?? []
    }

    private static func firstMeaningfulCoordinate(in steps: [TransportRouteStepDTO]) -> CLLocationCoordinate2D? {
        for step in steps {
            if let lat = step.startLatitude, let lng = step.startLongitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }
        return nil
    }

    private static func lastMeaningfulCoordinate(in steps: [TransportRouteStepDTO]) -> CLLocationCoordinate2D? {
        for step in steps.reversed() {
            if let lat = step.targetLatitude, let lng = step.targetLongitude {
                return CLLocationCoordinate2D(latitude: lat, longitude: lng)
            }
        }
        return nil
    }

    private static func distanceMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let radius = 6_371_000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2)
        return 2 * radius * atan2(sqrt(h), sqrt(1 - h))
    }
}
