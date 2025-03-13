import Foundation
import Combine

class MeldingenViewModel: ObservableObject {
    @Published var meldingen: [MeldingenModel] = []
    @Published var errorMessage: String?
    
    // Een statische ISO8601 formatter om datums met fractionele seconden te verwerken
    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()
    
    // Een aangepaste JSONDecoder die de ISO8601 datums met fractionele seconden decodeert
    private static var customDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let dateStr = try container.decode(String.self)
            guard let date = MeldingenViewModel.isoFormatter.date(from: dateStr) else {
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Ongeldig datumformaat: \(dateStr)"
                )
            }
            return date
        }
        return decoder
    }()
    
    // Haal meldingen op van het endpoint
    func fetchMeldingen() {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/signalements") else {
            DispatchQueue.main.async {
                self.errorMessage = "Ongeldige URL"
            }
            return
        }
        
        URLSession.shared.dataTask(with: url) { data, response, error in
            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }
            
            guard let data = data else {
                DispatchQueue.main.async {
                    self.errorMessage = "Geen data ontvangen"
                }
                return
            }
            
            do {
                let decodedMeldingen = try MeldingenViewModel.customDecoder.decode([MeldingenModel].self, from: data)
                print("Succesvol gedecodeerd: \(decodedMeldingen.count) items")
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

