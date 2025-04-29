//
//  LocationManager.swift
//  StibAlert
//
//  Created by studentehb on 28/04/2025.
//
import Foundation
import CoreLocation
 
class LocationManager: NSObject, ObservableObject, CLLocationManagerDelegate {
    private let locationManager = CLLocationManager()
    
    @Published var userLocation: CLLocationCoordinate2D?
    @Published var showLocationError: Bool = false // <-- AJOUTÉ
    
    override init() {
        super.init()
        locationManager.delegate = self
        locationManager.desiredAccuracy = kCLLocationAccuracyBest
        locationManager.requestWhenInUseAuthorization()
    }
    
    func requestLocation() {
        locationManager.requestLocation()
    }
    
    func locationManager(_ manager: CLLocationManager, didChangeAuthorization status: CLAuthorizationStatus) {
        switch status {
        case .authorizedWhenInUse, .authorizedAlways:
            print("[LocationManager] Autorisation OK ✅")
            locationManager.startUpdatingLocation()
            locationManager.requestLocation()
        case .denied, .restricted:
            print("[LocationManager] Autorisation refusée ❌")
            showLocationError = true // <-- Affiche l'erreur
        case .notDetermined:
            print("[LocationManager] Autorisation pas encore donnée...")
        @unknown default:
            break
        }
    }
    
    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        userLocation = locations.first?.coordinate
        print("[LocationManager] Position mise à jour : \(userLocation?.latitude ?? 0), \(userLocation?.longitude ?? 0)")
    }
    
    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        print("[LocationManager] Erreur de localisation: \(error.localizedDescription)")
        showLocationError = true // <-- Affiche l'erreur
    }
}


 
extension CLLocationCoordinate2D: Equatable {
    public static func == (lhs: CLLocationCoordinate2D, rhs: CLLocationCoordinate2D) -> Bool {
        return lhs.latitude == rhs.latitude && lhs.longitude == rhs.longitude
    }
}
