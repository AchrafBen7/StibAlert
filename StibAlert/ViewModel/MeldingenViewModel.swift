import Foundation
import Combine

class MeldingenViewModel: ObservableObject {
    @Published var meldingen: [MeldingenReadModel] = []
    @Published var errorMessage: String?
    
    // Formatter ISO8601 pour les dates avec fraction de secondes
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // JSONDecoder personnalisé pour décoder les dates en format ISO8601 avec fraction de secondes
    private static var customDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            guard let date = MeldingenViewModel.isoFormatter.date(from: dateStr) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Ongeldig datumformaat: \(dateStr)"
                )
            }
            return date
        }
        return decoder
    }()
    
    // Récupération des meldingen depuis l'endpoint
    func fetchMeldingen() {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/signalements") else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL"
            }
            return
        }
        
        print("Envoi de la requête à l'URL : \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Erreur dans la requête : \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            if let httpResponse = response as? HTTPURLResponse {
                print("Réponse HTTP reçue avec le status code : \(httpResponse.statusCode)")
            } else {
                print("Réponse non HTTP reçue.")
            }
            
            guard let data = data else {
                print("Aucune donnée reçue depuis l'API.")
                DispatchQueue.main.async {
                    self.errorMessage = "Geen data ontvangen"
                }
                return
            }
            
            // Affichage du JSON brut reçu (pour diagnostic)
            if let jsonStr = String(data: data, encoding: .utf8) {
                print("Données reçues (JSON brut) : \(jsonStr)")
            } else {
                print("Impossible de convertir les données en String.")
            }
            
            do {
                let decodedMeldingen = try MeldingenViewModel.customDecoder.decode([MeldingenReadModel].self, from: data)
                print("Décodage réussi : \(decodedMeldingen.count) éléments reçus")
                DispatchQueue.main.async {
                    self.meldingen = decodedMeldingen
                }
            } catch {
                print("Erreur lors du décodage : \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }
        }.resume()
    }
}
