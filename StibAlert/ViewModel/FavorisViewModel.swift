//
//  FavorisViewModel.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
//

import Foundation
import Combine

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
            .decode(type: UserModel.self, decoder: JSONDecoder())
            .flatMap { user in
                let ids = user.favoris ?? []
                let requests = ids.map { id -> AnyPublisher<HalteModel?, Never> in
                    guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/arrets/\(id)") else {
                        return Just(nil).eraseToAnyPublisher()
                    }
                    
                    return URLSession.shared.dataTaskPublisher(for: url)
                        .handleEvents(receiveOutput: { output in
                            if let raw = String(data: output.data, encoding: .utf8) {
                                print("✅ Réponse brute arrêt \(id):\n\(raw)")
                            }
                        })
                        .map(\.data)
                        .decode(type: HalteModel.self, decoder: JSONDecoder())
                        .map { Optional($0) }
                        .catch { _ in Just(nil) }
                        .eraseToAnyPublisher()
                }
                
                return Publishers.MergeMany(requests)
                    .compactMap { $0 }
                    .collect()
                    .mapError { $0 as Error }
                    .eraseToAnyPublisher()
            }
            .receive(on: DispatchQueue.main)
            .sink { completion in
                self.isLoading = false
                if case .failure(let error) = completion {
                    self.errorMessage = error.localizedDescription
                }
            } receiveValue: { haltes in
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
