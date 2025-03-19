//
//  AlleHaltesViewModel.swift
//  StibAlert
//
//  Created by studentehb on 19/03/2025.
//

import Foundation
import Combine

class AlleHaltesViewModel: ObservableObject {
    @Published var arrets: [HalteModel] = []
    @Published var errorMessage: String?

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
}
