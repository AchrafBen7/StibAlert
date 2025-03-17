import Foundation
import Combine

class LijnenViewModel: ObservableObject {
    @Published var lijnen: [LijnModel] = []
    @Published var errorMessage: String?
    
    func fetchLijnen() {
        // 1. Définir l’URL
        let urlString = "https://stib-alert-backend.onrender.com/api/lignes"
        print("[LOG] URL utilisée: \(urlString)")
        
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "[LOG] URL invalide: \(urlString)"
            }
            return
        }
        
        // 2. Créer la requête
        let request = URLRequest(url: url)
        print("[LOG] Envoi de la requête à \(url)")
        
        // 3. Exécuter la requête
        URLSession.shared.dataTask(with: request) { data, response, error in
            // 3a. Vérifier les erreurs réseau
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "[LOG] Erreur réseau: \(error.localizedDescription)"
                }
                print("[LOG] Erreur réseau: \(error.localizedDescription)")
                return
            }
            
            // 3b. Vérifier la réponse HTTP
            if let httpResponse = response as? HTTPURLResponse {
                print("[LOG] Status code: \(httpResponse.statusCode)")
                // Vous pouvez également loguer les headers:
                // print("[LOG] Headers: \(httpResponse.allHeaderFields)")
            } else {
                print("[LOG] La réponse n'est pas de type HTTPURLResponse.")
            }
            
            // 3c. Vérifier la présence de données
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "[LOG] Aucune donnée reçue (data est nil)."
                }
                print("[LOG] Aucune donnée reçue (data est nil).")
                return
            }
            
            // 4. Afficher la réponse brute pour debug
            if let rawString = String(data: data, encoding: .utf8) {
                print("[LOG] Réponse brute: \(rawString)")
            } else {
                print("[LOG] Impossible de convertir les données en String (encodage UTF-8).")
            }
            
            // 5. Tenter de décoder les données
            do {
                let lignesDecodees = try JSONDecoder().decode([LijnModel].self, from: data)
                print("[LOG] Décodage réussi: \(lignesDecodees.count) éléments.")
                DispatchQueue.main.async {
                    self.lijnen = lignesDecodees
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "[LOG] Erreur de décodage: \(error.localizedDescription)"
                }
                print("[LOG] Erreur de décodage: \(error.localizedDescription)")
            }
        }.resume()
    }
}
