import Foundation
import SwiftUI

struct SearchSignalCluster: Identifiable, Equatable {
    enum Level: Equatable {
        case low
        case medium
        case high
    }

    let id: String
    let coordinate: TransitCoordinate
    let count: Int
    let level: Level

}

struct TransitVehicleMock: Identifiable, Equatable {
    let id = UUID()
    let label: String
}

struct TransitRouteMock: Identifiable, Equatable {
    let id = UUID()
    let code: String
    let icon: String
    let color: Color
    let path: [TransitCoordinate]
    let vehicles: [TransitVehicleMock]
}

enum TransitMapMockData {
    static let routes: [TransitRouteMock] = [
        .init(
            code: "M6",
            icon: "tram.fill",
            color: Color(hex: "#7AB4FF"),
            path: [
                .init(latitude: 50.8949, longitude: 4.3417),
                .init(latitude: 50.8820, longitude: 4.3495),
                .init(latitude: 50.8682, longitude: 4.3528),
                .init(latitude: 50.8559, longitude: 4.3603),
                .init(latitude: 50.8455, longitude: 4.3697)
            ],
            vehicles: [.init(label: "Metro 6"), .init(label: "Metro 6")]
        ),
        .init(
            code: "T7",
            icon: "tram.fill",
            color: Color(hex: "#57E3B6"),
            path: [
                .init(latitude: 50.8740, longitude: 4.3205),
                .init(latitude: 50.8614, longitude: 4.3324),
                .init(latitude: 50.8490, longitude: 4.3448),
                .init(latitude: 50.8361, longitude: 4.3577),
                .init(latitude: 50.8225, longitude: 4.3728)
            ],
            vehicles: [.init(label: "Tram 7"), .init(label: "Tram 7")]
        ),
        .init(
            code: "B95",
            icon: "bus.fill",
            color: Color(hex: "#FF9B2F"),
            path: [
                .init(latitude: 50.8466, longitude: 4.3572),
                .init(latitude: 50.8394, longitude: 4.3641),
                .init(latitude: 50.8308, longitude: 4.3725),
                .init(latitude: 50.8224, longitude: 4.3807),
                .init(latitude: 50.8138, longitude: 4.3815)
            ],
            vehicles: [.init(label: "Bus 95")]
        ),
    ]
}
