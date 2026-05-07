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

    var visibleLines: Set<String> = []
    var userLocation: CLLocationCoordinate2D?
    var proximityRadiusKm: Double = 1.5

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
        if let loc = userLocation {
            params += "&lat=\(loc.latitude)&lng=\(loc.longitude)&rayon=\(proximityRadiusKm)"
        }

        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib/vehicle-positions-map?\(params)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            let response = try decoder.decode(VehiclePositionsResponse.self, from: data)
            let fresh = response.items.filter { $0.latitude != nil && $0.longitude != nil }

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

            self.vehicles = fresh
            self.vehicleBearings = newBearings
        } catch {
            // silently fail — map still works without vehicles
        }
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
