import CoreLocation
import Foundation
import SwiftUI

struct SNCBStation: Decodable, Identifiable, Equatable, Hashable {
    let id: String
    let uri: String
    let name: String
    let lat: Double
    let lng: Double
    let standardname: String
    /// Belgian province (precomputed offline from coordinates) — drives the
    /// Horaires drill-down. Optional for forward-compatibility.
    let province: String?

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    var displayName: String {
        standardname.isEmpty ? name : standardname
    }

    var displayProvince: String { province ?? "Autre" }
}

struct SNCBStationDistance: Identifiable {
    let station: SNCBStation
    let distanceMeters: Int

    var id: String { station.id }
}

private struct SNCBStationsPayload: Decodable {
    let stations: [SNCBStation]
}

struct SNCBDeparture: Decodable, Identifiable {
    let minutes: Int
    let time: String
    let destination: String
    let line: String
    var id: String { "\(minutes)-\(destination)-\(line)" }
}

private struct SNCBDeparturesResponse: Decodable {
    let stationId: String
    let dayType: String
    let items: [SNCBDeparture]
}

/// The three GTFS day-types the static timetable is precomputed for.
enum SNCBDayType: String, CaseIterable, Identifiable {
    case weekday = "wk"
    case saturday = "sa"
    case sunday = "su"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .weekday: return "Semaine"
        case .saturday: return "Samedi"
        case .sunday: return "Dimanche"
        }
    }
}

/// Full theoretical timetable for a gare (every departure of the day for the
/// three day-types), as returned by `GET /api/sncb/schedule`.
struct SNCBSchedule: Decodable {
    let stationId: String
    let today: String
    let days: Days

    struct Days: Decodable {
        let wk: [SNCBDeparture]
        let sa: [SNCBDeparture]
        let su: [SNCBDeparture]
    }

    func departures(for day: SNCBDayType) -> [SNCBDeparture] {
        switch day {
        case .weekday: return days.wk
        case .saturday: return days.sa
        case .sunday: return days.su
        }
    }

    /// Day-type to preselect (the gare's "today" per Brussels time).
    var todayType: SNCBDayType { SNCBDayType(rawValue: today) ?? .weekday }
}

/// A live (iRail) departure for a gare: the scheduled slot plus its real-time
/// delay / cancellation, used both to populate the Officiel tab and to annotate
/// the theoretical timetable.
struct SNCBRTDeparture: Decodable, Identifiable {
    let scheduledMinutes: Int
    let time: String
    let destination: String
    let line: String
    let delayMinutes: Int
    let canceled: Bool
    let platform: String?
    var id: String { "\(scheduledMinutes)-\(destination)-\(line)" }
}

/// An official NMBS disturbance (network-wide), from iRail.
struct SNCBDisruption: Decodable, Identifiable {
    let id: String
    let title: String
    let description: String
    let type: String?
    let link: String?
}

struct SNCBRealtime: Decodable {
    let stationId: String
    let fetchedAt: String?
    let departures: [SNCBRTDeparture]
    let disruptions: [SNCBDisruption]
}

enum SNCBStationService {
    static let allStations: [SNCBStation] = loadStations()

    /// Display order for the Horaires province sections (north → south-ish).
    private static let provinceOrder = [
        "Bruxelles", "Brabant flamand", "Brabant wallon", "Anvers",
        "Flandre-Orientale", "Flandre-Occidentale", "Limbourg",
        "Hainaut", "Liège", "Namur", "Luxembourg",
    ]

    /// Gares grouped by province (ordered), each sorted alphabetically so
    /// same-city gares (Bruxelles-Midi/Central/Nord…) cluster together.
    static let stationsByProvince: [(province: String, stations: [SNCBStation])] = {
        let grouped = Dictionary(grouping: allStations) { $0.displayProvince }
        let ordered = grouped.keys.sorted { a, b in
            let ia = provinceOrder.firstIndex(of: a) ?? Int.max
            let ib = provinceOrder.firstIndex(of: b) ?? Int.max
            return ia != ib ? ia < ib : a < b
        }
        return ordered.map { p in
            (province: p,
             stations: grouped[p]!.sorted {
                 $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
             })
        }
    }()

    /// Recherche une gare par nom (catalogue local embarqué, accent-insensible).
    /// Utilisée par la feuille unifiée « Ajouter un arrêt favori » pour trouver
    /// une gare SNCB par son nom au milieu des arrêts STIB/De Lijn/TEC. Si une
    /// position est fournie, on trie par distance, sinon par ordre alphabétique.
    static func searchByName(
        _ query: String,
        around coordinate: CLLocationCoordinate2D? = nil,
        limit: Int = 6
    ) -> [SNCBStationDistance] {
        let needle = query
            .folding(options: .diacriticInsensitive, locale: AppLocale.current)
            .lowercased()
            .trimmingCharacters(in: .whitespaces)
        guard needle.count >= 2 else { return [] }

        let origin = coordinate.map { CLLocation(latitude: $0.latitude, longitude: $0.longitude) }
        return allStations
            .filter { station in
                let name = station.displayName.folding(options: .diacriticInsensitive, locale: AppLocale.current).lowercased()
                let raw = station.name.folding(options: .diacriticInsensitive, locale: AppLocale.current).lowercased()
                return name.contains(needle) || raw.contains(needle)
            }
            .map { station -> SNCBStationDistance in
                let distance = origin.map { Int($0.distance(from: CLLocation(latitude: station.lat, longitude: station.lng)).rounded()) } ?? 0
                return SNCBStationDistance(station: station, distanceMeters: distance)
            }
            .sorted { lhs, rhs in
                origin != nil
                    ? lhs.distanceMeters < rhs.distanceMeters
                    : lhs.station.displayName.localizedCaseInsensitiveCompare(rhs.station.displayName) == .orderedAscending
            }
            .prefix(limit)
            .map { $0 }
    }

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

    /// Next theoretical departures for a gare, from the backend's static GTFS
    /// dataset (no live data, no Mobility API call). Returns [] on any failure.
    static func departures(stationId: String, limit: Int = 8) async -> [SNCBDeparture] {
        guard AppConfig.isBackendEnabled else { return [] }
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/sncb/departures?stationId=\(encoded)&limit=\(limit)") else { return [] }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(SNCBDeparturesResponse.self, from: data).items
        } catch {
            return []
        }
    }

    /// Full theoretical timetable for a gare (all three day-types in one call,
    /// so the schedule page can switch days without re-fetching). Backend-only,
    /// no Mobility API call. Returns nil on any failure.
    static func fullSchedule(stationId: String) async -> SNCBSchedule? {
        guard AppConfig.isBackendEnabled else { return nil }
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/sncb/schedule?stationId=\(encoded)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(SNCBSchedule.self, from: data)
        } catch {
            return nil
        }
    }

    /// Live SNCB data for a gare (iRail, via the backend): real-time departures
    /// with delays/cancellations + official NMBS disturbances. Backend-cached,
    /// fetched on demand. Returns nil on any failure.
    static func realtime(stationId: String) async -> SNCBRealtime? {
        guard AppConfig.isBackendEnabled else { return nil }
        let encoded = stationId.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? stationId
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/sncb/realtime?stationId=\(encoded)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try JSONDecoder().decode(SNCBRealtime.self, from: data)
        } catch {
            return nil
        }
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
