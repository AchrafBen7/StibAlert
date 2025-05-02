//
//  AlleHaltesViewModel.swift
//  StibAlert
//
//  Created by studentehb on 19/03/2025.
//

import Foundation
import Combine

class AlleHaltesViewModel: ObservableObject {
    @Published var lignesPourArret: [LijnModel] = []
    @Published var arrets: [HalteModel] = []
    @Published var errorMessage: String?
    @Published var isFetchingLignes = false
    
    
    func fetchArrets(lineId: String) {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/arrets/par-ligne-filtres?line=\(lineId)&sort=asc") else {
            errorMessage = "URL invalide"
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = error.localizedDescription
                } else if let data = data {
                    // Log du JSON brut
                    if let raw = String(data: data, encoding: .utf8) {
                        print("DEBUG JSON brut :", raw)
                    }
                    
                    do {
                        self.arrets = try JSONDecoder().decode([HalteModel].self, from: data)
                    } catch {
                        self.errorMessage = "Erreur de décodage : \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
        
    }
    func fetchAllHaltes() {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/arrets") else { return }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let data = data {
                do {
                    let decoded = try JSONDecoder().decode([HalteModel].self, from: data)
                    DispatchQueue.main.async {
                        self.arrets = decoded
                    }
                } catch {
                    print("[ERREUR] Décodage arrêts :", error.localizedDescription)
                }
            }
        }.resume()
    }
    func fetchLijnenPourArret(arretId: String, completion: @escaping () -> Void) {
        print("[DEBUG] 📡 Envoi de requête pour les lignes de l'arrêt ID: \(arretId)")
        
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/arrets/\(arretId)/lignes") else {
            print("[ERREUR] ❌ URL invalide")
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, _, error in
            if let error = error {
                print("[ERREUR] ❌ Requête échouée: \(error.localizedDescription)")
                return
            }
            
            guard let data = data else {
                print("[ERREUR] ❌ Pas de données")
                return
            }
            
            if let raw = String(data: data, encoding: .utf8) {
                print("[DEBUG] 🔍 JSON brut:\n\(raw)")
            }
            
            do {
                let lignes = try JSONDecoder().decode([LijnModel].self, from: data)
                DispatchQueue.main.async {
                    self.lignesPourArret = lignes
                    print("[DEBUG] ✅ Lignes chargées: \(lignes.map { $0.lineid })")
                    completion()
                }
            } catch {
                print("[ERREUR] ❌ Décodage JSON: \(error.localizedDescription)")
            }
        }.resume()
    }
    
    
}


