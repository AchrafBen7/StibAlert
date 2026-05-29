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

        // S3 — Bypass clustering désormais à 0.018 au lieu de 0.02.
        // Une zone de transition 0.018-0.025 (en dessous) utilise un
        // cellSize très petit pour faire fondre les clusters progressivement
        // en singletons au lieu de tout faire "exploser" d'un coup quand on
        // passait la barre 0.02 (effet visuel jarring rapporté en audit).
        if latitudeDelta <= 0.018 {
            return points.map { point in
                MapSignalCluster(
                    id: point.id,
                    coordinate: point.coordinate,
                    count: 1,
                    dominantType: point.typeProbleme,
                    dominantOrigin: point.origin,
                    sampleIds: [point.id],
                    span: nil
                )
            }
        }

        // S3 — Transition douce entre 0.018 et 0.025 : cellSize linéaire
        // entre 80m (à 0.018, juste au-dessus de la zone singleton) et
        // ~280m (à 0.025). Les pins ne se mergent qu'à très très petite
        // distance dans cette zone. Au-dessus de 0.025 on garde la formule
        // latDelta/5 qui donne ~3km à city view.
        let cellSize: Double
        if latitudeDelta <= 0.025 {
            let progress = (latitudeDelta - 0.018) / 0.007 // 0..1
            cellSize = 0.0008 + progress * 0.0020 // 80m -> 280m
        } else {
            cellSize = max(0.0005, latitudeDelta / 5)
        }

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
