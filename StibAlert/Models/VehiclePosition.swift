import Foundation
import CoreLocation

struct VehiclePositionsResponse: Codable {
    let source: String?
    let endpoint: String?
    let count: Int
    let items: [VehiclePositionDTO]
}

struct VehiclePositionDTO: Codable {
    let vehicleId: String?
    let line: String?
    let direction: String?
    let latitude: Double?
    let longitude: Double?
    let updatedAt: String?
}

struct VehiclePosition: Identifiable {
    let id: String
    let line: String
    let direction: String
    var coordinate: CLLocationCoordinate2D
    var previousCoordinate: CLLocationCoordinate2D?
    let updatedAt: String

    var bearing: Double {
        guard let prev = previousCoordinate else { return 0 }
        let dLon = coordinate.longitude - prev.longitude
        let y = sin(dLon * .pi / 180) * cos(coordinate.latitude * .pi / 180)
        let x = cos(prev.latitude * .pi / 180) * sin(coordinate.latitude * .pi / 180)
            - sin(prev.latitude * .pi / 180) * cos(coordinate.latitude * .pi / 180) * cos(dLon * .pi / 180)
        return atan2(y, x) * 180 / .pi
    }

    var transportType: TransportType {
        Self.transportType(for: line)
    }

    static func transportType(for line: String) -> TransportType {
        guard let lineNum = Int(line) else { return .bus }
        if (1...6).contains(lineNum) && line.count == 1 { return .metro }
        if (1...19).contains(lineNum) { return .tram }
        return .bus
    }

    enum TransportType {
        case bus, tram, metro

        var iconName: String {
            switch self {
            case .bus: return "bus.fill"
            case .tram: return "tram.fill"
            case .metro: return "train.side.front.car"
            }
        }

        var color: String {
            switch self {
            case .bus: return "#F18F5D"
            case .tram: return "#4557A1"
            case .metro: return "#E63946"
            }
        }
    }
}
