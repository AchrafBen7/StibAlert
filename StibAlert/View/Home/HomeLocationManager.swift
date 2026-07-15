import CoreLocation
import Combine

final class HomeLocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    @Published var userCoordinate: CLLocationCoordinate2D?
    @Published var heading: Double = 0

    // Mock Brussels center when no real location available
    static let mockCoordinate = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    private let manager = CLLocationManager()
    /// Dernier statut connu, pour ne compter (analytics) que la RÉPONSE de
    /// l'utilisateur au prompt — pas chaque lancement d'une app déjà autorisée.
    private var lastAuthStatus: CLAuthorizationStatus = .notDetermined

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        lastAuthStatus = manager.authorizationStatus
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
        let status = manager.authorizationStatus
        // Funnel : on ne compte QUE la transition depuis `.notDetermined`, c.-à-d.
        // le moment où l'utilisateur vient de répondre au prompt. Sinon on
        // compterait « accordé » à chaque ouverture d'une app déjà autorisée.
        if lastAuthStatus == .notDetermined && status != .notDetermined {
            switch status {
            case .authorizedWhenInUse, .authorizedAlways:
                Analytics.track(.locationGranted)
            case .denied, .restricted:
                Analytics.track(.locationDenied)
            default:
                break
            }
        }
        lastAuthStatus = status

        if status == .authorizedWhenInUse || status == .authorizedAlways {
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
