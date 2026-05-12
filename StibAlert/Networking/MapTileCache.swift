import Foundation
import MapKit
import UIKit

/// Pre-renders a static map snapshot of the user's current area and stores it
/// to disk. When the user opens the app offline (e.g. in the métro), HomeView
/// can render this snapshot as a fallback while MapKit struggles to fetch tiles.
///
/// This is NOT a real tile cache (MapKit doesn't expose its tile cache API).
/// It's a one-pic snapshot that covers the user's "home zone". Good enough as
/// a degraded mode — pins still render on top via SwiftUI overlay.
enum MapTileCache {
    private static let snapshotFileName = "home-zone-snapshot.png"
    private static let metadataKey = "mapTileCache.metadata.v1"
    private static let snapshotMaxAgeSeconds: TimeInterval = 7 * 24 * 60 * 60 // 7 days

    private struct Metadata: Codable {
        let centerLat: Double
        let centerLng: Double
        let span: Double
        let createdAt: Date
    }

    private static var snapshotURL: URL {
        let dir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return dir.appendingPathComponent(snapshotFileName)
    }

    /// Re-renders the snapshot if it's older than 24h or the user has moved >500m
    /// from the cached center. Call from HomeView's `.task` modifier.
    static func refreshSnapshotIfNeeded(
        center: CLLocationCoordinate2D,
        spanDegrees: Double = 0.04,
        size: CGSize = CGSize(width: 800, height: 800)
    ) async {
        if !shouldRefresh(center: center, spanDegrees: spanDegrees) {
            return
        }
        await render(center: center, spanDegrees: spanDegrees, size: size)
    }

    static func loadSnapshot() -> UIImage? {
        guard FileManager.default.fileExists(atPath: snapshotURL.path) else { return nil }
        return UIImage(contentsOfFile: snapshotURL.path)
    }

    static func snapshotMetadata() -> (center: CLLocationCoordinate2D, span: Double, createdAt: Date)? {
        guard let data = UserDefaults.standard.data(forKey: metadataKey),
              let meta = try? JSONDecoder().decode(Metadata.self, from: data) else {
            return nil
        }
        return (
            CLLocationCoordinate2D(latitude: meta.centerLat, longitude: meta.centerLng),
            meta.span,
            meta.createdAt
        )
    }

    static func clear() {
        try? FileManager.default.removeItem(at: snapshotURL)
        UserDefaults.standard.removeObject(forKey: metadataKey)
    }

    // MARK: - Private

    private static func shouldRefresh(center: CLLocationCoordinate2D, spanDegrees: Double) -> Bool {
        guard let meta = snapshotMetadata() else { return true }

        if Date().timeIntervalSince(meta.createdAt) > snapshotMaxAgeSeconds {
            return true
        }
        let prev = CLLocation(latitude: meta.center.latitude, longitude: meta.center.longitude)
        let curr = CLLocation(latitude: center.latitude, longitude: center.longitude)
        let movedMeters = prev.distance(from: curr)
        if movedMeters > 500 {
            return true
        }
        // Span changed significantly (zoom out → cached snapshot looks tiny)
        if abs(meta.span - spanDegrees) > 0.02 {
            return true
        }
        return false
    }

    private static func render(
        center: CLLocationCoordinate2D,
        spanDegrees: Double,
        size: CGSize
    ) async {
        let options = MKMapSnapshotter.Options()
        options.region = MKCoordinateRegion(
            center: center,
            span: MKCoordinateSpan(latitudeDelta: spanDegrees, longitudeDelta: spanDegrees)
        )
        options.size = size
        options.scale = await UIScreen.main.scale
        options.showsBuildings = true
        options.mapType = .standard

        let snapshotter = MKMapSnapshotter(options: options)

        do {
            let snapshot = try await snapshotter.start()
            guard let pngData = snapshot.image.pngData() else { return }
            try pngData.write(to: snapshotURL, options: .atomic)

            let meta = Metadata(
                centerLat: center.latitude,
                centerLng: center.longitude,
                span: spanDegrees,
                createdAt: Date()
            )
            if let encoded = try? JSONEncoder().encode(meta) {
                UserDefaults.standard.set(encoded, forKey: metadataKey)
            }
        } catch {
            // Silent — degraded fallback is just not having the snapshot.
        }
    }
}
