import Foundation
import Combine

class LijnenViewModel: ObservableObject {
    @Published var lijnen: [LijnModel] = []
    @Published var errorMessage: String?
    
    func fetchLijnen() {
        let urlString = "https://stib-alert-backend.onrender.com/api/lignes"
        let cacheFile = "lijnen_cache.json"
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "URL invalide"
            }
            return
        }
        
        if !NetworkMonitor.shared.isConnected {
            print("[LOG] 🔌 Mode hors-ligne – lecture du cache")
            if let cached = CacheManager.shared.load(filename: cacheFile) {
                self.decodeLijnen(from: cached)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Aucune donnée disponible hors-ligne."
                }
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Erreur : \(error.localizedDescription)"
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "Pas de données reçues"
                }
                return
            }

            CacheManager.shared.save(data: data, filename: cacheFile)
            UserDefaults.standard.set(Date(), forKey: "LastUpdateLijnen") // ⬅️ ici
            self.decodeLijnen(from: data)
        }.resume()
    }
    
    private func decodeLijnen(from data: Data) {
        do {
            let lignesDecodees = try JSONDecoder().decode([LijnModel].self, from: data)
            print("[LOG] ✅ Décodage réussi: \(lignesDecodees.count) lignes.")
            DispatchQueue.main.async {
                self.lijnen = lignesDecodees
            }
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Erreur de décodage: \(error.localizedDescription)"
            }
            print("[LOG] ❌ Erreur de décodage: \(error.localizedDescription)")
        }
    }

}
