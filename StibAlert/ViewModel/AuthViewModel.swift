//
//  AuthViewModel.swift
//  StibAlert
//
//  Created by studentehb on 26/03/2025.
//

import Foundation
import Combine

class AuthViewModel: ObservableObject {
    @Published var user: UserModel?
    @Published var isAuthenticated = false
    @Published var errorMessage: String?
    @Published var isLoading = false
    @Published var activationToken: String?
    @Published var votes: [String] = []
    private var aDejaVerifieConnexion = false
    
    
    private let baseURL = "https://stib-alert-backend.onrender.com/api/utilisateurs"
    
    func inscrire(nom: String, email: String, motDePasse: String) {
        print("[DEBUG] 🔄 Début inscription avec: \(email)")
        
        guard let url = URL(string: "\(baseURL)/inscription") else { return }
        
        let body = ["nom": nom, "email": email, "motDePasse": motDePasse]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        do {
            request.httpBody = try JSONEncoder().encode(body)
        } catch {
            self.errorMessage = "Erreur d'encodage"
            print("[DEBUG] ❌ Erreur d'encodage")
            return
        }
        
        isLoading = true
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                self.isLoading = false
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    print("[DEBUG] ❌ Erreur réseau : \(error.localizedDescription)")
                    return
                }
                
                // Debug: Print raw response if available
                if let data = data, let rawResponse = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Raw response: \(rawResponse)")
                }
                
                if let data = data,
                   let json = try? JSONDecoder().decode([String: String].self, from: data),
                   let token = json["activationToken"] {
                    self.activationToken = token
                    print("[DEBUG] ✅ Token reçu : \(token)")
                } else {
                    self.errorMessage = "Échec de l'inscription."
                    print("[DEBUG] ❌ Réponse inattendue")
                }
            }
        }.resume()
    }
    
    func activer(code: String) {
        print("[DEBUG] 🔄 Activation avec le code : \(code)")
        guard let token = activationToken,
              let url = URL(string: "\(baseURL)/activation") else {
            print("[DEBUG] ❌ Pas de token d'activation disponible")
            return
        }
        
        let body = ["activationToken": token, "activationCode": code]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        
        isLoading = true
        URLSession.shared.dataTask(with: request) { data, _, _ in
            DispatchQueue.main.async {
                self.isLoading = false
                self.activationToken = nil
                print("[DEBUG] ✅ Activation envoyée, token supprimé.")
            }
        }.resume()
    }
    
    func connexion(email: String, motDePasse: String) {
        print("[DEBUG] 🔄 Connexion en cours pour: \(email)")
        
        guard let url = URL(string: "\(baseURL)/connexion") else { return }
        
        let body = ["email": email, "motDePasse": motDePasse]
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONEncoder().encode(body)
        
        isLoading = true
        URLSession.shared.dataTask(with: request) { data, response, error in
            DispatchQueue.main.async {
                // Affichez le code de statut HTTP
                if let httpResponse = response as? HTTPURLResponse {
                    print("[DEBUG] HTTP Status Code: \(httpResponse.statusCode)")
                }
                // Affichez la réponse brute si disponible
                if let data = data, let rawResponse = String(data: data, encoding: .utf8) {
                    print("[DEBUG] Raw response: \(rawResponse)")
                }
                
                // Votre logique existante de gestion d'erreur et décodage
                self.isLoading = false
                
                if let error = error {
                    self.errorMessage = error.localizedDescription
                    print("[DEBUG] ❌ Erreur réseau : \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    self.errorMessage = "Erreur de connexion"
                    print("[DEBUG] ❌ Aucune donnée reçue")
                    return
                }
                
                do {
                    let response = try JSONDecoder().decode(ConnexionResponse.self, from: data)
                    self.user = response.utilisateur
                    KeychainManager.save(key: "jwt", value: response.token)
                    KeychainManager.save(key: "userId", value: response.utilisateur.id)
                    self.isAuthenticated = true  // Considérez que la connexion est réussie
                    print("[DEBUG] ✅ Connexion réussie pour \(response.utilisateur.email)")
                } catch {
                    self.errorMessage = "Identifiants incorrects"
                    print("[DEBUG] ❌ Erreur de décodage : \(error.localizedDescription)")
                }
                
            }
        }.resume()
        
    }
    
    func deconnexion() {
        guard let token = UserDefaults.standard.string(forKey: "jwt"),
              let url = URL(string: "\(baseURL)/deconnexion") else {
            print("[DEBUG] ❌ Pas de token trouvé pour la déconnexion.")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        print("[DEBUG] 🔄 Tentative de déconnexion...")
        
        URLSession.shared.dataTask(with: request) { _, response, error in
            DispatchQueue.main.async {
                self.user = nil
                self.isAuthenticated = false
                KeychainManager.delete(key: "jwt")
                KeychainManager.delete(key: "userId")
                
                if let error = error {
                    print("[DEBUG] ❌ Erreur de déconnexion : \(error.localizedDescription)")
                } else if let httpResponse = response as? HTTPURLResponse {
                    print("[DEBUG] ✅ Déconnexion effectuée (status: \(httpResponse.statusCode))")
                } else {
                    print("[DEBUG] ❓ Réponse inconnue lors de la déconnexion.")
                }
            }
        }.resume()
    }
    
    func verifierConnexion() {
        guard !aDejaVerifieConnexion else { return }
        aDejaVerifieConnexion = true
        
        if let token = KeychainManager.get(key: "jwt"),
           let userId = KeychainManager.get(key: "userId") {
            print("[DEBUG] ✅ Token et ID détectés, tentative de récupération du profil...")
            self.isAuthenticated = true
            
            if self.user == nil {
                self.fetchProfilUtilisateurDepuisStock(id: userId, token: token)
            }
        } else {
            print("[DEBUG] ❌ Aucun token ou ID trouvé, utilisateur non connecté")
            self.isAuthenticated = false
            self.user = nil
        }
    }
    
    
    
    
    func fetchProfilUtilisateurDepuisStock(id: String, token: String) {
        guard let url = URL(string: "\(baseURL)/\(id)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[❌] Erreur de requête : \(error.localizedDescription)")
                    return
                }
                
                guard let data = data else {
                    print("[❌] Aucune donnée reçue")
                    return
                }
                
                do {
                    let utilisateur = try JSONDecoder().decode(UserModel.self, from: data)
                    self.user = utilisateur
                    print("[✅] Profil chargé depuis stockage : \(utilisateur.email)")
                } catch {
                    print("[❌] Erreur de décodage : \(error.localizedDescription)")
                }
            }
        }.resume()
    }
    
    
    
    func fetchProfilUtilisateur() {
        guard let userId = user?.id,
              let token = UserDefaults.standard.string(forKey: "jwt"),
              let url = URL(string: "\(baseURL)/\(userId)") else {
            print("[❌] Erreur : pas d'ID utilisateur ou de token")
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("[❌] Erreur de requête : \(error.localizedDescription)")
                    self.errorMessage = "Impossible de charger le profil"
                    return
                }
                
                guard let data = data else {
                    print("[❌] Données non reçues")
                    self.errorMessage = "Pas de réponse"
                    return
                }
                
                do {
                    let utilisateur = try JSONDecoder().decode(UserModel.self, from: data)
                    self.user = utilisateur
                    print("[✅] Profil chargé : \(utilisateur.email)")
                } catch {
                    print("[❌] Erreur de décodage : \(error)")
                    self.errorMessage = "Erreur de lecture du profil"
                }
            }
        }.resume()
    }
    
    func fetchVotesUtilisateur() {
        guard let userId = user?.id,
              let token = KeychainManager.get(key: "jwt"),
              let url = URL(string: "\(baseURL)/\(userId)/votes") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "GET"
        request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if let data = data,
                   let json = try? JSONDecoder().decode([String].self, from: data) {
                    self.votes = json
                    print("[✅] Votes récupérés : \(json.count)")
                } else {
                    print("[❌] Erreur lors du fetch des votes.")
                }
            }
        }.resume()
    }
    var token: String? {
        return KeychainManager.get(key: "jwt")
    }
    
}

struct ConnexionResponse: Codable {
    let message: String
    let utilisateur: UserModel
    let token: String
}


