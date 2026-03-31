import Foundation
import CoreLocation

struct ShapeFilesResponse: Codable {
    let source: String?
    let endpoint: String?
    let count: Int
    let items: [ShapeFileDTO]
}

struct ShapeFileDTO: Codable {
    let id: String?
    let line: String?
    let transportType: String?
    let direction: String?
    let polylines: [[ShapeCoordinateDTO]]
}

struct ShapeCoordinateDTO: Codable {
    let latitude: Double
    let longitude: Double
}

struct TransitLineShape: Identifiable {
    let id: String
    let line: String
    let transportType: String
    let direction: String
    let segments: [[CLLocationCoordinate2D]]
    var disruptionSeverity: LineDisruption.Severity = .low
    var disruptionTitle: String? = nil

    var inferredTransport: VehiclePosition.TransportType {
        let normalized = transportType.lowercased()
        if normalized.contains("metro") || normalized.contains("subway") {
            return .metro
        }
        if normalized.contains("tram") {
            return .tram
        }

        guard let lineNumber = Int(line) else { return .bus }
        if (1...6).contains(lineNumber) && line.count == 1 {
            return .metro
        }
        if (1...19).contains(lineNumber) {
            return .tram
        }
        return .bus
    }
}
