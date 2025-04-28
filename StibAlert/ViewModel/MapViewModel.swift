//
//  MapViewModel.swift
//  StibAlert
//
//  Created by studentehb on 28/04/2025.
//
 
import Foundation
import MapKit
class MapViewModel: NSObject, ObservableObject, MKLocalSearchCompleterDelegate {
    @Published var searchResults: [MKLocalSearchCompletion] = []
    @Published var route: MKRoute?
    
    private var completer: MKLocalSearchCompleter
    
    override init() {
        self.completer = MKLocalSearchCompleter()
        super.init()
        self.completer.delegate = self
        self.completer.resultTypes = .address
        print("[MapViewModel] Initialisé")
    }
    
    func updateSearch(queryFragment: String) {
        print("[MapViewModel] updateSearch: \(queryFragment)")
        completer.queryFragment = queryFragment
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didUpdateResults results: [MKLocalSearchCompletion]) {
        print("[MapViewModel] didUpdateResults, nombre de résultats: \(results.count)")
        DispatchQueue.main.async {
            self.searchResults = results
        }
    }
    
    func completer(_ completer: MKLocalSearchCompleter, didFailWithError error: Error) {
        print("[MapViewModel] Erreur lors du compléteur: \(error.localizedDescription)")
    }
    
    func searchLocation(address: String, completion: @escaping (CLLocationCoordinate2D?) -> Void) {
        print("[MapViewModel] Recherche de l'adresse: \(address)")
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = address
        
        let search = MKLocalSearch(request: request)
        search.start { response, error in
            if let error = error {
                print("[MapViewModel] Erreur de recherche: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let coordinate = response?.mapItems.first?.placemark.coordinate else {
                print("[MapViewModel] Aucune coordonnée trouvée")
                completion(nil)
                return
            }
            print("[MapViewModel] Coordonnée trouvée: \(coordinate.latitude), \(coordinate.longitude)")
            completion(coordinate)
        }
    }
    
    func getRoute(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D, completion: @escaping (MKRoute?) -> Void) {
        print("[MapViewModel] Calcul de l'itinéraire de \(from) à \(to)")
        let request = MKDirections.Request()
        request.source = MKMapItem(placemark: MKPlacemark(coordinate: from))
        request.destination = MKMapItem(placemark: MKPlacemark(coordinate: to))
        request.transportType = .any
        
        let directions = MKDirections(request: request)
        directions.calculate { response, error in
            if let error = error {
                print("[MapViewModel] Erreur de route: \(error.localizedDescription)")
                completion(nil)
                return
            }
            guard let route = response?.routes.first else {
                print("[MapViewModel] Aucune route trouvée")
                completion(nil)
                return
            }
            print("[MapViewModel] Route trouvée avec \(route.steps.count) étapes")
            completion(route)
        }
    }
}
