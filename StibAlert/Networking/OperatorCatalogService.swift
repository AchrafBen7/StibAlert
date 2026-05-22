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

enum OperatorCatalogService {
    private struct LinesResponse: Decodable { let lines: [OperatorLine] }
    private struct DisruptionsResponse: Decodable { let alerts: [OperatorDisruption] }

    static func lines(operator op: TransitOperator) async -> [OperatorLine] {
        await fetch(path: "lines", op: op, decode: { try JSONDecoder().decode(LinesResponse.self, from: $0).lines }) ?? []
    }

    static func disruptions(operator op: TransitOperator) async -> [OperatorDisruption] {
        await fetch(path: "disruptions", op: op, decode: { try JSONDecoder().decode(DisruptionsResponse.self, from: $0).alerts }) ?? []
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
