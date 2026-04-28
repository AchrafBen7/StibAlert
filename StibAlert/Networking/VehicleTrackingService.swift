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
    private let interval: TimeInterval = 45

    var visibleLines: Set<String> = []

    func start(lines: Set<String>) {
        visibleLines = normalizedLines(from: lines)
        guard AppConfig.isBackendEnabled else { return }
        guard !visibleLines.isEmpty else {
            stop()
            return
        }
        guard pollingTask == nil else { return }
        isTracking = true
        pollingTask = Task { [weak self] in
            await self?.pollLoop()
        }
    }

    func updateLines(_ lines: Set<String>) {
        let normalized = normalizedLines(from: lines)
        guard normalized != visibleLines else { return }
        visibleLines = normalized

        guard AppConfig.isBackendEnabled else { return }
        guard !visibleLines.isEmpty else {
            stop()
            return
        }

        if pollingTask == nil {
            start(lines: visibleLines)
            return
        }

        Task { [weak self] in
            await self?.fetchVehicles()
        }
    }

    func stop() {
        pollingTask?.cancel()
        pollingTask = nil
        isTracking = false
        vehicles = []
    }

    private func pollLoop() async {
        while !Task.isCancelled {
            guard !visibleLines.isEmpty else {
                stop()
                return
            }
            await fetchVehicles()
            try? await Task.sleep(nanoseconds: UInt64(interval * 1_000_000_000))
        }
    }

    private func fetchVehicles() async {
        guard !visibleLines.isEmpty else {
            vehicles = []
            return
        }

        let lineParam = "&lines=\(visibleLines.sorted().joined(separator: ","))"
        guard let url = URL(string: "\(AppConfig.backendBaseURL)/api/stib/vehicle-positions?limit=200\(lineParam)") else { return }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .custom { dec in
                let container = try dec.singleValueContainer()
                let s = try container.decode(String.self)
                let precise = ISO8601DateFormatter()
                precise.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                if let d = precise.date(from: s) { return d }
                return ISO8601DateFormatter().date(from: s) ?? Date()
            }
            let response = try decoder.decode(VehiclePositionsResponse.self, from: data)
            let filtered = response.items.filter { v in
                guard let line = v.line else { return false }
                return visibleLines.contains(line)
            }
            self.vehicles = filtered
        } catch {
            // silently fail — map still works without vehicles
        }
    }

    private func normalizedLines(from lines: Set<String>) -> Set<String> {
        Set(
            lines
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
                .filter { !$0.isEmpty }
        )
    }
}
