import Foundation
import SwiftUI
import CoreLocation

struct ArretNearbyDTO: Decodable {
    let id: String
    let nom: String
    let latitude: Double
    let longitude: Double
    let distanceMeters: Int
    let lignes: [LigneNearbyDTO]

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, latitude, longitude, distanceMeters, lignes
    }
}

struct LigneNearbyDTO: Decodable {
    let lineid: String
    let typeTransport: String
    let couleur: String
    let destination: LigneNearbyDestination?
}

struct LigneNearbyDestination: Decodable {
    let fr: String?
    let nl: String?
}

enum NearbyStopService {
    static func fetchNearby(lat: Double, lng: Double, radius: Double = 600) async throws -> [NearbyStop] {
        let dtos: [ArretNearbyDTO] = try await APIClient.shared.request(
            "/api/arrets/nearby?lat=\(lat)&lng=\(lng)&radius=\(Int(radius))"
        )
        return dtos.map { toNearbyStop($0) }
    }

    private static func toNearbyStop(_ dto: ArretNearbyDTO) -> NearbyStop {
        let stopLines = dto.lignes.map { StopLine(number: $0.lineid, color: Color(hex: $0.couleur)) }
        let issueLines = dto.lignes.map { ligne -> NearbyIssueLine in
            NearbyIssueLine(
                number: ligne.lineid,
                color: Color(hex: ligne.couleur),
                direction: ligne.destination?.fr ?? ligne.lineid,
                crowding: .low,
                reliability: 80,
                lineTextColor: isLight(hex: ligne.couleur) ? .black : .white
            )
        }
        return NearbyStop(
            backendId: dto.id,
            name: dto.nom,
            lines: stopLines,
            distanceMeters: dto.distanceMeters,
            issueLines: issueLines,
            coordinate: CLLocationCoordinate2D(latitude: dto.latitude, longitude: dto.longitude)
        )
    }

    private static func isLight(hex: String) -> Bool {
        var h = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        if h.count == 3 { h = h.map { "\($0)\($0)" }.joined() }
        guard h.count == 6, let n = UInt64(h, radix: 16) else { return false }
        let r = Double((n >> 16) & 0xFF) / 255
        let g = Double((n >> 8) & 0xFF) / 255
        let b = Double(n & 0xFF) / 255
        return 0.299 * r + 0.587 * g + 0.114 * b > 0.6
    }
}
