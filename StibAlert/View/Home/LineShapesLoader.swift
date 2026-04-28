import Foundation
import SwiftUI
import CoreLocation

struct LineShape: Identifiable {
    let id: String
    let ligne: String
    let variant: Int
    let color: Color
    let coordinates: [CLLocationCoordinate2D]
}

private struct LineShapeFeature: Decodable {
    let ligne: String
    let variante: Int?
    let colorHex: String
    let geoShape: LineShapeGeo

    enum CodingKeys: String, CodingKey {
        case ligne, variante
        case colorHex = "color_hex"
        case geoShape = "geo_shape"
    }
}

private struct LineShapeGeo: Decodable {
    let geometry: LineShapeGeometry
}

private struct LineShapeGeometry: Decodable {
    let type: String
    let coordinates: [[Double]]
}

@MainActor
final class LineShapesLoader: ObservableObject {
    static let shared = LineShapesLoader()

    @Published private(set) var shapes: [LineShape] = []
    @Published private(set) var isLoaded: Bool = false
    private var loadTask: Task<Void, Never>? = nil

    private init() {}

    func loadIfNeeded() {
        guard !isLoaded, loadTask == nil else { return }
        loadTask = Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let parsed = Self.parseFromBundle()
            self.shapes = parsed
            self.isLoaded = true
            self.loadTask = nil
        }
    }

    private static func parseFromBundle() -> [LineShape] {
        guard let url = Bundle.main.url(forResource: "line-shapes", withExtension: "json") else {
            print("line-shapes.json not found in bundle")
            return []
        }
        do {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let decoder = JSONDecoder()
            let features = try decoder.decode([LineShapeFeature].self, from: data)
            return features.compactMap { feat in
                let coords = feat.geoShape.geometry.coordinates.compactMap { pair -> CLLocationCoordinate2D? in
                    guard pair.count >= 2 else { return nil }
                    return CLLocationCoordinate2D(latitude: pair[1], longitude: pair[0])
                }
                guard coords.count >= 2 else { return nil }
                return LineShape(
                    id: "\(feat.ligne)-\(feat.variante ?? 1)",
                    ligne: feat.ligne,
                    variant: feat.variante ?? 1,
                    color: Color(hex: feat.colorHex),
                    coordinates: coords
                )
            }
        } catch {
            print("Line shapes decode failed: \(error.localizedDescription)")
            return []
        }
    }

    func shapes(matchingNumbers numbers: Set<String>) -> [LineShape] {
        guard !numbers.isEmpty else { return [] }
        return shapes.filter { shape in
            guard let normalized = Self.normalizedLineNumber(from: shape.ligne) else { return false }
            return numbers.contains(normalized)
        }
    }

    static func normalizedLineNumber(from id: String) -> String? {
        let digitsPrefix = id.prefix { $0.isNumber }
        guard !digitsPrefix.isEmpty, let number = Int(digitsPrefix) else { return nil }
        return String(number)
    }
}
