import Foundation
import CoreLocation
import Combine

class VehicleTrackingViewModel: ObservableObject {
    @Published var vehicles: [VehiclePosition] = []
    @Published var isTracking = false
    @Published var error: String?

    private var timer: Timer?
    private var previousPositions: [String: CLLocationCoordinate2D] = [:]
    private let baseURL = AppConfig.backendBaseURL
    private let pollInterval: TimeInterval = 10

    func startTracking() {
        guard AppConfig.isBackendEnabled else {
            isTracking = false
            vehicles = []
            error = nil
            stopTracking()
            return
        }
        guard !isTracking else { return }
        isTracking = true
        fetchPositions()
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchPositions()
        }
    }

    func stopTracking() {
        isTracking = false
        timer?.invalidate()
        timer = nil
    }

    func fetchPositions() {
        guard AppConfig.isBackendEnabled else {
            DispatchQueue.main.async {
                self.vehicles = []
                self.error = nil
            }
            return
        }
        guard let url = URL(string: "\(baseURL)/api/stib/vehicle-positions") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, response, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.error = error.localizedDescription
                }
                return
            }

            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode(VehiclePositionsResponse.self, from: data)
                let newVehicles = decoded.items.compactMap { dto -> VehiclePosition? in
                    guard let id = dto.vehicleId,
                          let line = dto.line,
                          let lat = dto.latitude,
                          let lon = dto.longitude else { return nil }

                    let coord = CLLocationCoordinate2D(latitude: lat, longitude: lon)
                    let prev = self.previousPositions[id]
                    self.previousPositions[id] = coord

                    return VehiclePosition(
                        id: id,
                        line: line,
                        direction: dto.direction ?? "",
                        coordinate: coord,
                        previousCoordinate: prev,
                        updatedAt: dto.updatedAt ?? ""
                    )
                }

                DispatchQueue.main.async {
                    self.vehicles = newVehicles
                    self.error = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.error = "Erreur de décodage: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    deinit {
        stopTracking()
    }
}
