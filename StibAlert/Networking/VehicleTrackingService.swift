import Foundation
import Combine
import CoreLocation

private struct VehiclePositionsResponse: Decodable {
    let items: [TransportVehicleDTO]
}

@MainActor
final class VehicleTrackingService: ObservableObject {
    @Published private(set) var vehicles: [TransportVehicleDTO] = []
    @Published private(set) var isTracking = false

    private var pollingTask: Task<Void, Never>?
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
            self.vehicles = response.items.filter { $0.latitude != nil && $0.longitude != nil }
        } catch {
            // silently fail — map still works without vehicles
        }
    }

    private func normalizedLines(from lines: Set<String>) -> Set<String> {
        Set(lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }.filter { !$0.isEmpty })
    }
}
