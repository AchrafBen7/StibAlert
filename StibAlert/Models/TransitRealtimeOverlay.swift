import Foundation
import CoreLocation

struct TravellersInformationResponse: Codable {
    let source: String?
    let endpoint: String?
    let count: Int
    let items: [TravellerInformationDTO]
}

struct TravellerInformationDTO: Codable {
    let id: String?
    let title: String?
    let description: String?
    let lines: [StringOrIntValue]?
    let stops: [StringOrIntValue]?
    let priority: String?
    let language: String?
    let updatedAt: String?
}

struct WaitingTimesResponse: Codable {
    let source: String?
    let endpoint: String?
    let count: Int
    let items: [WaitingTimeDTO]
}

struct WaitingTimeDTO: Codable {
    let stopId: String?
    let stopName: String?
    let line: String?
    let destination: String?
    let minutes: IntOrStringValue?
}

struct StopDetailsResponse: Codable {
    let source: String?
    let endpoint: String?
    let count: Int
    let items: [StopDetailDTO]
}

struct StopDetailDTO: Codable {
    let id: String?
    let name: String?
    let latitude: DoubleOrStringValue?
    let longitude: DoubleOrStringValue?
}

struct LineDisruption: Identifiable {
    enum Severity: Int {
        case low = 0
        case medium = 1
        case high = 2

        init(priority: String?) {
            let value = (priority ?? "").lowercased()
            if value.contains("high") || value.contains("major") || value.contains("severe") || value.contains("critical") {
                self = .high
            } else if value.contains("medium") || value.contains("warning") || value.contains("moderate") {
                self = .medium
            } else {
                self = .low
            }
        }
    }

    let id: String
    let line: String
    let title: String
    let description: String
    let severity: Severity
    let stopIDs: [String]
}

struct WaitingTimeStop: Identifiable {
    let id: String
    let stopName: String
    let line: String
    let destination: String
    let minutes: Int
    let coordinate: CLLocationCoordinate2D
}

enum StringOrIntValue: Codable {
    case string(String)
    case int(Int)

    var stringValue: String {
        switch self {
        case .string(let value):
            return value
        case .int(let value):
            return String(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let string = try? container.decode(String.self) {
            self = .string(string)
        } else if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else {
            throw DecodingError.typeMismatch(StringOrIntValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

enum IntOrStringValue: Codable {
    case int(Int)
    case string(String)

    var intValue: Int? {
        switch self {
        case .int(let value):
            return value
        case .string(let value):
            return Int(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let int = try? container.decode(Int.self) {
            self = .int(int)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(IntOrStringValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}

enum DoubleOrStringValue: Codable {
    case double(Double)
    case string(String)

    var doubleValue: Double? {
        switch self {
        case .double(let value):
            return value
        case .string(let value):
            return Double(value)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let double = try? container.decode(Double.self) {
            self = .double(double)
        } else if let string = try? container.decode(String.self) {
            self = .string(string)
        } else {
            throw DecodingError.typeMismatch(DoubleOrStringValue.self, .init(codingPath: decoder.codingPath, debugDescription: "Unsupported value"))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .double(let value):
            try container.encode(value)
        case .string(let value):
            try container.encode(value)
        }
    }
}
