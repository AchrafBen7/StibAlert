import CoreLocation
import MapKit
import SwiftUI

struct RouteModeSummary {
    let modeKey: String
    let title: String
    let durationText: String
    let isFastest: Bool
}

struct RouteVisualSegment {
    let tint: Color
    let weight: CGFloat
}

struct RouteDepartureInsight {
    let lineCode: String
    let modeText: String
    let waitText: String
    let departureText: String
    let arrivalText: String?
    let stopText: String?
    let isRealtime: Bool

    var titleText: String {
        "\(modeText) \(lineCode)"
    }

    var detailText: String {
        let destinationPart = stopText.map { "vers \($0)" }
        let arrivalPart = arrivalText.map { "arrivée \($0)" }
        return [destinationPart, "départ \(departureText)", arrivalPart]
            .compactMap { $0 }
            .joined(separator: " · ")
    }
}

struct InlineRouteStepItem: Identifiable {
    let id = UUID()
    let icon: String?
    let title: String
    let meta: String
    let lineCode: String?
    let timingBadge: String?
    let timingDetail: String?
    /// Minutes spent waiting at the next connection (gap between this leg's
    /// arrival and the following leg's departure). Drives the "Attente X min"
    /// connector so a long correspondence isn't silently hidden.
    var waitAfterMinutes: Int? = nil
}

struct RouteItinerarySegment {
    let timeText: String
    let placeTitle: String
    let icon: String?
    let accentColor: Color
    let stepCard: RouteItineraryStepCard?
    let durationBadge: String?
    var stopCountText: String? = nil
}

struct RouteItineraryStepCard {
    enum CardStyle {
        case mint
        case white
    }

    let style: CardStyle
    let title: String
    let subtitle: String
    let lineBadge: String?
    let serviceInfo: RouteTransitServiceInfo?
}

struct RouteTransitServiceInfo {
    let lineCode: String
    let statusTitle: String
    let detail: String
    let waitTime: String
}

extension Int {
    func clockString(from startDate: Date) -> String {
        let date = startDate.addingTimeInterval(TimeInterval(self * 60))
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }
}

extension CLLocationCoordinate2D {
    func distance(to other: CLLocationCoordinate2D) -> CLLocationDistance {
        CLLocation(latitude: latitude, longitude: longitude)
            .distance(from: CLLocation(latitude: other.latitude, longitude: other.longitude))
    }

    func bearing(to destination: CLLocationCoordinate2D) -> Double {
        let lat1 = latitude * .pi / 180
        let lon1 = longitude * .pi / 180
        let lat2 = destination.latitude * .pi / 180
        let lon2 = destination.longitude * .pi / 180
        let dLon = lon2 - lon1
        let y = sin(dLon) * cos(lat2)
        let x = cos(lat1) * sin(lat2) - sin(lat1) * cos(lat2) * cos(dLon)
        let bearing = atan2(y, x) * 180 / .pi
        return (bearing + 360).truncatingRemainder(dividingBy: 360)
    }
}

extension MKPolyline {
    var firstCoordinate: CLLocationCoordinate2D? {
        guard pointCount > 0 else { return nil }
        return points()[0].coordinate
    }
}

extension CLLocationDistance {
    var distanceLabel: String {
        if self >= 1000 {
            return String(format: "%.1f km", self / 1000)
        }
        return "\(max(1, Int(rounded()))) m"
    }
}
