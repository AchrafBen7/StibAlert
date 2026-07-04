import CoreLocation
import Foundation

/// Recherche d'adresse via **Photon (OpenStreetMap)**, proxy backend — gratuit,
/// sans clé, meilleur qu'Apple MKLocalSearch en Belgique (playbook
/// Citymapper/Moovit). Les prédictions sont **déjà géolocalisées** : pas de 2ᵉ
/// appel « details », un tap suffit.
enum AddressSearchService {
    struct Prediction: Decodable {
        let title: String
        let subtitle: String
        let lat: Double
        let lng: Double
    }

    private struct Response: Decodable {
        let predictions: [Prediction]
    }

    /// Prédictions pour la saisie courante, biaisées sur la position de
    /// l'utilisateur si fournie (sinon Bruxelles côté backend).
    static func autocomplete(
        _ query: String,
        coordinate: CLLocationCoordinate2D?
    ) async -> [Prediction] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2,
              AppConfig.isBackendEnabled,
              let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) else {
            return []
        }
        var path = "/api/geocode/autocomplete?q=\(encoded)"
        if let c = coordinate {
            path += "&lat=\(c.latitude)&lng=\(c.longitude)"
        }
        do {
            let resp: Response = try await APIClient.shared.request(path)
            return resp.predictions
        } catch {
            return []
        }
    }
}
