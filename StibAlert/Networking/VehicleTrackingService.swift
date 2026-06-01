import Foundation
import Combine
import CoreLocation

private struct VehiclePositionsResponse: Decodable {
    let items: [TransportVehicleDTO]
}

// ISO-8601 parsers au niveau fichier (donc NON isolés MainActor) : référencés
// depuis la closure Sendable du JSONDecoder qui tourne hors du main actor.
// ISO8601DateFormatter est thread-safe en lecture (date(from:)).
nonisolated(unsafe) private let vehicleISO8601WithMillis: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
    return f
}()

nonisolated(unsafe) private let vehicleISO8601Plain: ISO8601DateFormatter = {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withInternetDateTime]
    return f
}()

@MainActor
final class VehicleTrackingService: ObservableObject {
    @Published private(set) var vehicles: [TransportVehicleDTO] = []
    @Published private(set) var vehicleBearings: [String: Double] = [:]
    @Published private(set) var isTracking = false

    private var pollingTask: Task<Void, Never>?
    private let interval: TimeInterval = 15

    // === Suivi d'identité stable des véhicules ===
    // Le backend renvoie un vehicleId « slot » = ligne:pointId:direction, avec
    // des coordonnées calées sur l'arrêt. Quand un métro avance d'un arrêt, son
    // id change donc entièrement → SwiftUI détruit/recrée l'annotation, le halo
    // redémarre et MapKit recycle les pins (ils « volent » hors du tracé). On
    // réassocie chaque position à un véhicule du poll précédent (même
    // ligne+direction, plus proche voisin) pour lui réattribuer un id STABLE :
    // le même métro garde le même pin et se déplace d'un cran, sans casse.
    private struct TrackedVehicle {
        var coordinate: CLLocationCoordinate2D
        let line: String
        let direction: String?
    }
    private var trackedVehicles: [String: TrackedVehicle] = [:]
    private var trackingSeq = 0
    /// Distance max entre deux polls pour considérer que c'est le même véhicule.
    /// Généreuse (≈ 2 arrêts, positions calées sur les arrêts) mais bien
    /// en-deçà de l'espacement typique entre 2 véhicules d'une même ligne.
    private let matchThresholdMeters: Double = 2500

    /// Per-line cache so that switching lines (or re-opening a stop on a
    /// line we already polled) feels instant: we re-emit the cached array
    /// while a fresh fetch runs in the background.
    private var cacheByLines: [Set<String>: [TransportVehicleDTO]] = [:]
    private var bearingsCacheByLines: [Set<String>: [String: Double]] = [:]

    var visibleLines: Set<String> = []
    var userLocation: CLLocationCoordinate2D?
    var proximityRadiusKm: Double = 1.5
    /// When false, the backend returns every live vehicle on the tracked
    /// lines instead of just those within `proximityRadiusKm` of the user.
    /// Set this to false in line-focus mode so the user can see trams
    /// anywhere along the tracé, not only around their own position.
    var proximityFilterEnabled: Bool = true

    func start(lines: Set<String>, location: CLLocationCoordinate2D? = nil) {
        visibleLines = normalizedLines(from: lines)
        userLocation = location
        guard AppConfig.isBackendEnabled else { return }
        guard !visibleLines.isEmpty else { stop(); return }
        guard pollingTask == nil else { return }
        isTracking = true
        pollingTask = Task { [weak self] in await self?.pollLoop() }
    }

    func updateLines(_ lines: Set<String>) {
        let normalized = normalizedLines(from: lines)
        guard normalized != visibleLines else { return }
        visibleLines = normalized

        guard AppConfig.isBackendEnabled else { return }
        guard !visibleLines.isEmpty else { stop(); return }

        // Optimistic display: if we polled this exact line set before, re-emit
        // the last-known positions so the map is never empty for the 500 ms –
        // 3 s the network round-trip takes. A fresh fetch starts right after.
        if let cached = cacheByLines[normalized] {
            self.vehicles = cached
            self.vehicleBearings = bearingsCacheByLines[normalized] ?? [:]
        } else {
            self.vehicles = []
            self.vehicleBearings = [:]
        }

        if pollingTask == nil {
            start(lines: visibleLines, location: userLocation)
            return
        }
        Task { [weak self] in await self?.fetchVehicles() }
    }

    func updateLocation(_ location: CLLocationCoordinate2D) {
        userLocation = location
        Task { [weak self] in await self?.fetchVehicles() }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isTracking = false
        vehicles = []
        vehicleBearings = [:]
        trackedVehicles = [:]
        trackingSeq = 0
    }

    /// One-shot snapshot of live vehicles for the given lines, fetched from
    /// the same enriched `vehicle-positions-map` endpoint the home map uses
    /// (each item carries `stopNom` + real coordinates — unlike the raw
    /// `/transport/line` vehicles). No proximity filter, so callers get every
    /// vehicle along the tracé. Used by detail screens that want a snapshot
    /// instead of a continuous poll.
    static func snapshot(lines: Set<String>) async -> [TransportVehicleDTO] {
        guard AppConfig.isBackendEnabled else { return [] }
        let normalized = lines
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        guard !normalized.isEmpty else { return [] }

        let params = "lines=\(normalized.sorted().joined(separator: ","))"
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib/vehicle-positions-map?\(params)") else { return [] }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let raw = try container.decode(String.self)
                if let date = vehicleISO8601WithMillis.date(from: raw) { return date }
                if let date = vehicleISO8601Plain.date(from: raw) { return date }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised ISO-8601 date: \(raw)"
                )
            }
            return try decoder.decode(VehiclePositionsResponse.self, from: data)
                .items
                .filter { $0.latitude != nil && $0.longitude != nil }
        } catch {
            #if DEBUG
            print("[VehicleTracker] snapshot failed for \(url.absoluteString): \(error.localizedDescription)")
            #endif
            return []
        }
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            guard !visibleLines.isEmpty else { stop(); return }
            await fetchVehicles()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func fetchVehicles() async {
        guard !visibleLines.isEmpty else { vehicles = []; return }

        var params = "lines=\(visibleLines.sorted().joined(separator: ","))"
        if proximityFilterEnabled, let loc = userLocation {
            params += "&lat=\(loc.latitude)&lng=\(loc.longitude)&rayon=\(proximityRadiusKm)"
        }

        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib/vehicle-positions-map?\(params)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            // Backend ships `updatedAt` as `2026-05-19T11:09:09.651Z`. The
            // stock `.iso8601` strategy doesn't accept fractional seconds, so
            // we install a custom decoder that tries both forms.
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let raw = try container.decode(String.self)
                if let date = vehicleISO8601WithMillis.date(from: raw) { return date }
                if let date = vehicleISO8601Plain.date(from: raw) { return date }
                throw DecodingError.dataCorruptedError(
                    in: container,
                    debugDescription: "Unrecognised ISO-8601 date: \(raw)"
                )
            }
            let response = try decoder.decode(VehiclePositionsResponse.self, from: data)
            let fresh = response.items.filter { $0.latitude != nil && $0.longitude != nil }
            #if DEBUG
            print("[VehicleTracker] \(url.absoluteString) → \(response.items.count) raw, \(fresh.count) with coords")
            #endif

            // Réattribue des identités stables (cf. TrackedVehicle) et calcule
            // les caps à partir du déplacement réel de chaque véhicule suivi.
            // C'est ce qui fixe le « ça bouge partout » : un même métro garde
            // son pin (et son halo) au lieu d'être détruit/recréé à chaque poll.
            let (stable, newBearings) = assignStableIdentities(to: fresh)

            self.vehicles = stable
            self.vehicleBearings = newBearings
            // Cache so a subsequent line switch shows trams instantly.
            cacheByLines[visibleLines] = stable
            bearingsCacheByLines[visibleLines] = newBearings
        } catch {
            #if DEBUG
            print("[VehicleTracker] fetch failed for \(url.absoluteString): \(error.localizedDescription)")
            #endif
            // silently fail — map still works without vehicles
        }
    }

    /// Associe chaque position fraîche à un véhicule du poll précédent (même
    /// ligne + direction, plus proche voisin non déjà réclamé) et lui réattribue
    /// son identité stable. Les nouveaux véhicules reçoivent un id neuf ; ceux
    /// qui disparaissent ne sont pas reconduits. Renvoie aussi les caps mis à
    /// jour, calculés sur le déplacement réel.
    private func assignStableIdentities(
        to fresh: [TransportVehicleDTO]
    ) -> (vehicles: [TransportVehicleDTO], bearings: [String: Double]) {
        var availableByGroup: [String: [String]] = [:]
        for (sid, tv) in trackedVehicles {
            availableByGroup[Self.groupKey(line: tv.line, direction: tv.direction), default: []].append(sid)
        }

        var claimed: Set<String> = []
        var updated: [String: TrackedVehicle] = [:]
        var newBearings: [String: Double] = [:]
        var result: [TransportVehicleDTO] = []
        result.reserveCapacity(fresh.count)

        // Ordre déterministe (nord→sud puis ouest→est) pour que l'appariement
        // greedy soit reproductible d'un poll à l'autre.
        let ordered = fresh.sorted { a, b in
            let la = a.latitude ?? 0, lb = b.latitude ?? 0
            if la != lb { return la > lb }
            return (a.longitude ?? 0) < (b.longitude ?? 0)
        }

        for v in ordered {
            guard let line = v.line, let lat = v.latitude, let lng = v.longitude else {
                result.append(v)
                continue
            }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            let group = Self.groupKey(line: line, direction: v.direction)

            var bestId: String?
            var bestDist = Double.greatestFiniteMagnitude
            for sid in availableByGroup[group] ?? [] where !claimed.contains(sid) {
                guard let prev = trackedVehicles[sid] else { continue }
                let d = CLLocation(latitude: lat, longitude: lng).distance(
                    from: CLLocation(latitude: prev.coordinate.latitude, longitude: prev.coordinate.longitude)
                )
                if d < bestDist { bestDist = d; bestId = sid }
            }

            let stableId: String
            if let bestId, bestDist <= matchThresholdMeters {
                stableId = bestId
                claimed.insert(bestId)
                // Cap seulement si le véhicule a réellement bougé, sinon on
                // conserve l'ancien pour ne pas faire pivoter la flèche à vide.
                if bestDist > 8, let prev = trackedVehicles[bestId] {
                    newBearings[stableId] = compassBearing(from: prev.coordinate, to: coord)
                } else if let kept = vehicleBearings[bestId] {
                    newBearings[stableId] = kept
                }
            } else {
                trackingSeq += 1
                stableId = "trk-\(group)-\(trackingSeq)"
            }

            updated[stableId] = TrackedVehicle(coordinate: coord, line: line, direction: v.direction)
            result.append(v.withVehicleId(stableId))
        }

        trackedVehicles = updated
        return (result, newBearings)
    }

    private static func groupKey(line: String, direction: String?) -> String {
        "\(line.uppercased())|\(direction ?? "")"
    }

    private func compassBearing(from: CLLocationCoordinate2D, to: CLLocationCoordinate2D) -> Double {
        let lat1 = from.latitude * .pi / 180
        let lat2 = to.latitude * .pi / 180
        let dLng = (to.longitude - from.longitude) * .pi / 180
        let y = sin(dLng) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLng)
        return (atan2(y, x) * 180 / .pi + 360).truncatingRemainder(dividingBy: 360)
    }

    private func normalizedLines(from lines: Set<String>) -> Set<String> {
        Set(lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
    }
}


private extension TransportVehicleDTO {
    /// Copie le DTO en ne remplaçant que l'identifiant — sert à substituer l'id
    /// « slot » du backend par un id de suivi stable (cf. assignStableIdentities).
    func withVehicleId(_ newId: String) -> TransportVehicleDTO {
        TransportVehicleDTO(
            vehicleId: newId,
            line: line,
            direction: direction,
            latitude: latitude,
            longitude: longitude,
            updatedAt: updatedAt,
            stopNom: stopNom,
            distanceFromPoint: distanceFromPoint
        )
    }
}
