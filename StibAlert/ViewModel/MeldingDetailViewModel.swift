//
//  MeldingDetailViewModel.swift
//  StibAlert
//
//  Created by studentehb on 24/03/2025.
//

import Foundation
import Combine

class MeldingDetailViewModel: ObservableObject {
    @Published var signalement: MeldingenModel?
    @Published var errorMessage: String?
    
    // Récupère un signalement spécifique pour une halte donnée via GET
    func fetchSignalement(arretId: String, signalementId: String) {
        let urlString = "https://stib-alert-backend.onrender.com/api/signalements/arret/\(arretId)/signalement/\(signalementId)"
        guard let url = URL(string: urlString) else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL: \(urlString)"
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
                
                do {
                    let decoder = JSONDecoder()
                    let formatter = DateFormatter()
                    formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSSZ"
                    formatter.locale = Locale(identifier: "en_US_POSIX")
                    decoder.dateDecodingStrategy = .formatted(formatter)

                    let decoded = try decoder.decode(MeldingenModel.self, from: data)
                    print("[DEBUG] Décodage signalement réussi: \(decoded)")

                    self.signalement = decoded
                    if let raw = String(data: data, encoding: .utf8) {
                        print("[DEBUG] Réponse JSON brute :\n\(raw)")
                    }


                } catch {
                    self.errorMessage = "Decodering mislukt: \(error.localizedDescription)"
                }
            }
        }.resume()
    }
    
    // Envoie un vote pour un signalement via POST
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
                // Recharger le signalement pour mettre à jour les votes
                self.fetchSignalement(arretId: arretId, signalementId: signalementId)
            }
        }.resume()
    }

}
