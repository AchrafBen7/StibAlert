import CoreLocation
import Foundation

struct STIBAIContext: Encodable {
    var position: GeoPoint?
    var currentStartStop: NearStop?
    var activeTrip: ActiveTrip?
    var network: NetworkState?
    var disruptedLines: [String]?
    var travellersInfo: [TravellerInfo]?
    var nearbyStops: [NearStop]?
    var followedLines: [String]?
    var reports: [CommunityReport]?
    var proposedDestination: String?
    var proposedRoutes: [ProposedRoute]?
}

struct GeoPoint: Encodable {
    let lat: Double
    let lng: Double

    init(_ coordinate: CLLocationCoordinate2D) {
        lat = coordinate.latitude
        lng = coordinate.longitude
    }
}

struct NearStop: Encodable, Identifiable {
    let id: String
    let name: String
    let distance: Double
    let lines: [String]
    let mode: String?
}

struct ActiveTrip: Encodable {
    let fromName: String?
    let toName: String?
    let lines: [String]?
    let stopIds: [String]?
}

struct NetworkState: Encodable {
    let level: String
    let headline: String
    let affectedLines: [String]
}

struct TravellerInfo: Encodable {
    let priority: Int?
    let type: String?
    let title: String?
    let description: String?
    let lines: [String]?
    let points: [String]?
}

struct CommunityReport: Encodable {
    let line: String?
    let stop: String?
    let type: String?
    let ageMin: Int?
}

struct ProposedRoute: Encodable {
    var totalMin: Int?
    var walkMin: Int?
    var transitMin: Int?
    var fromStop: String?
    var toStop: String?
    var accessFromMeters: Int?
    var accessToMeters: Int?
    var steps: [RouteStep]?
    var transfers: Int?
    var hasDisruption: Bool?
    var disruptionReasons: [String]?
    var walkOnly: Bool?
    var info: [String]?
}

struct RouteStep: Encodable {
    let line: String?
    let fromName: String
    let toName: String
    let minutes: Int
    let disrupted: Bool?
    let reason: String?
}

struct STIBAIMessage: Identifiable, Equatable, Encodable {
    enum Role: String, Encodable {
        case user
        case assistant
    }

    let id: UUID
    let role: Role
    var content: String

    init(id: UUID = UUID(), role: Role, content: String) {
        self.id = id
        self.role = role
        self.content = content
    }

    enum CodingKeys: String, CodingKey {
        case role
        case content
    }
}

struct STIBAIRequest: Encodable {
    let messages: [STIBAIMessage]
    let context: STIBAIContext
}
