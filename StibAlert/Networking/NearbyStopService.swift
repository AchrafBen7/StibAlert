import Foundation
import SwiftUI
import CoreLocation

struct ArretNearbyDTO: Decodable {
    let id: String
    let nom: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Int
    let lignes: [LigneNearbyDTO]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, latitude, longitude, distanceMeters, lignes
    }
}

struct LigneNearbyDTO: Decodable {
    let lineid: String
    let typeTransport: String
    let couleur: String
    let destination: LigneNearbyDestination?
}

struct LigneNearbyDestination: Decodable {
    let fr: String?
    let nl: String?
}

private struct StaticTransitCatalog: Codable {
    let generatedAt: Date
    let stops: [StaticTransitStop]
    let lines: [String: StaticTransitLine]
}

private struct MergedTransitCatalog: Decodable {
    let generatedAt: Date?
    let stops: [MergedTransitStop]
    let lines: [String: MergedTransitLine]
}

private struct MergedTransitStop: Decodable {
    let id: Int
    let nameFr: String
    let nameNl: String?
    let latitude: Double
    let longitude: Double
    let lines: [String]
    let physicalStopIds: [String]?
}

private struct MergedTransitLine: Decodable {
    let lineId: String
    let direction: String?
    let destinationFr: String?
    let destinationNl: String?
    let colorHex: String?
    let typeTransport: String?
    let stops: [MergedTransitLineStop]
}

private struct MergedTransitLineStop: Decodable {
    let mergedStopId: Int
    let physicalStopId: String?
    let order: Int
    let nameFr: String
    let nameNl: String?
    let latitude: Double
    let longitude: Double
}

private struct StaticTransitStop: Codable {
    let id: String
    let stopId: String?
    let name: String
    let latitude: Double
    let longitude: Double
    let lines: [String]
}

private struct StaticTransitLine: Codable {
    let lineId: String
    let colorHex: String?
    let direction: String?
    let destinationFr: String?
    let typeTransport: String?
}

private struct StaticLineDTO: Decodable {
    let lineid: String
    let nomComplet: String?
    let nomCompletRetour: String?
    let typeTransport: String?
    let couleur: String?
    let direction: String?
}

private enum StaticTransitCatalogStore {
    private static let fileName = "stib-static-catalog.json"
    private static let bundledSeedFileName = "stib-static-catalog-merged"
    private static let maxAge: TimeInterval = 14 * 24 * 60 * 60

    static func loadOrRefresh() async throws -> StaticTransitCatalog? {
        let cached = loadFromDisk() ?? loadBundledSeed()
        let shouldRefresh = cached == nil || isExpired(cached)

        if shouldRefresh, AppConfig.isBackendEnabled {
            do {
                let refreshed = try await refreshFromBackend()
                saveToDisk(refreshed)
                return refreshed
            } catch {
                if let cached {
                    return cached
                }
                throw error
            }
        }

        return cached
    }

    private static func refreshFromBackend() async throws -> StaticTransitCatalog {
        let stops: [ArretDTO] = try await APIClient.shared.request("/api/arrets")
        let lines: [StaticLineDTO] = try await APIClient.shared.request("/api/lignes")

        let mappedStops = stops.compactMap { stop -> StaticTransitStop? in
            guard
                let latitude = stop.latitude,
                let longitude = stop.longitude
            else {
                return nil
            }

            return StaticTransitStop(
                id: stop.id,
                stopId: stop.stopId,
                name: stop.nom,
                latitude: latitude,
                longitude: longitude,
                lines: (stop.lignesDesservies ?? [])
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                    .filter { !$0.isEmpty }
            )
        }

        let mappedLines = Dictionary(
            uniqueKeysWithValues: lines.map { line in
                let key = line.lineid.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
                return (
                    key,
                    StaticTransitLine(
                        lineId: key,
                        colorHex: line.couleur,
                        direction: line.direction,
                        destinationFr: line.nomCompletRetour ?? line.nomComplet,
                        typeTransport: line.typeTransport
                    )
                )
            }
        )

        return StaticTransitCatalog(
            generatedAt: Date(),
            stops: mappedStops,
            lines: mappedLines
        )
    }

    private static func isExpired(_ catalog: StaticTransitCatalog?) -> Bool {
        guard let catalog else { return true }
        return Date().timeIntervalSince(catalog.generatedAt) > maxAge
    }

    private static func loadFromDisk() -> StaticTransitCatalog? {
        guard let url = fileURL(),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(StaticTransitCatalog.self, from: data)
    }

    private static func loadBundledSeed() -> StaticTransitCatalog? {
        guard let url = Bundle.main.url(forResource: bundledSeedFileName, withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            return nil
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        if let direct = try? decoder.decode(StaticTransitCatalog.self, from: data) {
            return direct
        }

        guard let merged = try? decoder.decode(MergedTransitCatalog.self, from: data) else {
            return nil
        }

        return normalizeMergedCatalog(merged)
    }

    private static func saveToDisk(_ catalog: StaticTransitCatalog) {
        guard let url = fileURL() else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601

        do {
            let data = try encoder.encode(catalog)
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            try data.write(to: url, options: .atomic)
        } catch {
            ErrorReporting.capture(error, tag: "nearbyStops.catalogSave")
        }
    }

    private static func fileURL() -> URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("StibAlert", isDirectory: true)
            .appendingPathComponent(fileName)
    }

    private static func normalizeMergedCatalog(_ merged: MergedTransitCatalog) -> StaticTransitCatalog {
        var stopVariants: [Int: [String]] = [:]
        for (variantKey, line) in merged.lines {
            for stop in line.stops {
                stopVariants[stop.mergedStopId, default: []].append(
                    variantKey.trimmingCharacters(in: .whitespacesAndNewlines)
                )
            }
        }

        let stops = merged.stops.map { stop in
            StaticTransitStop(
                id: String(stop.id),
                stopId: stop.physicalStopIds?.first,
                name: stop.nameFr,
                latitude: stop.latitude,
                longitude: stop.longitude,
                lines: (stopVariants[stop.id] ?? stop.lines)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty }
            )
        }

        let lines = Dictionary(uniqueKeysWithValues: merged.lines.map { key, line in
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            return (
                normalizedKey,
                StaticTransitLine(
                    lineId: line.lineId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased(),
                    colorHex: line.colorHex,
                    direction: line.direction,
                    destinationFr: line.destinationFr ?? line.destinationNl,
                    typeTransport: line.typeTransport
                )
            )
        })

        return StaticTransitCatalog(
            generatedAt: merged.generatedAt ?? Date(),
            stops: stops,
            lines: lines
        )
    }
}

enum NearbyStopService {
    /// Generic street/transit words that shouldn't drive a stop match on their
    /// own. Without this filter "avenue des desirs" was matching "AVENUE DU
    /// ROI" on the single word "avenue", and "rue de la fontaine" was matching
    /// any random street stop containing "rue".
    private static let genericLocationWords: Set<String> = [
        "rue", "avenue", "boulevard", "chaussee", "place", "square", "parc",
        "porte", "pont", "quai", "esplanade", "voie", "venelle", "passage",
        "impasse", "drève", "dreve", "carrefour", "gare", "station", "metro",
        "métro", "tram", "bus", "arret", "arrêt", "rond-point", "rondpoint",
        "des", "les", "aux", "sur", "sous", "par", "pour", "avec", "vers",
    ]

    /// Search the local static STIB catalog for a stop whose name best matches
    /// `query` (token-based scoring, accent-insensitive). Used by the STIB AI
    /// chat / voice flow to resolve a spoken/typed destination like
    /// "Delacroix" to the real STIB stop coordinate before falling back to
    /// Google geocoding (which has the right address coverage for non-transit
    /// destinations like "avenue des Désirs").
    static func searchStopByName(_ query: String) async -> (name: String, coordinate: CLLocationCoordinate2D)? {
        let queryNorm = normalize(query)
        let allTokens = queryNorm.split(separator: " ").map(String.init).filter { $0.count >= 3 }
        // Significant tokens = NOT generic street words ("avenue", "rue"…)
        // and NOT short articles ("des", "les"…). If none remain after the
        // filter, the query is "rue avenue place" or similar — there's no
        // way to disambiguate a stop, so let Google handle it.
        let significantTokens = allTokens.filter { !genericLocationWords.contains($0) }
        guard !significantTokens.isEmpty else { return nil }

        guard let catalog = try? await StaticTransitCatalogStore.loadOrRefresh(),
              !catalog.stops.isEmpty else {
            return nil
        }

        var best: (stop: StaticTransitStop, score: Int)?
        for stop in catalog.stops {
            let stopName = normalize(stop.name)
            let stopTokens = Set(stopName.split(separator: " ").map(String.init))
            var score = 0
            // Score uniquement sur les tokens significatifs — un stop qui
            // partage seulement "avenue" avec la query ne match plus.
            for token in significantTokens {
                if stopTokens.contains(token) {
                    score += 100 + token.count // exact word match
                } else if stopName.contains(" " + token) || stopName.hasPrefix(token + " ") {
                    score += 50 + token.count // word starts/contains
                } else if stopName.contains(token) {
                    score += 10 + token.count // substring (weaker)
                }
            }
            // Bonus si TOUS les tokens significatifs sont présents dans le
            // nom du stop (couvre "delacroix" → DELACROIX, et évite qu'un
            // stop avec 1 mot partagé sur 3 ne gagne).
            if significantTokens.allSatisfy({ stopTokens.contains($0) }) {
                score += 100
            }
            if score > (best?.score ?? 0) {
                best = (stop, score)
            }
        }

        // Seuil : il faut au minimum un EXACT WORD MATCH sur un token
        // significatif (100+) sinon on retombe sur Google plutôt que de
        // pousser un stop fragile.
        guard let best, best.score >= 100 else { return nil }
        return (best.stop.name, CLLocationCoordinate2D(latitude: best.stop.latitude, longitude: best.stop.longitude))
    }

    /// Top-N variant used by the autocomplete searchbar : returns the N best
    /// stop matches (sorted by score). Used to PREPEND STIB stops to the
    /// MKLocalSearch suggestions list so typing "dela" surfaces DELACROIX
    /// before random "Dela…" street matches.
    static func topStopsByName(_ query: String, limit: Int = 5) async -> [(name: String, coordinate: CLLocationCoordinate2D, lines: [String])] {
        let queryNorm = normalize(query)
        let allTokens = queryNorm.split(separator: " ").map(String.init).filter { $0.count >= 2 }
        let significantTokens = allTokens.filter { !genericLocationWords.contains($0) }
        // Pour l'autocomplete on accepte les prefixes courts ("del", "fla") —
        // si tous les tokens sont génériques, on retombe sur allTokens.
        let scoringTokens = significantTokens.isEmpty ? allTokens : significantTokens
        guard !scoringTokens.isEmpty else { return [] }

        guard let catalog = try? await StaticTransitCatalogStore.loadOrRefresh(),
              !catalog.stops.isEmpty else {
            return []
        }

        var scored: [(stop: StaticTransitStop, score: Int)] = []
        for stop in catalog.stops {
            let stopName = normalize(stop.name)
            let stopTokens = Set(stopName.split(separator: " ").map(String.init))
            var score = 0
            for token in scoringTokens {
                if stopTokens.contains(token) {
                    score += 100 + token.count
                } else if stopName.contains(" " + token) || stopName.hasPrefix(token) {
                    // Prefix match accepté ici (autocomplete) : "del" → "DELACROIX"
                    score += 60 + token.count
                } else if stopName.contains(token) {
                    score += 10 + token.count
                }
            }
            if scoringTokens.allSatisfy({ stopTokens.contains($0) }) {
                score += 80
            }
            if score >= 60 {
                scored.append((stop, score))
            }
        }

        return scored
            .sorted { $0.score > $1.score }
            .prefix(limit)
            .map { (name: $0.stop.name,
                    coordinate: CLLocationCoordinate2D(latitude: $0.stop.latitude, longitude: $0.stop.longitude),
                    lines: $0.stop.lines) }
    }

    private static func normalize(_ text: String) -> String {
        let folded = text
            .lowercased()
            .folding(options: .diacriticInsensitive, locale: AppLocale.current)
        return folded
            .replacingOccurrences(of: #"[^a-z0-9\s]"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
    }

    /// Recherche d'arrêts par nom OU numéro de ligne sur TOUT le réseau (pas
    /// seulement autour de l'utilisateur). Renvoie de vrais `backendId` Mongo,
    /// indispensables pour épingler un favori. Utilisé par la feuille « Ajouter
    /// un arrêt favori » : avant, elle ne filtrait que les arrêts dans 1,5 km,
    /// donc un arrêt éloigné comme « Paduwa » (bus 66) était introuvable.
    static func searchStopsByName(_ query: String) async throws -> [NearbyStop] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, AppConfig.isBackendEnabled else { return [] }

        let encoded = trimmed.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? trimmed
        let dtos: [ArretNearbyDTO] = try await APIClient.shared.request("/api/arrets/recherche?q=\(encoded)")
        let mapped = dtos.map { toNearbyStop($0) }

        // Enrichit les lignes manquantes depuis le catalogue local (même
        // traitement que fetchNearby) pour des badges cohérents.
        if let catalog = try? await StaticTransitCatalogStore.loadOrRefresh(),
           !catalog.stops.isEmpty {
            return enrichNearbyStops(mapped, using: catalog)
        }
        return mapped
    }

    static func fetchNearby(lat: Double, lng: Double, radius: Double = 600) async throws -> [NearbyStop] {
        if AppConfig.isBackendEnabled {
            do {
                let dtos: [ArretNearbyDTO] = try await APIClient.shared.request(
                    "/api/arrets/nearby?lat=\(lat)&lng=\(lng)&radius=\(Int(radius))"
                )
                if !dtos.isEmpty {
                    let mapped = dtos.map { toNearbyStop($0) }
                    if let catalog = try? await StaticTransitCatalogStore.loadOrRefresh(),
                       !catalog.stops.isEmpty {
                        return enrichNearbyStops(mapped, using: catalog)
                    }
                    return mapped
                }
            } catch {
                ErrorReporting.capture(error, tag: "nearbyStops.backend")
            }
        }

        if let catalog = try? await StaticTransitCatalogStore.loadOrRefresh(),
           !catalog.stops.isEmpty {
            return nearbyStops(from: catalog, lat: lat, lng: lng, radius: radius)
        }

        let dtos: [ArretNearbyDTO] = try await APIClient.shared.request(
            "/api/arrets/nearby?lat=\(lat)&lng=\(lng)&radius=\(Int(radius))"
        )
        return dtos.map { toNearbyStop($0) }
    }

    private static func nearbyStops(
        from catalog: StaticTransitCatalog,
        lat: Double,
        lng: Double,
        radius: Double
    ) -> [NearbyStop] {
        let origin = CLLocationCoordinate2D(latitude: lat, longitude: lng)

        return catalog.stops
            .map { stop in
                let coordinate = CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)
                let distance = haversineMeters(from: origin, to: coordinate)
                return (stop: stop, coordinate: coordinate, distance: distance)
            }
            .filter { $0.distance <= radius }
            .sorted { $0.distance < $1.distance }
            .prefix(24)
            .map { entry in
                let issueLines = issueLines(for: entry.stop, in: catalog)

                return NearbyStop(
                    backendId: entry.stop.id,
                    stopId: entry.stop.stopId,
                    name: entry.stop.name,
                    lines: uniqueStopLines(from: issueLines),
                    distanceMeters: Int(entry.distance.rounded()),
                    issueLines: issueLines,
                    coordinate: entry.coordinate
                )
            }
    }

    private static func toNearbyStop(_ dto: ArretNearbyDTO) -> NearbyStop {
        let stopLines = dto.lignes.map {
            StopLine(number: normalizedLineId($0.lineid), color: normalizedColor(from: $0.couleur))
        }
        let issueLines = dto.lignes.map { ligne -> NearbyIssueLine in
            NearbyIssueLine(
                number: normalizedLineId(ligne.lineid),
                color: normalizedColor(from: ligne.couleur),
                direction: ligne.destination?.fr ?? ligne.lineid,
                crowding: .low,
                reliability: 80,
                lineTextColor: isLight(hex: ligne.couleur) ? .black : .white
            )
        }
        return NearbyStop(
            backendId: dto.id,
            name: dto.nom,
            lines: stopLines,
            distanceMeters: dto.distanceMeters,
            issueLines: issueLines,
            coordinate: CLLocationCoordinate2D(latitude: dto.latitude, longitude: dto.longitude)
        )
    }

    private static func enrichNearbyStops(_ stops: [NearbyStop], using catalog: StaticTransitCatalog) -> [NearbyStop] {
        stops.map { stop in
            guard stop.lines.isEmpty else { return stop }
            guard let catalogStop = matchingCatalogStop(for: stop, in: catalog) else { return stop }

            let issueLines = issueLines(for: catalogStop, in: catalog)
            guard !issueLines.isEmpty else { return stop }

            return NearbyStop(
                backendId: stop.backendId,
                stopId: catalogStop.stopId ?? stop.stopId,
                name: stop.name,
                lines: uniqueStopLines(from: issueLines),
                distanceMeters: stop.distanceMeters,
                issueLines: issueLines,
                coordinate: stop.coordinate
            )
        }
    }

    private static func matchingCatalogStop(for stop: NearbyStop, in catalog: StaticTransitCatalog) -> StaticTransitStop? {
        if let backendId = stop.backendId,
           let direct = catalog.stops.first(where: { $0.id == backendId || $0.stopId == backendId }) {
            return direct
        }

        let normalizedName = normalizeStopName(stop.name)
        if let nameMatch = catalog.stops.first(where: { normalizeStopName($0.name) == normalizedName }) {
            return nameMatch
        }

        guard let coordinate = stop.coordinate else { return nil }
        return catalog.stops.min { lhs, rhs in
            coordinateDistance(
                from: coordinate,
                to: CLLocationCoordinate2D(latitude: lhs.latitude, longitude: lhs.longitude)
            ) < coordinateDistance(
                from: coordinate,
                to: CLLocationCoordinate2D(latitude: rhs.latitude, longitude: rhs.longitude)
            )
        }
    }

    private static func toNearbyIssueLine(lineId: String, metadata: StaticTransitLine?) -> NearbyIssueLine {
        let color = normalizedColor(from: metadata?.colorHex)
        let normalizedLine = normalizedLineId(lineId)
        let direction = metadata?.destinationFr ?? metadata?.direction ?? normalizedLine

        return NearbyIssueLine(
            number: normalizedLine,
            color: color,
            direction: direction,
            crowding: .low,
            reliability: 80,
            lineTextColor: color.isDark ? .white : .black
        )
    }

    private static func normalizedLineId(_ lineId: String) -> String {
        let normalized = lineId.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        return normalized.split(separator: ":").first.map(String.init) ?? normalized
    }

    private static func normalizeStopName(_ name: String) -> String {
        name
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: AppLocale.current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func metadata(for lineId: String, in catalog: StaticTransitCatalog) -> StaticTransitLine? {
        let normalized = normalizedLineId(lineId)
        if let exact = catalog.lines[normalized] {
            return exact
        }

        return catalog.lines.first(where: { _, value in
            value.lineId == normalized
        })?.value
    }

    private static func issueLines(for stop: StaticTransitStop, in catalog: StaticTransitCatalog) -> [NearbyIssueLine] {
        var seen = Set<String>()

        return stop.lines.compactMap { key in
            let normalizedKey = key.trimmingCharacters(in: .whitespacesAndNewlines)
            let issueLine = toNearbyIssueLine(
                lineId: normalizedKey,
                metadata: catalog.lines[normalizedKey] ?? metadata(for: normalizedKey, in: catalog)
            )
            let dedupeKey = "\(issueLine.number)|\(issueLine.direction)"
            guard seen.insert(dedupeKey).inserted else { return nil }
            return issueLine
        }
        .sorted {
            if $0.number == $1.number {
                return $0.direction.localizedCaseInsensitiveCompare($1.direction) == .orderedAscending
            }
            return $0.number.localizedStandardCompare($1.number) == .orderedAscending
        }
    }

    private static func uniqueStopLines(from issueLines: [NearbyIssueLine]) -> [StopLine] {
        var seen = Set<String>()
        return issueLines.compactMap { line in
            guard seen.insert(line.number).inserted else { return nil }
            return StopLine(number: line.number, color: line.color)
        }
    }

    private static func normalizedColor(from hex: String?) -> Color {
        guard let hex, !hex.isEmpty else { return Color(hex: "#3B82F6") }
        if hex.hasPrefix("#") {
            return Color(hex: hex)
        }
        return Color(hex: "#\(hex)")
    }

    private static func haversineMeters(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let radius = 6_371_000.0
        let dLat = (to.latitude - from.latitude) * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2)
        return 2 * radius * atan2(sqrt(h), sqrt(1 - h))
    }

    private static func coordinateDistance(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: from.latitude, longitude: from.longitude)
            .distance(from: CLLocation(latitude: to.latitude, longitude: to.longitude))
    }

    private static func isLight(hex: String) -> Bool {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let n = UInt64(h, radix: 16) else { return false }
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >> 8) & 0xFF) / 255
        let b = Double(n & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }
}
