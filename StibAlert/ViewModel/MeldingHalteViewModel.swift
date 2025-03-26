//
//  MeldingHalteViewModel.swift
//  StibAlert
//
//  Created by studentehb on 21/03/2025.
//
import Foundation
import Combine

class MeldingHalteViewModel: ObservableObject {
    // Les données que votre vue va afficher
    @Published var resume: String = ""
    @Published var signalements: [ArretSignalementItem] = []
    @Published var errorMessage: String?
    
    // Fonction pour récupérer les signalements (et le résumé) d’un arrêt
    func fetchMeldingen(voor arretId: String) {
        // Construire l'URL à partir de l'ID d'arrêt
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/signalements/arret/\(arretId)") else {
            self.errorMessage = "URL invalide pour arretId \(arretId)"
            print("[DEBUG] URL invalide pour arretId \(arretId)")
            return
        }
        
        print("[DEBUG] Requête GET à l'URL : \(url.absoluteString)")
        
        // Lancer la requête
        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                // Vérifier les erreurs réseau
                if let error = error {
                    self.errorMessage = "Erreur réseau : \(error.localizedDescription)"
                    print("[DEBUG] Erreur réseau : \(error.localizedDescription)")
                    return
                }
                
                // Vérifier la réponse
                if let httpResponse = response as? HTTPURLResponse {
                    print("[DEBUG] Status code: \(httpResponse.statusCode)")
                }
                
                // Vérifier la data
                guard let data = data else {
                    self.errorMessage = "Aucune donnée reçue"
                    print("[DEBUG] Aucune donnée reçue")
                    return
                }
                
                // Log du JSON brut
                if let rawString = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Réponse brute:\n\(rawString)")
                }
                
                // Tenter de décoder
                do {
                    let decoded = try JSONDecoder().decode(ArretSignalementsResponse.self, from: data)
                    self.resume = decoded.resume
                    self.signalements = decoded.signalements
                    print("[DEBUG] Décodage réussi : résumé = \(decoded.resume)")
                    print("[DEBUG] Nombre de signalements = \(decoded.signalements.count)")
                } catch {
                    self.errorMessage = "Décodage échoué: \(error.localizedDescription)"
                    print("[DEBUG] Erreur de décodage : \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}
