import SwiftUI
import MapKit

struct SearchTransitMapView: View {
    let selectedScope: SearchScope
    let journey: SearchJourney?

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

                Annotation("", coordinate: journey.origin.coordinate.coordinate, anchor: .bottom) {
                    marker(color: Color(hex: "#57E3B6"), label: "A")
                }

                Annotation("", coordinate: journey.destination.coordinate.coordinate, anchor: .bottom) {
                    marker(color: Color(hex: "#FF9B2F"), label: "B")
                }
            }
        }
        .mapStyle(.standard(elevation: .realistic))
        .environment(\.colorScheme, .dark)
        .onAppear {
            recenterIfNeeded()
        }
        .onChange(of: journey?.destination.id) { _, _ in
            recenterIfNeeded()
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
}

private extension MapPolyline {
    init(coordinates: [CLLocationCoordinate2D]) {
        self.init(MKPolyline(coordinates: coordinates, count: coordinates.count))
    }
}
