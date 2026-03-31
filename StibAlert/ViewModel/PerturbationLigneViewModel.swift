//
//  PerturbationLigneViewModel.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//
import Foundation

class PerturbationLigneViewModel: ObservableObject {
    @Published var signalements: [Signalement] = []
    @Published var resume: String = ""
    @Published var isLoading = false
    @Published var error: String?

    func fetchPerturbations(for lineID: String) {
        guard AppConfig.isBackendEnabled else {
            signalements = []
            resume = ""
            isLoading = false
            error = nil
            return
        }
        print("📡 Début du fetch des perturbations pour la ligne \(lineID)")
        isLoading = true
        error = nil

        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/lignes/\(lineID)/perturbations") else {
            self.error = "URL invalide"
            print("❌ URL invalide")
            return
        }

        print("🌍 Requête envoyée à : \(url)")

        URLSession.shared.dataTask(with: url) { data, response, err in
            DispatchQueue.main.async {
                self.isLoading = false
            }

            if let err = err {
                DispatchQueue.main.async {
                    self.error = err.localizedDescription
                    print("❌ Erreur réseau : \(err.localizedDescription)")
                }
                return
            }

            guard let data = data else {
                DispatchQueue.main.async {
                    self.error = "Pas de données"
                    print("❌ Aucune donnée reçue")
                }
                return
            }

            if let jsonString = String(data: data, encoding: .utf8) {
                print("📥 Données brutes reçues :\n\(jsonString)")
            }

            do {
                let decoder = JSONDecoder()
                let decoded = try decoder.decode(PerturbationResponse.self, from: data)
                DispatchQueue.main.async {
                    self.signalements = decoded.signalements
                    self.resume = decoded.resume
                    print("✅ Décodage réussi. \(decoded.signalements.count) signalement(s) récupéré(s).")
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Erreur de décodage : \(error.localizedDescription)"
                    print("❌ Erreur de décodage : \(error.localizedDescription)")
                }
            }
        }.resume()
    }
}
