//
//  MeldingenViewModel.swift
//  StibAlert
//
//  Created by studentehb on 12/03/2025.
//

import Foundation
import Combine

class MeldingenViewModel: ObservableObject {
    @Published var meldingen: [MeldingenModel] = []
    @Published var errorMessage: String?

    func fetchMeldingen() {
        // URL de l'endpoint
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/signalements") else {
            DispatchQueue.main.async {
                self.errorMessage = "URL invalide"
            }
            return
        }
        
        // Exécution de l'appel réseau
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "Aucune donnée reçue"
                }
                return
            }
            // Ajoute cette ligne pour debug
            print("Réponse brute :", String(data: data, encoding: .utf8) ?? "nil")

            do {
                let decoder = JSONDecoder()
                // Stratégie personnalisée pour gérer les fractions de secondes
                let isoFormatter = ISO8601DateFormatter()
                isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateStr = try container.decode(String.self)
                    guard let date = isoFormatter.date(from: dateStr) else {
                        throw DecodingError.dataCorruptedError(in: container,
                            debugDescription: "Format de date invalide: \(dateStr)")
                    }
                    return date
                }
                
                let decodedMeldingen = try decoder.decode([MeldingenModel].self, from: data)
                
                print("Décodage réussi : \(decodedMeldingen.count) éléments")
                    print("Détails :", decodedMeldingen)
                DispatchQueue.main.async {
                    self.meldingen = decodedMeldingen
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
            }
        }.resume()
    }
}
