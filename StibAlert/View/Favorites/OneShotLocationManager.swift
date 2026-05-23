import CoreLocation
import Foundation

/// Lightweight one-shot location helper used by favorite pickers.
///
/// It intentionally returns Brussels center when permission is missing instead
/// of blocking the sheet. Favorites remain usable during onboarding/TestFlight
/// even if the user has not granted location yet.
final class OneShotLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private var continuation: CheckedContinuation<CLLocationCoordinate2D, Never>?

    static let fallback = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyHundredMeters
    }

    func getCurrentLocation() async -> CLLocationCoordinate2D {
        let status = manager.authorizationStatus
        guard status == .authorizedWhenInUse || status == .authorizedAlways else {
            return Self.fallback
        }

        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            manager.requestLocation()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        continuation?.resume(returning: locations.last?.coordinate ?? Self.fallback)
        continuation = nil
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        continuation?.resume(returning: Self.fallback)
        continuation = nil
    }
}
