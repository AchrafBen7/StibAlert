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
    
    func fetchMeldingen() {
        let urlString = "https://stib-alert-backend.onrender.com/api/signalements"
        let cacheFile = "meldingen_cache.json"
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL"
            }
            return
        }
        
        // 🔥 1. CHECK si offline
        if !NetworkMonitor.shared.isConnected {
            print("[DEBUG] ❗ Offline détecté : chargement depuis le cache...")
            if let cachedData = loadFromCache(filename: cacheFile) {
                self.decodeMeldingen(from: cachedData)  // <--- ici ajouter self
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Pas de connexion et aucun cache trouvé."
                }
            }
            return
        }
        
        // 🔥 2. Si online => normale requête API
        print("Envoi de la requête à l'URL : \(url)")
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                print("Erreur dans la requête : \(error.localizedDescription)")
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            guard let data = data else {
                print("Aucune donnée reçue depuis l'API.")
                DispatchQueue.main.async {
                    self.errorMessage = "Geen data ontvangen"
                }
                return
            }
            
            // 🔵 Sauvegarde dans le cache
            saveToCache(data: data, filename: cacheFile)
            
            self.decodeMeldingen(from: data) 
        }.resume()
    }
    
    private func decodeMeldingen(from data: Data) {
        do {
            let decodedMeldingen = try MeldingenViewModel.customDecoder.decode([MeldingenReadModel].self, from: data)
            print("[DEBUG] ✅ Décodage réussi : \(decodedMeldingen.count) éléments")
            DispatchQueue.main.async {
                self.meldingen = decodedMeldingen
                // 🕒 Sauvegarde la date de mise à jour
                UserDefaults.standard.set(Date(), forKey: "LastUpdate")
            }
        } catch {
            print("[DEBUG] ❌ Erreur décodage cache/réseau : \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.errorMessage = "Erreur décodage : \(error.localizedDescription)"
            }
        }
    }
    
}


