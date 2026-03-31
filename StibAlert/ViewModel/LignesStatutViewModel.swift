//
//  LignesStatutViewModel.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//
import Foundation

class LignesStatutViewModel: ObservableObject {
    @Published var statuts: [LigneEtat] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    func fetchEtatLignes() {
        guard AppConfig.isBackendEnabled else {
            statuts = []
            isLoading = false
            errorMessage = nil
            return
        }
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/lignes/etat-lignes") else { return }

        isLoading = true
        errorMessage = nil

        URLSession.shared.dataTask(with: url) { data, _, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    return
                }

                guard let data = data else {
                    self.errorMessage = "Aucune donnée reçue."
                    return
                }

                do {
                    let decoded = try JSONDecoder().decode([LigneEtat].self, from: data)
                    self.statuts = decoded
                } catch {
                    self.errorMessage = "Erreur de décodage : \(error.localizedDescription)"
                }
            }
        }.resume()
    }
}
