// NewMeldingViewModel.swift

import Foundation
import Combine
import UIKit

class NewMeldingViewModel: ObservableObject {
    @Published var MeldingCreated: MeldingCreated?
    @Published var errorMessage: String?
    
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
            self.handleResponse(data: data, response: response, error: error)
        }.resume()
    }
    
    func postMeldingWithImage(nieuweMelding: NewMeldingRequest, image: UIImage) {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/signalements") else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL"
            }
            return
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        
        let boundary = UUID().uuidString
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")

        var body = Data()

        let fields: [String: String] = [
            "nomArret": nieuweMelding.nomArret,
            "ligne": nieuweMelding.ligne,
            "typeProbleme": nieuweMelding.typeProbleme,
            "description": nieuweMelding.description
        ]

        for (key, value) in fields {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(key)\"\r\n\r\n")
            body.append("\(value)\r\n")
        }

        if let imageData = image.jpegData(compressionQuality: 0.7) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"photo\"; filename=\"photo.jpg\"\r\n")
            body.append("Content-Type: image/jpeg\r\n\r\n")
            body.append(imageData)
            body.append("\r\n")
        }

        body.append("--\(boundary)--\r\n")
        request.httpBody = body

        URLSession.shared.dataTask(with: request) { data, response, error in
            self.handleResponse(data: data, response: response, error: error)
        }.resume()
    }
    
    private func handleResponse(data: Data?, response: URLResponse?, error: Error?) {
        if let error = error {
            DispatchQueue.main.async {
                self.errorMessage = "Netwerkfout: \(error.localizedDescription)"
            }
            return
        }

        guard let data = data else {
            DispatchQueue.main.async {
                self.errorMessage = "Geen data ontvangen"
            }
            return
        }

        print("Reçu:", String(data: data, encoding: .utf8) ?? "vide")

        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { decoder in
                let container = try decoder.singleValueContainer()
                let dateStr = try container.decode(String.self)
                guard let date = Self.iso8601WithFractional.date(from: dateStr) else {
                    throw DecodingError.dataCorruptedError(in: container, debugDescription: "Date invalide: \(dateStr)")
                }
                return date
            }

            let responseData = try decoder.decode(CreateMeldingResponse.self, from: data)
            DispatchQueue.main.async {
                self.MeldingCreated = responseData.signalement
                self.errorMessage = nil
            }

        } catch {
            if let apiError = try? JSONDecoder().decode(APIError.self, from: data) {
                DispatchQueue.main.async {
                    self.errorMessage = apiError.message
                }
            } else {
                DispatchQueue.main.async {
                    self.errorMessage = "Fout bij decoderen: \(error.localizedDescription)"
                }
            }
        }
    }
}

struct APIError: Decodable {
    let message: String
}
