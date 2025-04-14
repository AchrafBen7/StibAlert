//
//  AlternativesViewModel.swift
//  StibAlert
//
//  Created by studentehb on 28/03/2025.
//

import Foundation
import Combine

class AlternativesViewModel: ObservableObject {
    @Published var suggestion: String = ""
    @Published var alternatives: [String] = []
    @Published var arret: String = ""
    @Published var ligne: String = ""
    @Published var isLoading = false
    @Published var error: String?

    func fetchAlternatives(for ligneID: String, arretID: String) {
        isLoading = true
        error = nil

        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/lignes/\(ligneID)/\(arretID)/alternatives") else {
            error = "URL invalide"
            return
        }

        URLSession.shared.dataTask(with: url) { data, _, err in
            DispatchQueue.main.async { self.isLoading = false }

            if let err = err {
                DispatchQueue.main.async {
                    self.error = err.localizedDescription
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.error = "Pas de données"
                }
                return
            }

            do {
                let decoded = try JSONDecoder().decode(AlternativeResponse.self, from: data)
                DispatchQueue.main.async {
                    self.arret = decoded.arret
                    self.ligne = decoded.ligneAffectee
                    self.alternatives = decoded.alternatives
                    self.suggestion = decoded.suggestion
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Erreur décodage : \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
