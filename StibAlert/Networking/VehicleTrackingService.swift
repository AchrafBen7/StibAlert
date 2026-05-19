import Foundation
import Combine
import CoreLocation

private struct VehiclePositionsResponse: Decodable {
    let items: [TransportVehicleDTO]
}

@MainActor
final class VehicleTrackingService: ObservableObject {
    @Published private(set) var vehicles: [TransportVehicleDTO] = []
    @Published private(set) var vehicleBearings: [String: Double] = [:]
    @Published private(set) var isTracking = false

    private var pollingTask: Task<Void, Never>?
    private var previousPositions: [String: CLLocationCoordinate2D] = [:]
    private let interval: TimeInterval = 15

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
        previousPositions = [:]
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
                if let date = Self.iso8601WithMillis.date(from: raw) { return date }
                if let date = Self.iso8601Plain.date(from: raw) { return date }
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

            var newBearings = vehicleBearings
            for vehicle in fresh {
                guard
                    let vid = vehicle.vehicleId,
                    let lat = vehicle.latitude, let lng = vehicle.longitude,
                    let prev = previousPositions[vid]
                else { continue }
                let dist = CLLocation(latitude: lat, longitude: lng)
                    .distance(from: CLLocation(latitude: prev.latitude, longitude: prev.longitude))
                guard dist > 8 else { continue }
                newBearings[vid] = compassBearing(
                    from: prev,
                    to: CLLocationCoordinate2D(latitude: lat, longitude: lng)
                )
            }

            previousPositions = Dictionary(
                uniqueKeysWithValues: fresh.compactMap { v -> (String, CLLocationCoordinate2D)? in
                    guard let id = v.vehicleId, let lat = v.latitude, let lng = v.longitude else { return nil }
                    return (id, CLLocationCoordinate2D(latitude: lat, longitude: lng))
                }
            )

            // Glide animation is applied on the SwiftUI side via .animation()
            // on the consumer view — we keep this service UIKit-free so it
            // doesn't import SwiftUI (importing it here was masking other
            // symbols of the module).
            self.vehicles = fresh
            self.vehicleBearings = newBearings
            // Cache so a subsequent line switch shows trams instantly.
            cacheByLines[visibleLines] = fresh
            bearingsCacheByLines[visibleLines] = newBearings
        } catch {
            #if DEBUG
            print("[VehicleTracker] fetch failed for \(url.absoluteString): \(error.localizedDescription)")
            #endif
            // silently fail — map still works without vehicles
        }
    }

    private static let iso8601WithMillis: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    private static let iso8601Plain: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f
    }()

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
