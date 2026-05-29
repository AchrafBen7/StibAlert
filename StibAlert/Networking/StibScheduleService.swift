import Foundation

/// Horaires théoriques d'un arrêt STIB (GTFS static), groupés par
/// ligne + direction + dayType (weekday / saturday / sunday). Source :
/// backend `/api/stib/schedule/:stopId` qui lit les 21 parts JSON du
/// snapshot GTFS officiel mai 2026.
///
/// Utilisé par l'onglet "Horaires" de `ArretDetailPage` pour atteindre la
/// parité avec `GareDetailPage` SNCB (qui avait déjà ce picker).
struct StibScheduleLine: Decodable, Identifiable, Hashable {
    let line: String
    let destination: String?
    let dayTypes: [String: [String]]

    var id: String { "\(line)|\(destination ?? "")" }

    /// Récupère les horaires (format "HH:MM") pour un type de jour donné.
    /// `dayType` attendus : "weekday" / "saturday" / "sunday".
    func departures(for dayType: String) -> [String] {
        dayTypes[dayType] ?? []
    }
}

struct StibStopSchedule: Decodable {
    let stopId: String
    let lines: [StibScheduleLine]
}

enum StibScheduleService {
    static func fetch(stopId: String) async -> StibStopSchedule? {
        guard AppConfig.isBackendEnabled,
              let encoded = stopId.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib/schedule/\(encoded)") else {
            return nil
        }
        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
                return nil
            }
            return try? JSONDecoder().decode(StibStopSchedule.self, from: data)
        } catch {
            return nil
        }
    }

    /// Détermine le dayType applicable selon une date donnée (default = now).
    /// "weekday" pour lun-ven, "saturday" pour samedi, "sunday" pour
    /// dimanche. Calcul sur l'heure locale Bruxelles.
    static func currentDayType(at date: Date = Date()) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        let weekday = calendar.component(.weekday, from: date) // 1 = sunday, 7 = saturday
        switch weekday {
        case 1: return "sunday"
        case 7: return "saturday"
        default: return "weekday"
        }
    }
}
