import Foundation
import CoreLocation

struct MapSignalCluster: Identifiable {
    let id: String
    let coordinate: CLLocationCoordinate2D
    let count: Int
    let dominantType: String
    let sampleIds: [String]
}

enum MapSignalClusterer {
    struct Input {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let typeProbleme: String
    }

    static func cluster(points: [Input], latitudeDelta: Double) -> [MapSignalCluster] {
        guard !points.isEmpty else { return [] }
        let cellSize = max(0.00015, latitudeDelta / 40)

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
            let grouped = Dictionary(grouping: members, by: \.typeProbleme)
            let dominant = grouped.max(by: { $0.value.count < $1.value.count })?.key
                ?? members.first?.typeProbleme
                ?? "Autre"

            return MapSignalCluster(
                id: members.count == 1 ? (members.first?.id ?? key) : "cluster-\(key)",
                coordinate: CLLocationCoordinate2D(latitude: latSum / count, longitude: lonSum / count),
                count: members.count,
                dominantType: dominant,
                sampleIds: members.map(\.id)
            )
        }
    }
}
