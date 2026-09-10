import CoreLocation
import Foundation
import SwiftUI

/// Coordonnée d'un point de tracé. Vivait dans `View/Search/SearchServices.swift`
/// (dossier supprimé : l'onglet Recherche n'existait plus) ; c'est le SEUL type de
/// ce dossier réellement partagé, donc il est rapatrié ici, auprès de ses usages.
struct TransitCoordinate: Hashable, Equatable, Codable {
    let latitude: Double
    let longitude: Double

    var coordinate: CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }
}



struct TransitVehicleMock: Identifiable, Equatable {
    let id = UUID()
    let label: String
}

struct TransitRouteMock: Identifiable, Equatable {
    let id = UUID()
    let code: String
    let icon: String
    let color: Color
    let path: [TransitCoordinate]
    let vehicles: [TransitVehicleMock]
}

