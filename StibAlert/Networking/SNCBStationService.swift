import CoreLocation
import Foundation
import SwiftUI

struct SNCBStation: Decodable, Identifiable, Equatable {
    let id: String
    let uri: String
    let name: String
    let lat: Double
    let lng: Double
    let standardname: String

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var displayName: String {
        standardname.isEmpty ? name : standardname
    }
}

struct SNCBStationDistance: Identifiable {
    let station: SNCBStation
    let distanceMeters: Int

    var id: String { station.id }
}

private struct SNCBStationsPayload: Decodable {
    let stations: [SNCBStation]
}

enum SNCBStationService {
    static let allStations: [SNCBStation] = loadStations()

    static func nearbyStations(
        around coordinate: CLLocationCoordinate2D?,
        radiusMeters: CLLocationDistance = 35_000,
        limit: Int = 8
    ) -> [SNCBStationDistance] {
        let origin = coordinate ?? CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
        let originLocation = CLLocation(latitude: origin.latitude, longitude: origin.longitude)

        return allStations
            .map { station -> (station: SNCBStation, distance: CLLocationDistance) in
                let distance = originLocation.distance(from: CLLocation(latitude: station.lat, longitude: station.lng))
                return (station, distance)
            }
            .filter { $0.distance <= radiusMeters }
            .sorted { $0.distance < $1.distance }
            .prefix(limit)
            .map { SNCBStationDistance(station: $0.station, distanceMeters: Int($0.distance.rounded())) }
    }

    static func mapStations(
        around coordinate: CLLocationCoordinate2D,
        cameraLatitudeDelta: Double,
        limit: Int = 50
    ) -> [SNCBStation] {
        // Keep the map readable: show all Brussels stations only from city-level
        // zooms, otherwise keep the closest railway layer around the viewport.
        let radius = min(max(cameraLatitudeDelta * 111_000 * 0.8, 4_000), 22_000)
        return nearbyStations(around: coordinate, radiusMeters: radius, limit: limit).map(\.station)
    }

    static func nearbyStop(from stationDistance: SNCBStationDistance) -> NearbyStop {
        let station = stationDistance.station
        let line = StopLine(number: "SNCB", color: Color(hex: "#0055A4"))
        // The report flow requires a selectable "line"; SNCB stations expose a
        // single "SNCB" pseudo-line so a report carries ligne == "SNCB" (which
        // the Infos trafic SNCB filter matches). We have no realtime crowding /
        // reliability for trains, so use neutral placeholders.
        let issueLine = NearbyIssueLine(
            number: "SNCB",
            color: Color(hex: "#0055A4"),
            direction: "Train SNCB",
            crowding: .low,
            reliability: 100,
            lineTextColor: .white
        )

        return NearbyStop(
            backendId: station.id,
            stopId: station.id,
            name: station.displayName,
            lines: [line],
            distanceMeters: stationDistance.distanceMeters,
            issueLines: [issueLine],
            coordinate: station.coordinate
        )
    }

    private static func loadStations() -> [SNCBStation] {
        guard let url = Bundle.main.url(forResource: "sncb-brussels-stations", withExtension: "json") else {
            ErrorReporting.captureMessage("SNCB stations bundle resource missing", tag: "sncb.stations")
            return []
        }

        do {
            let data = try Data(contentsOf: url)
            let payload = try JSONDecoder().decode(SNCBStationsPayload.self, from: data)
            return payload.stations.sorted {
                $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
            }
        } catch {
            ErrorReporting.capture(error, tag: "sncb.stations.decode")
            return []
        }
    }
}
