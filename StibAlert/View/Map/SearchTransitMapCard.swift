import SwiftUI
import MapKit

struct SearchTransitMapView: View {
    let selectedScope: SearchScope
    let journey: SearchJourney?
    let activeStepPath: [CLLocationCoordinate2D]
    let snappedCoordinate: CLLocationCoordinate2D?

    @State private var position: MapCameraPosition = .region(
        MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.04, longitudeDelta: 0.04)
        )
    )

    var body: some View {
        Map(position: $position) {
            if let journey {
                MapPolyline(coordinates: journey.path.map(\.coordinate))
                    .stroke(Color(hex: "#B5CFF8"), style: StrokeStyle(lineWidth: 5, lineCap: .round, lineJoin: .round))

                if activeStepPath.count >= 2 {
                    MapPolyline(coordinates: activeStepPath)
                        .stroke(Color(hex: "#57E3B6"), style: StrokeStyle(lineWidth: 7, lineCap: .round, lineJoin: .round))
                }

                Annotation("", coordinate: journey.origin.coordinate.coordinate, anchor: .bottom) {
                    marker(color: Color(hex: "#57E3B6"), label: "A")
                }

                Annotation("", coordinate: journey.destination.coordinate.coordinate, anchor: .bottom) {
                    marker(color: Color(hex: "#FF9B2F"), label: "B")
                }

                if let snappedCoordinate {
                    Annotation("", coordinate: snappedCoordinate, anchor: .center) {
                        ZStack {
                            Circle()
                                .fill(Color(hex: "#57E3B6").opacity(0.22))
                                .frame(width: 28, height: 28)
                            Circle()
                                .fill(Color(hex: "#57E3B6"))
                                .frame(width: 12, height: 12)
                                .overlay(
                                    Circle()
                                        .stroke(Color.white.opacity(0.95), lineWidth: 2)
                                )
                        }
                    }
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .mapControls { }
        .environment(\.colorScheme, .light)
        .onAppear {
            recenterIfNeeded()
        }
        .onChange(of: journey?.destination.id) { _, _ in
            recenterIfNeeded()
        }
        .onChange(of: snappedCoordinate?.latitude) { _, _ in
            followGuidanceIfNeeded()
        }
        .onChange(of: snappedCoordinate?.longitude) { _, _ in
            followGuidanceIfNeeded()
        }
    }

    private func marker(color: Color, label: String) -> some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 28, height: 28)
            Text(label)
                .font(.custom("Montserrat-SemiBold", size: 12))
                .foregroundStyle(.black)
        }
    }

    private func recenterIfNeeded() {
        guard let journey else { return }
        let coordinates = journey.path.map(\.coordinate)
        guard !coordinates.isEmpty else { return }

        let latitudes = coordinates.map(\.latitude)
        let longitudes = coordinates.map(\.longitude)

        guard let minLat = latitudes.min(),
              let maxLat = latitudes.max(),
              let minLon = longitudes.min(),
              let maxLon = longitudes.max() else { return }

        let center = CLLocationCoordinate2D(
            latitude: (minLat + maxLat) / 2,
            longitude: (minLon + maxLon) / 2
        )

        let span = MKCoordinateSpan(
            latitudeDelta: max(0.02, (maxLat - minLat) * 1.6),
            longitudeDelta: max(0.02, (maxLon - minLon) * 1.6)
        )

        position = .region(MKCoordinateRegion(center: center, span: span))
    }

    private func followGuidanceIfNeeded() {
        guard let snappedCoordinate else { return }

        let currentSpan: MKCoordinateSpan
        if activeStepPath.count >= 2 {
            currentSpan = MKCoordinateSpan(latitudeDelta: 0.008, longitudeDelta: 0.008)
        } else {
            currentSpan = MKCoordinateSpan(latitudeDelta: 0.012, longitudeDelta: 0.012)
        }

        withAnimation(.easeInOut(duration: 0.35)) {
            position = .region(MKCoordinateRegion(center: snappedCoordinate, span: currentSpan))
        }
    }
}

private extension MapPolyline {
    init(coordinates: [CLLocationCoordinate2D]) {
        self.init(MKPolyline(coordinates: coordinates, count: coordinates.count))
    }
}
