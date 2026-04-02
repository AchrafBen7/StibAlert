import CoreLocation
import Combine

final class HomeLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var heading: Double = 0

    // Mock Brussels center when no real location available
    static let mockCoordinate = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        // Permission requested lazily via start(), not here
    }

    func start() {
        let status = manager.authorizationStatus
        if status == .notDetermined {
            manager.requestWhenInUseAuthorization()
        }
        if status == .authorizedWhenInUse || status == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse ||
           manager.authorizationStatus == .authorizedAlways {
            manager.startUpdatingLocation()
            manager.startUpdatingHeading()
        }
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userCoordinate = locations.last?.coordinate
    }

    func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
        heading = newHeading.magneticHeading
    }

    var displayCoordinate: CLLocationCoordinate2D {
        userCoordinate ?? Self.mockCoordinate
    }
}
