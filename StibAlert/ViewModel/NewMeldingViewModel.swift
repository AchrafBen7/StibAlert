// NewMeldingViewModel.swift

import Foundation
import Combine

class NewMeldingViewModel: ObservableObject {
    @Published var MeldingCreated: MeldingCreated?
    @Published var errorMessage: String?
    
    // Un formateur ISO8601 capable de gérer ".000Z"
    private static let iso8601WithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    func postMelding(nieuweMelding: NewMeldingRequest) {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/signalements") else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL"
            }
            return
        }
        
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        
        // Encodage du body JSON
        do {
            let jsonData = try JSONEncoder().encode(nieuweMelding)
            request.httpBody = jsonData
        } catch {
            DispatchQueue.main.async {
                self.errorMessage = "Fout bij encodage: \(error.localizedDescription)"
            }
            return
        }
        
        URLSession.shared.dataTask(with: request) { data, response, error in
            // 1) Vérif. erreur réseau
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = "Netwerkfout: \(error.localizedDescription)"
                }
                return
            }
            
            // 2) Log status code
            if let httpResponse = response as? HTTPURLResponse {
                print("Status code:", httpResponse.statusCode)
                print("Headers:", httpResponse.allHeaderFields)
            }
            
            // 3) Vérif. data non nulle
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "Geen data ontvangen"
                }
                return
            }
            
            // 4) Debug : JSON brut
            let rawResponse = String(data: data, encoding: .utf8) ?? "nil"
            print("Ruwe response:", rawResponse)
            
            // 5) Décodage avec une stratégie personnalisée
            do {
                let decoder = JSONDecoder()
                decoder.dateDecodingStrategy = .custom { decoder in
                    let container = try decoder.singleValueContainer()
                    let dateStr = try container.decode(String.self)
                    
                    guard let date = Self.iso8601WithFractional.date(from: dateStr) else {
                        throw DecodingError.dataCorruptedError(
                            in: container,
                            debugDescription: "Format de date invalide : \(dateStr)"
                        )
                    }
                    return date
                }
                
                let responseData = try decoder.decode(CreateMeldingResponse.self, from: data)
                
                DispatchQueue.main.async {
                    self.MeldingCreated = responseData.signalement
                    self.errorMessage = nil  // ou message de succès si souhaité
                }
            } catch {
                // 👉 Tenter de décoder un message d'erreur retourné par l'API
                if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                    DispatchQueue.main.async {
                        self.errorMessage = apiError.message
                    }
                } else {
                    DispatchQueue.main.async {
                        self.errorMessage = "Decodering mislukt: \(error.localizedDescription)"
                    }
                }
            }
        }.resume()
    }
}
struct APIError: Decodable {
    let message: String
}

