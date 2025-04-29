//
//  MeldingDetailViewModel.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.
//
import Foundation
import Combine

import Foundation
import Combine

class MeldingDetailViewModel: ObservableObject {
    @Published var signalement: MeldingenModel?
    @Published var errorMessage: String?
    @Published var halteNom: String? // ✅ Changer ici : halte devient juste un "nom" simple
    
    func fetchSignalement(arretId: String, signalementId: String) {
        let cacheFile = "signalement_\(signalementId).json"
        
        // 1. Vérifie la connexion
        if !NetworkMonitor.shared.isConnected {
            print("[DEBUG] 🔌 Hors-ligne - lecture du cache pour signalement \(signalementId)")
            if let cachedData = loadFromCache(filename: cacheFile) {
                self.decodeSignalement(from: cachedData)
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Pas de connexion et pas de cache disponible."
                }
            }
            return
        }
        
        // 2. En ligne, fetch normal
        let urlString = "https://stib-alert-backend.onrender.com/api/signalements/arret/\(arretId)/signalement/\(signalementId)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "URL invalide: \(urlString)"
            }
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Netwerkfout: \(error.localizedDescription)"
                    return
                }

                guard let data = data else {
                    self.errorMessage = "Geen data ontvangen"
                    return
                }
                
                // 3. Sauvegarde le signalement dans cache
                saveToCache(data: data, filename: cacheFile)
                
                self.decodeSignalement(from: data)
            }
        }.resume()
    }
    
    private func decodeSignalement(from data: Data) {
        do {
            let decoder = JSONDecoder()
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
            formatter.locale = Locale(identifier: "en_US_POSIX")
            decoder.dateDecodingStrategy = .formatted(formatter)

            let decoded = try decoder.decode(MeldingenModel.self, from: data)
            self.signalement = decoded
            
            if let raw = String(data: data, encoding: .utf8) {
                print("[DEBUG] ✅ Signalement brut (offline/online):\n\(raw)")
            }

            if let nomDirect = decoded.arret, !nomDirect.isEmpty {
                self.halteNom = nomDirect
                print("[DEBUG] ✅ Nom d'arrêt récupéré : \(nomDirect)")
            } else {
                self.fetchHalte(arretId: decoded.arretId)
            }
        } catch {
            self.errorMessage = "Erreur de décodage: \(error.localizedDescription)"
            print("[DEBUG] ❌ Erreur de décodage signalement: \(error.localizedDescription)")
        }
    }



    func fetchHalte(arretId: String) {
        guard !arretId.isEmpty else {
            print("[DEBUG] ❌ arretId vide, pas de requête pour halte.")
            self.halteNom = nil
            return
        }

        let urlString = "https://stib-alert-backend.onrender.com/api/arrets/\(arretId)"
        guard let url = URL(string: urlString) else {
            print("[DEBUG] ❌ URL incorrecte pour halte: \(urlString)")
            return
        }

        URLSession.shared.dataTask(with: url) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[DEBUG] ❌ Erreur récupération halte: \(error.localizedDescription)")
                    return
                }

                guard let data = data else {
                    print("[DEBUG] ❌ Pas de data pour halte")
                    return
                }

                do {
                    let halteDecoded = try JSONDecoder().decode(HalteModel.self, from: data)
                    self.halteNom = halteDecoded.nom
                    print("[DEBUG] ✅ Halte récupérée : \(halteDecoded.nom)")
                } catch {
                    print("[DEBUG] ❌ Erreur décodage halte: \(error.localizedDescription)")
                }
            }
        }.resume()
    }

    func voteSignalement(arretId: String, signalementId: String, isUp: Bool) {
        let urlString = "https://stib-alert-backend.onrender.com/api/signalements/\(signalementId)/vote"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL: \(urlString)"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")

        let body: [String: String] = ["vote": isUp ? "up" : "down"]

        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Body encoding fout: \(error.localizedDescription)"
            }
            return
        }

        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                if let error = error {
                    self.errorMessage = "Netwerkfout: \(error.localizedDescription)"
                    return
                }
                self.fetchSignalement(arretId: arretId, signalementId: signalementId)
            }
        }.resume()
    }
}
