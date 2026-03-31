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
    @Published var arretsAller: [HalteModel] = []
    @Published var arretsRetour: [HalteModel] = []
    @Published var errorMessage: String?
    @Published var isFetchingLignes = false
    @Published var isLoading = false
    
    func fetchArrets(lineId: String, sortAsc: Bool = true) {
        guard AppConfig.isBackendEnabled else {
            errorMessage = nil
            isLoading = false
            if sortAsc {
                arretsAller = []
            } else {
                arretsRetour = []
            }
            arrets = []
            return
        }
        let sort = sortAsc ? "asc" : "desc"
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/arrets/par-ligne-filtres?line=\(lineId)&sort=\(sort)") else {
            errorMessage = "URL invalide"
            return
        }

        isLoading = true
        print("[FETCH] Début du fetch: \(url)")

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false

                if let error = error {
                    self.errorMessage = "[\(sort.uppercased())] Erreur : \(error.localizedDescription)"
                    print(self.errorMessage!)
                    return
                }

                guard let data = data else {
                    self.errorMessage = "[\(sort.uppercased())] Aucune donnée reçue"
                    print(self.errorMessage!)
                    return
                }

                do {
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[DEBUG] 🔍 JSON brut reçu:\n\(raw)")
                    }
                    let decoder = JSONDecoder()
                    decoder.dateDecodingStrategy = .iso8601
                    let decoded = try decoder.decode([HalteModel].self, from: data)

                    print("[FETCH] ✅ \(decoded.count) arrêts reçus pour ligne \(lineId)")

                    if sortAsc {
                        self.arretsAller = decoded
                    } else {
                        self.arretsRetour = decoded
                    }
                } catch {
                    print("[ERREUR DECODAGE] 🔴 Erreur complète : \(error)")
                    self.errorMessage = "[\(sort.uppercased())] Erreur de décodage : \(error.localizedDescription)"
                }

            }
        }.resume()
    }
    
    func fetchAllHaltes() {
        guard AppConfig.isBackendEnabled else {
            arrets = []
            return
        }
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
        guard AppConfig.isBackendEnabled else {
            lignesPourArret = []
            completion()
            return
        }
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

