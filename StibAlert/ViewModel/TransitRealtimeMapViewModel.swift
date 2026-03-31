import Foundation
import CoreLocation

final class TransitRealtimeMapViewModel: ObservableObject {
    @Published var vehicles: [VehiclePosition] = []
    @Published var lineShapes: [TransitLineShape] = []
    @Published var disruptions: [LineDisruption] = []
    @Published var waitingStops: [WaitingTimeStop] = []
    @Published var errorMessage: String?

    private let baseURL = AppConfig.backendBaseURL
    private let pollInterval: TimeInterval = 15
    private var timer: Timer?
    private var previousPositions: [String: CLLocationCoordinate2D] = [:]
    private var currentMode: TransitMapView.TransitMode = .bus
    private var stopDetailsByID: [String: CLLocationCoordinate2D] = [:]

    func start(mode: TransitMapView.TransitMode) {
        guard AppConfig.isBackendEnabled else {
            currentMode = mode
            stop()
            DispatchQueue.main.async {
                self.vehicles = []
                self.lineShapes = []
                self.disruptions = []
                self.waitingStops = []
                self.errorMessage = nil
            }
            return
        }
        currentMode = mode
        fetchAll()

        guard timer == nil else { return }
        timer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            self?.fetchAll()
        }
    }

    func stop() {
        timer?.invalidate()
        timer = nil
    }

    func updateMode(_ mode: TransitMapView.TransitMode) {
        currentMode = mode
        guard AppConfig.isBackendEnabled else { return }
        fetchAll()
    }

    func fetchAll() {
        guard AppConfig.isBackendEnabled else {
            DispatchQueue.main.async {
                self.vehicles = []
                self.lineShapes = []
                self.disruptions = []
                self.waitingStops = []
                self.errorMessage = nil
            }
            return
        }
        fetchShapeFiles(mode: currentMode)
        fetchVehiclePositions(mode: currentMode)
        fetchTravellersInformation(mode: currentMode)
        fetchWaitingTimes(mode: currentMode)
    }

    private func fetchShapeFiles(mode: TransitMapView.TransitMode) {
        guard var components = URLComponents(string: "\(baseURL)/api/stib/shape-files") else { return }
        components.queryItems = [
            URLQueryItem(name: "transportType", value: mode.queryValue),
        ]

        guard let url = components.url else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode(ShapeFilesResponse.self, from: data)
                let disruptionByLine = Dictionary(uniqueKeysWithValues: self.disruptions.map { ($0.line, $0) })
                let shapes = decoded.items.compactMap { dto -> TransitLineShape? in
                    guard let line = dto.line, !dto.polylines.isEmpty else { return nil }

                    let segments = dto.polylines.map { segment in
                        segment.map { CLLocationCoordinate2D(latitude: $0.latitude, longitude: $0.longitude) }
                    }
                    .filter { !$0.isEmpty }

                    guard !segments.isEmpty else { return nil }

                    let disruption = disruptionByLine[line]

                    return TransitLineShape(
                        id: dto.id ?? "\(line)-\(dto.direction ?? "default")",
                        line: line,
                        transportType: dto.transportType ?? mode.queryValue,
                        direction: dto.direction ?? "",
                        segments: segments,
                        disruptionSeverity: disruption?.severity ?? .low,
                        disruptionTitle: disruption?.title
                    )
                }

                DispatchQueue.main.async {
                    self.lineShapes = shapes
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Erreur de décodage shape-files: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fetchVehiclePositions(mode: TransitMapView.TransitMode) {
        guard let url = URL(string: "\(baseURL)/api/stib/vehicle-positions") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode(VehiclePositionsResponse.self, from: data)
                let vehicles = decoded.items.compactMap { dto -> VehiclePosition? in
                    guard let id = dto.vehicleId,
                          let line = dto.line,
                          let latitude = dto.latitude,
                          let longitude = dto.longitude else { return nil }

                    let coordinate = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
                    let previousCoordinate = self.previousPositions[id]
                    self.previousPositions[id] = coordinate

                    let vehicle = VehiclePosition(
                        id: id,
                        line: line,
                        direction: dto.direction ?? "",
                        coordinate: coordinate,
                        previousCoordinate: previousCoordinate,
                        updatedAt: dto.updatedAt ?? ""
                    )

                    return vehicle.transportType.matches(mode) ? vehicle : nil
                }

                DispatchQueue.main.async {
                    self.vehicles = vehicles
                    self.errorMessage = nil
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Erreur de décodage véhicules: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fetchTravellersInformation(mode: TransitMapView.TransitMode) {
        guard let url = URL(string: "\(baseURL)/api/stib/travellers-information") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode(TravellersInformationResponse.self, from: data)
                let disruptions = decoded.items.flatMap { dto -> [LineDisruption] in
                    let lines = (dto.lines ?? []).map(\.stringValue).filter { !$0.isEmpty }
                    let stopIDs = (dto.stops ?? []).map(\.stringValue).filter { !$0.isEmpty }
                    let severity = LineDisruption.Severity(priority: dto.priority)

                    return lines.compactMap { line in
                        let transport = VehiclePosition.transportType(for: line)
                        guard transport.matches(mode) else { return nil }

                        return LineDisruption(
                            id: dto.id ?? "\(line)-\(dto.updatedAt ?? UUID().uuidString)",
                            line: line,
                            title: dto.title ?? "Perturbation STIB",
                            description: dto.description ?? "",
                            severity: severity,
                            stopIDs: stopIDs
                        )
                    }
                }

                DispatchQueue.main.async {
                    self.disruptions = disruptions
                    self.lineShapes = self.lineShapes.map { shape in
                        var updatedShape = shape
                        if let disruption = disruptions.first(where: { $0.line == shape.line }) {
                            updatedShape.disruptionSeverity = disruption.severity
                            updatedShape.disruptionTitle = disruption.title
                        } else {
                            updatedShape.disruptionSeverity = .low
                            updatedShape.disruptionTitle = nil
                        }
                        return updatedShape
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Erreur de décodage perturbations: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fetchWaitingTimes(mode: TransitMapView.TransitMode) {
        guard let url = URL(string: "\(baseURL)/api/stib/waiting-times") else { return }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if let error = error {
                DispatchQueue.main.async {
                    self.errorMessage = error.localizedDescription
                }
                return
            }

            guard let data = data else { return }

            do {
                let decoded = try JSONDecoder().decode(WaitingTimesResponse.self, from: data)
                let candidates = decoded.items.compactMap { dto -> WaitingTimeCandidate? in
                    guard let stopId = dto.stopId,
                          let line = dto.line,
                          let minutes = dto.minutes?.intValue else { return nil }

                    let transport = VehiclePosition.transportType(for: line)
                    guard transport.matches(mode) else { return nil }

                    return WaitingTimeCandidate(
                        stopId: stopId,
                        stopName: dto.stopName ?? "Arrêt",
                        line: line,
                        destination: dto.destination ?? "",
                        minutes: minutes
                    )
                }
                .sorted { $0.minutes < $1.minutes }

                let uniqueStopIDs = Array(Set(candidates.map(\.stopId))).prefix(10)
                self.fetchStopDetails(for: Array(uniqueStopIDs)) { coordinatesByStopID in
                    let waitingStops = candidates.compactMap { candidate -> WaitingTimeStop? in
                        guard let coordinate = coordinatesByStopID[candidate.stopId] else { return nil }
                        return WaitingTimeStop(
                            id: "\(candidate.stopId)-\(candidate.line)-\(candidate.minutes)",
                            stopName: candidate.stopName,
                            line: candidate.line,
                            destination: candidate.destination,
                            minutes: candidate.minutes,
                            coordinate: coordinate
                        )
                    }

                    DispatchQueue.main.async {
                        self.waitingStops = Array(waitingStops.prefix(8))
                    }
                }
            } catch {
                DispatchQueue.main.async {
                    self.errorMessage = "Erreur de décodage waiting-times: \(error.localizedDescription)"
                }
            }
        }.resume()
    }

    private func fetchStopDetails(for stopIDs: [String], completion: @escaping ([String: CLLocationCoordinate2D]) -> Void) {
        let missingStopIDs = stopIDs.filter { stopDetailsByID[$0] == nil }

        if missingStopIDs.isEmpty {
            completion(stopDetailsByID)
            return
        }

        guard var components = URLComponents(string: "\(baseURL)/api/stib/stop-details") else {
            completion(stopDetailsByID)
            return
        }
        components.queryItems = missingStopIDs.map { URLQueryItem(name: "stopId", value: $0) }

        guard let url = components.url else {
            completion(stopDetailsByID)
            return
        }

        URLSession.shared.dataTask(with: url) { [weak self] data, _, error in
            guard let self = self else { return }

            if error != nil {
                completion(self.stopDetailsByID)
                return
            }

            guard let data = data,
                  let decoded = try? JSONDecoder().decode(StopDetailsResponse.self, from: data) else {
                completion(self.stopDetailsByID)
                return
            }

            var updated = self.stopDetailsByID
            decoded.items.forEach { dto in
                guard let id = dto.id,
                      let latitude = dto.latitude?.doubleValue,
                      let longitude = dto.longitude?.doubleValue else { return }

                updated[id] = CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
            }

            self.stopDetailsByID = updated
            completion(updated)
        }.resume()
    }

    deinit {
        stop()
    }
}

private extension TransitMapView.TransitMode {
    var queryValue: String {
        switch self {
        case .bus:
            return "bus"
        case .metro:
            return "metro"
        case .tram:
            return "tram"
        }
    }
}

private extension VehiclePosition.TransportType {
    func matches(_ mode: TransitMapView.TransitMode) -> Bool {
        switch (self, mode) {
        case (.bus, .bus), (.metro, .metro), (.tram, .tram):
            return true
        default:
            return false
        }
    }
}

private struct WaitingTimeCandidate {
    let stopId: String
    let stopName: String
    let line: String
    let destination: String
    let minutes: Int
}
