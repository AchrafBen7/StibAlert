//
//  FavorisViewModel.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
//
//
//  FavorisViewModel.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
//
 
import Foundation
import Combine
 
 
private struct UserWithFavorisObjects: Codable {
    let favoris: [HalteModel]
}
 
 
class FavorisViewModel: ObservableObject {
    @Published var favoris: [HalteModel] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    
    private var cancellables = Set<AnyCancellable>()
    
    func fetchFavoris(for userId: String, token: String) {
        isLoading = true
        errorMessage = nil
        
        guard let urlUser = URL(string: "https://stib-alert-backend.onrender.com/api/utilisateurs/\(userId)") else {
            self.errorMessage = "URL invalide"
            return
        }
        
        var request = URLRequest(url: urlUser)
        request.httpMethod = "GET"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTaskPublisher(for: request)
            .handleEvents(receiveOutput: { output in
                if let raw = String(data: output.data, encoding: .utf8) {
                    print("✅ Réponse brute utilisateur :\n\(raw)")
                }
            })
            .map(\.data)
            .decode(type: UserWithFavorisObjects.self, decoder: JSONDecoder())
            .map { $0.favoris } // 👉 pas besoin de refaire des requêtes ici !
            .receive(on: DispatchQueue.main)
            .sink { completion in
                self.isLoading = false
                if case .failure(let error) = completion {
                    self.errorMessage = error.localizedDescription
                    print("❌ Erreur de décodage : \(error)")
                }
            } receiveValue: { haltes in
                print("✅ Haltes reçues : \(haltes.count)")
                self.favoris = haltes
            }
            .store(in: &cancellables)
    }
    
    
    func toggleFavori(userId: String, halteId: String, completion: @escaping () -> Void) {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/utilisateurs/\(userId)/favoris/\(halteId)") else {
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        
        URLSession.shared.dataTask(with: request) { data, _, error in
            DispatchQueue.main.async {
                if error != nil {
                    self.errorMessage = "Erreur réseau"
                } else {
                    completion()
                }
            }
        }.resume()
    }
}
