import Foundation

/// One real-time passage returned by the backend (matches the De Lijn shape
/// exposed by `delijnLiveService.js`). `delayMin` is `predicted - scheduled`
/// in minutes — negative means early, positive means late, 0 = on time.
/// `hasRealtime = false` means De Lijn only has a theoretical timetable for
/// this passage (still displayed, just without the "Live" badge).
struct OperatorRealtimePassage: Decodable, Hashable, Identifiable {
    let line: String
    let entity: String?
    let direction: String?
    let destination: String
    let destinationNl: String?
    let scheduledAt: Date?
    let predictedAt: Date?
    let delayMin: Int?
    let hasRealtime: Bool
    let tripId: String?

    var id: String {
        // Stable enough across refresh polls : scheduled time + line + trip
        let ts = (scheduledAt ?? predictedAt).map { ISO8601DateFormatter().string(from: $0) } ?? UUID().uuidString
        return "\(line)|\(tripId ?? "")|\(ts)"
    }

    /// Best effort effective arrival time : prefers real-time, falls back to
    /// scheduled. Used to sort + filter past passages.
    var effectiveTime: Date? { predictedAt ?? scheduledAt }
}

struct OperatorRealtimeReply: Decodable {
    let stopId: String?
    let entity: String?
    let live: Bool
    let fetchedAt: Date?
    let passages: [OperatorRealtimePassage]
    let error: String?
}

enum OperatorRealtimeService {
    /// Fetches the next live passages for a De Lijn stop. Returns nil if the
    /// backend is disabled, the network failed, or De Lijn isn't configured
    /// server-side. Caller is expected to show a graceful placeholder.
    static func delijnStop(_ stopId: String) async -> OperatorRealtimeReply? {
        guard AppConfig.isBackendEnabled else { return nil }
        let normalized = stopId.split(separator: ":").last.map(String.init) ?? stopId
        guard let encoded = normalized.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/operators/delijn/stops/\(encoded)/realtime") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse else { return nil }
            let decoder = JSONDecoder()
            // Custom date strategy : Node émet "...387Z" (fractional seconds)
            // que `.iso8601` Swift refuse → tout le décodage plante en
            // silence et on affiche du vide. Cf. note dans OperatorCatalogService.
            decoder.dateDecodingStrategy = .custom { dec in
                let s = try dec.singleValueContainer().decode(String.self)
                let withFrac = ISO8601DateFormatter()
                withFrac.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = withFrac.date(from: s) { return d }
                let noFrac = ISO8601DateFormatter()
                noFrac.formatOptions = [.withInternetDateTime]
                if let d = noFrac.date(from: s) { return d }
                throw DecodingError.dataCorruptedError(in: try dec.singleValueContainer(), debugDescription: "Invalid ISO8601: \(s)")
            }
            // B4 — différencier 200 (succès parse) vs 503 (backend non
            // configuré OU API De Lijn down). Avant les 2 retombaient sur
            // `{live:false, passages:[]}` indistinct → l'utilisateur voyait
            // "Aucun passage prévu" au lieu de "Service temporairement
            // indisponible" pour un backend down.
            switch http.statusCode {
            case 200:
                return try? decoder.decode(OperatorRealtimeReply.self, from: data)
            case 503:
                // Le backend peut renvoyer un body informatif — on essaie
                // de le parser, sinon on synthétise un message dégradé clair.
                if let decoded = try? decoder.decode(OperatorRealtimeReply.self, from: data) {
                    if decoded.error == nil {
                        return OperatorRealtimeReply(
                            stopId: decoded.stopId,
                            entity: decoded.entity,
                            live: false,
                            fetchedAt: decoded.fetchedAt,
                            passages: decoded.passages,
                            error: "Service temps réel temporairement indisponible."
                        )
                    }
                    return decoded
                }
                return OperatorRealtimeReply(
                    stopId: nil, entity: nil, live: false, fetchedAt: nil,
                    passages: [], error: "Service temps réel temporairement indisponible."
                )
            default:
                return nil
            }
        } catch {
            return nil
        }
    }
}
