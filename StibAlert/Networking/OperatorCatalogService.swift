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

    /// Cache mémoire pour éviter de re-fetch des payloads disruptions
    /// volumineux (TEC = 5+ MB, 1300+ alertes) à chaque ouverture de
    /// l'onglet Infos trafic. TTL court : 60 s pour disruptions, 1 h pour
    /// lines (catalogue stable, change rarement).
    private actor Cache {
        var disruptions: [TransitOperator: (bundle: OperatorDisruptionsBundle, at: Date)] = [:]
        var lines: [TransitOperator: (data: [OperatorLine], at: Date)] = [:]
        let disruptionsTTL: TimeInterval = 60
        let linesTTL: TimeInterval = 3600

        func getDisruptions(_ op: TransitOperator) -> OperatorDisruptionsBundle? {
            guard let entry = disruptions[op], Date().timeIntervalSince(entry.at) < disruptionsTTL else { return nil }
            return entry.bundle
        }
        func setDisruptions(_ op: TransitOperator, _ bundle: OperatorDisruptionsBundle) {
            disruptions[op] = (bundle, Date())
        }
        func getLines(_ op: TransitOperator) -> [OperatorLine]? {
            guard let entry = lines[op], Date().timeIntervalSince(entry.at) < linesTTL else { return nil }
            return entry.data
        }
        func setLines(_ op: TransitOperator, _ data: [OperatorLine]) {
            lines[op] = (data, Date())
        }
        func invalidate() {
            disruptions.removeAll()
            lines.removeAll()
        }
    }
    private static let cache = Cache()

    /// Force le prochain appel à re-fetch — utile sur pull-to-refresh.
    static func invalidateCache() async {
        await cache.invalidate()
    }

    static func lines(operator op: TransitOperator) async -> [OperatorLine] {
        if let cached = await cache.getLines(op) { return cached }
        let fresh = await fetch(path: "lines", op: op, decode: { try JSONDecoder().decode(LinesResponse.self, from: $0).lines }) ?? []
        if !fresh.isEmpty { await cache.setLines(op, fresh) }
        return fresh
    }

    /// Compatibilité ascendante — les call-sites existants reçoivent juste la liste.
    static func disruptions(operator op: TransitOperator) async -> [OperatorDisruption] {
        await disruptionsBundle(operator: op).alerts
    }

    /// Version enrichie pour les nouveaux call-sites qui veulent afficher
    /// un badge LIVE et la fraicheur des données. Cache TTL 60 s — évite
    /// de retélécharger le payload TEC complet (1300+ alertes, ~5 MB) à
    /// chaque retour sur l'onglet Infos trafic.
    static func disruptionsBundle(operator op: TransitOperator) async -> OperatorDisruptionsBundle {
        if let cached = await cache.getDisruptions(op) { return cached }
        let decoder = JSONDecoder()
        // Important : Node émet des dates avec millisecondes ("2026-05-28T13:08:44.387Z")
        // que `.iso8601` Swift NE parse PAS. Sans ce custom decoder, n'importe
        // quelle date dans la réponse fait planter tout le décodage → alerts
        // vides → "Réseau OK" alors qu'on a 300+ alertes en prod. On utilise
        // donc ISO8601DateFormatter en mode .withFractionalSeconds.
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
        let resp: DisruptionsResponse? = await fetch(path: "disruptions", op: op, decode: { data in
            try decoder.decode(DisruptionsResponse.self, from: data)
        })
        // B6 — ne CACHER que les succès. Avant on cachait même les bundles
        // vides (`resp == nil`), bloquant le user sur "Réseau OK" pendant
        // 60 s après un cold start raté. Maintenant si l'appel échoue, on
        // retourne un bundle vide MAIS sans le mémoriser → le prochain
        // affichage (pull-to-refresh, retour sur l'onglet) retentera tout
        // de suite.
        if let resp {
            let bundle = OperatorDisruptionsBundle(
                alerts: resp.alerts,
                live: resp.live ?? false,
                fetchedAt: resp.fetchedAt
            )
            await cache.setDisruptions(op, bundle)
            return bundle
        }
        return OperatorDisruptionsBundle(alerts: [], live: false, fetchedAt: nil)
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
