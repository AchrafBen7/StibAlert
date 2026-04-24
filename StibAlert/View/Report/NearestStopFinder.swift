import Foundation
import CoreLocation

enum NearestStopFinder {
    /// Returns the closest stop within `maxMeters` radius; otherwise nil.
    static func nearest(
        to coordinate: CLLocationCoordinate2D?,
        in stops: [NearbyStop],
        maxMeters: Double = 50
    ) -> NearbyStop? {
        guard let coordinate else { return nil }
        var best: (stop: NearbyStop, distance: Double)?
        for stop in stops {
            guard let stopCoord = stop.coordinate else { continue }
            let distance = haversine(coordinate, stopCoord)
            if distance <= maxMeters, best == nil || distance < best!.distance {
                best = (stop, distance)
            }
        }
        return best?.stop
    }

    /// Returns the closest stop regardless of distance (fallback when nothing within radius).
    static func closest(
        to coordinate: CLLocationCoordinate2D?,
        in stops: [NearbyStop]
    ) -> NearbyStop? {
        guard let coordinate else { return stops.first }
        var best: (stop: NearbyStop, distance: Double)?
        for stop in stops {
            guard let stopCoord = stop.coordinate else { continue }
            let distance = haversine(coordinate, stopCoord)
            if best == nil || distance < best!.distance {
                best = (stop, distance)
            }
        }
        return best?.stop ?? stops.first
    }

    private static func haversine(_ a: CLLocationCoordinate2D, _ b: CLLocationCoordinate2D) -> Double {
        let R = 6_371_000.0
        let dLat = (b.latitude - a.latitude) * .pi / 180
        let dLon = (b.longitude - a.longitude) * .pi / 180
        let lat1 = a.latitude * .pi / 180
        let lat2 = b.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLon / 2) * sin(dLon / 2) * cos(lat1) * cos(lat2)
        return 2 * R * atan2(sqrt(h), sqrt(1 - h))
    }
}
