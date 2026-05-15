import Foundation
import CoreLocation

enum MapPinOrigin: String {
    case community
    case official
}

struct MapSignalCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let dominantType: String
    let dominantOrigin: MapPinOrigin
    let sampleIds: [String]
    let span: (latitudeDelta: Double, longitudeDelta: Double)?
}

enum MapSignalClusterer {
    struct Input {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let typeProbleme: String
        let origin: MapPinOrigin
    }

    /// Buckets points into a coarse grid. cellSize scales with the camera
    /// latitudeDelta so the user sees: 1 big numeric marker per quartier when
    /// the city is in view; individual pins once they zoom to street level.
    static func cluster(points: [Input], latitudeDelta: Double) -> [MapSignalCluster] {
        guard !points.isEmpty else { return [] }
        // Aggressive grid: latDelta/5 gives ~3km cells at city view, ~150m at
        // street view, so pins stop merging only once the user is in detail.
        let cellSize = max(0.0005, latitudeDelta / 5)

        var buckets: [String: [Input]] = [:]
        for point in points {
            let keyY = Int((point.coordinate.latitude / cellSize).rounded(.down))
            let keyX = Int((point.coordinate.longitude / cellSize).rounded(.down))
            let bucketKey = "\(keyY)|\(keyX)"
            buckets[bucketKey, default: []].append(point)
        }

        return buckets.map { key, members in
            let latSum = members.reduce(0.0) { $0 + $1.coordinate.latitude }
            let lonSum = members.reduce(0.0) { $0 + $1.coordinate.longitude }
            let count = Double(members.count)
            let avg = CLLocationCoordinate2D(latitude: latSum / count, longitude: lonSum / count)

            let groupedType = Dictionary(grouping: members, by: \.typeProbleme)
            let dominantType = groupedType.max(by: { $0.value.count < $1.value.count })?.key
                ?? members.first?.typeProbleme
                ?? "Autre"

            let groupedOrigin = Dictionary(grouping: members, by: \.origin)
            let dominantOrigin = groupedOrigin.max(by: { $0.value.count < $1.value.count })?.key
                ?? .community

            let span: (Double, Double)?
            if members.count > 1 {
                let lats = members.map(\.coordinate.latitude)
                let lons = members.map(\.coordinate.longitude)
                let latRange = (lats.max() ?? avg.latitude) - (lats.min() ?? avg.latitude)
                let lonRange = (lons.max() ?? avg.longitude) - (lons.min() ?? avg.longitude)
                span = (latRange, lonRange)
            } else {
                span = nil
            }

            return MapSignalCluster(
                id: members.count == 1 ? (members.first?.id ?? key) : "grp-\(key)",
                coordinate: avg,
                count: members.count,
                dominantType: dominantType,
                dominantOrigin: dominantOrigin,
                sampleIds: members.map(\.id),
                span: span
            )
        }
    }
}
