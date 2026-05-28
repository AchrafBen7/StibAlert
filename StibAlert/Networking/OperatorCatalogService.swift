import Foundation

/// A De Lijn / TEC line from the backend catalog (built from the GTFS routes).
struct OperatorLine: Decodable, Identifiable, Hashable {
    let id: String
    let shortName: String
    let longName: String
    let mode: String
    let color: String
    let textColor: String

    enum CodingKeys: String, CodingKey {
        case id, mode, color
        case shortName = "short_name"
        case longName = "long_name"
        case textColor = "text_color"
    }

    var modeLabel: String {
        switch mode {
        case "tram": return "Tram"
        case "metro": return "Métro"
        case "trolleybus": return "Trolleybus"
        default: return "Bus"
        }
    }
}

/// An official De Lijn / TEC disruption from the backend (normalized GTFS-RT alerts).
struct OperatorDisruption: Decodable, Identifiable {
    let id: String
    let header: String
    let description: String
    let url: String
    let routeIds: [String]
}

/// Réponse enrichie : on garde `alerts` (compat ascendante) + on expose
/// `live` / `fetchedAt` pour afficher un badge "LIVE" vs "Snapshot" dans
/// l'onglet Infos trafic. Backend renvoie ces champs depuis mai 2026
/// (commits c42fb27 De Lijn, 0ae65db TEC) ; pour les anciens backends ou
/// pour STIB qui ne passe pas par cette route, `live` reste à false.
struct OperatorDisruptionsBundle {
    let alerts: [OperatorDisruption]
    let live: Bool
    let fetchedAt: Date?
}

enum OperatorCatalogService {
    private struct LinesResponse: Decodable { let lines: [OperatorLine] }
    private struct DisruptionsResponse: Decodable {
        let alerts: [OperatorDisruption]
        let live: Bool?
        let fetchedAt: Date?
    }

    static func lines(operator op: TransitOperator) async -> [OperatorLine] {
        await fetch(path: "lines", op: op, decode: { try JSONDecoder().decode(LinesResponse.self, from: $0).lines }) ?? []
    }

    /// Compatibilité ascendante — les call-sites existants reçoivent juste la liste.
    static func disruptions(operator op: TransitOperator) async -> [OperatorDisruption] {
        await disruptionsBundle(operator: op).alerts
    }

    /// Version enrichie pour les nouveaux call-sites qui veulent afficher
    /// un badge LIVE et la fraicheur des données.
    static func disruptionsBundle(operator op: TransitOperator) async -> OperatorDisruptionsBundle {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let resp: DisruptionsResponse? = await fetch(path: "disruptions", op: op, decode: { data in
            try decoder.decode(DisruptionsResponse.self, from: data)
        })
        return OperatorDisruptionsBundle(
            alerts: resp?.alerts ?? [],
            live: resp?.live ?? false,
            fetchedAt: resp?.fetchedAt
        )
    }

    private static func fetch<T>(path: String, op: TransitOperator, decode: (Data) throws -> T) async -> T? {
        guard AppConfig.isBackendEnabled,
              let url = URL(string: "\(AppConfig.backendBaseURL)/api/operators/\(op.rawValue)/\(path)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            return try decode(data)
        } catch {
            return nil
        }
    }
}
