import Foundation
import Combine

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

    func start(lines: Set<String>) {
        visibleLines = lines
        guard AppConfig.isBackendEnabled else { return }
        guard pollingTask == nil else { return }
        isTracking = true
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func updateLines(_ lines: Set<String>) {
        visibleLines = lines
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isTracking = false
        vehicles = []
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            await fetchVehicles()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func fetchVehicles() async {
        let lineParam = visibleLines.isEmpty ? "" : "&lineId=\(visibleLines.sorted().joined(separator: ","))"
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib/vehicle-positions?limit=200\(lineParam)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let s = try container.decode(String.self)
                if let d = iso.date(from: s) { return d }
                return ISO8601DateFormatter().date(from: s) ?? Date()
            }
            let response = try decoder.decode(VehiclePositionsResponse.self, from: data)
            let filtered = response.items.filter { v in
                guard let line = v.line else { return false }
                return visibleLines.isEmpty || visibleLines.contains(line)
            }
            self.vehicles = filtered
        } catch {
            // silently fail — map still works without vehicles
        }
    }
}
