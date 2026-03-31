//
//  TransitMapView.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//

import SwiftUI
import MapKit


struct TransitMapView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @Binding var navigateToConnexion: Bool
    @State private var startingAddress: String = ""
    @State private var destinationAddress: String = ""
    @State private var selectedField: FieldType? = nil

    @State private var cameraPosition: MapCameraPosition = .region(MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    ))
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTransit: TransitMode = .bus
    @State private var bottomSheetExpanded: Bool = false
    @StateObject private var lijnenVM = LijnenViewModel()
    @StateObject private var mapViewModel = MapViewModel()
    @StateObject private var realtimeMapViewModel = TransitRealtimeMapViewModel()
    @State private var route: MKRoute? = nil
    @State private var startCoordinate: CLLocationCoordinate2D? = nil
    @State private var destinationCoordinate: CLLocationCoordinate2D? = nil
    @State private var showAddSignalement = false
    @State private var isHovering = false
    @State private var showVehicles = true
    @State private var selectedVehicle: VehiclePosition? = nil

    enum TransitMode: String, CaseIterable, Identifiable {
        case bus, metro, tram
        var id: String { self.rawValue }
    }

    enum FieldType {
        case start
        case destination
    }

    var body: some View {
        ZStack(alignment: .bottom) {

            // Carte 3D avec MapKit iOS 17+
            Map(position: $cameraPosition) {
                // Position utilisateur
                if let userLoc = locationManager.userLocation {
                    Annotation("", coordinate: userLoc) {
                        PulsatingUserLocationView()
                    }
                }

                // Marqueur de départ
                if let start = startCoordinate {
                    Annotation("Départ", coordinate: start) {
                        Circle()
                            .fill(Color.green)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }

                // Marqueur de destination
                if let dest = destinationCoordinate {
                    Annotation("Destination", coordinate: dest) {
                        Circle()
                            .fill(Color.red)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }

                ForEach(shapeSegments) { shapeSegment in
                    MapPolyline(shapeSegment.polyline)
                        .stroke(shapeSegment.strokeColor, lineWidth: shapeSegment.lineWidth)
                }

                // Tracé de la route
                if let route = route {
                    MapPolyline(route.polyline)
                        .stroke(Color(hex: "#F18F5D"), lineWidth: 5)
                }

                // Véhicules en temps réel
                if showVehicles {
                    ForEach(realtimeMapViewModel.vehicles) { vehicle in
                        Annotation("", coordinate: vehicle.coordinate) {
                            VehicleMarkerView(vehicle: vehicle)
                                .onTapGesture {
                                    selectedVehicle = vehicle
                                }
                        }
                    }
                }

                ForEach(realtimeMapViewModel.waitingStops) { stop in
                    Annotation(stop.stopName, coordinate: stop.coordinate) {
                        WaitingTimeMarkerView(stop: stop)
                    }
                }
            }
            .mapStyle(.standard(elevation: .realistic, emphasis: .automatic, pointsOfInterest: .including([.publicTransport]), showsTraffic: true))
            .mapControls {
                MapCompass()
                MapPitchToggle()
                MapScaleView()
            }

            // Overlay UI
            VStack {
                HStack {
                    // Bouton profil
                    if authViewModel.isAuthenticated, let user = authViewModel.user {
                        NavigationLink(destination: ProfilView(authViewModel: authViewModel)) {
                            Text(String(user.nom.prefix(1)).uppercased())
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color(hex: "#4557A1"))
                                .clipShape(Circle())
                        }
                    } else {
                        Button {
                            navigateToConnexion = true
                        } label: {
                            Image(systemName: "person")
                                .font(.system(size: 20))
                                .foregroundColor(.white)
                                .frame(width: 36, height: 36)
                                .background(Color.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    Spacer()

                    // Toggle véhicules temps réel
                    Button {
                        showVehicles.toggle()
                        if showVehicles {
                            realtimeMapViewModel.start(mode: selectedTransit)
                        } else {
                            realtimeMapViewModel.stop()
                        }
                    } label: {
                        Image(systemName: showVehicles ? "bus.fill" : "bus")
                            .font(.system(size: 18))
                            .foregroundColor(showVehicles ? .white : .gray)
                            .frame(width: 36, height: 36)
                            .background(showVehicles ? Color(hex: "#4557A1") : Color.black.opacity(0.6))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                    }
                }
                .padding(.top, 60)
                .padding(.horizontal, 16)

                // Compteur de véhicules
                if showVehicles && !realtimeMapViewModel.vehicles.isEmpty {
                    HStack {
                        Spacer()
                        Text("\(realtimeMapViewModel.vehicles.count) véhicules en direct")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 6)
                            .background(Color(hex: "#4557A1").opacity(0.85))
                            .clipShape(Capsule())
                            .padding(.trailing, 16)
                    }
                }

                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            .onReceive(locationManager.$userLocation) { newLocation in
                if let newLocation = newLocation {
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: newLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        ))
                    }
                }
            }

            // Info bulle du véhicule sélectionné
            if let vehicle = selectedVehicle {
                VehicleInfoBubble(vehicle: vehicle) {
                    selectedVehicle = nil
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .padding(.bottom, 260)
                .zIndex(1)
            }

            if let disruption = primaryDisruption {
                VStack {
                    Spacer()
                    DisruptionBanner(disruption: disruption)
                        .padding(.horizontal, 16)
                        .padding(.bottom, 360)
                }
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(1)
            }

            DraggableBottomSheet(
                onSubmitSearch: rechercherTrajet,
                destinationAddress: $destinationAddress,
                searchResults: mapViewModel.searchResults,
                onSelectSuggestion: selectSuggestion,
                selectedTransit: $selectedTransit,
                isExpanded: $bottomSheetExpanded,
                lijnenVM: lijnenVM
            )
            .onAppear {
                lijnenVM.fetchLijnen()
                realtimeMapViewModel.start(mode: selectedTransit)
            }
            .onDisappear {
                realtimeMapViewModel.stop()
            }

            if locationManager.showLocationError {
                VStack {
                    Text("Fout in locatie. Activeer de positie.")
                        .foregroundColor(.white)
                        .padding()
                        .background(Color.red)
                        .cornerRadius(12)
                        .padding(.top, 60)
                    Spacer()
                }
                .transition(.move(edge: .top))
                .animation(.easeInOut(duration: 0.3), value: locationManager.showLocationError)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                        locationManager.showLocationError = false
                    }
                }
            }
            if !bottomSheetExpanded {
                HStack {
                    Spacer()
                    VStack {
                        Spacer()
                        Button(action: {
                            showAddSignalement = true
                        }) {
                            Image(systemName: "plus")
                                .font(.system(size: 20, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 52, height: 52)
                                .background(Color(hex: "#4557A1"))
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                .shadow(color: Color.black.opacity(0.25), radius: 6, x: 0, y: 4)
                        }
                        .padding(.trailing, 20)
                        .padding(.bottom, 200)
                    }
                }
            }
        }
        .ignoresSafeArea(edges: .top)
        .navigationBarHidden(true)
        .sheet(isPresented: $showAddSignalement) {
            NewMeldingView()
        }
        .onChange(of: selectedTransit) { mode in
            realtimeMapViewModel.updateMode(mode)
        }
    }

    private var shapeSegments: [TransitShapeSegment] {
        realtimeMapViewModel.lineShapes.flatMap { shape in
            shape.segments.enumerated().map { index, segment in
                TransitShapeSegment(
                    id: "\(shape.id)-\(index)",
                    polyline: MKPolyline(coordinates: segment, count: segment.count),
                    transportType: shape.inferredTransport,
                    severity: shape.disruptionSeverity
                )
            }
        }
    }

    private var primaryDisruption: LineDisruption? {
        realtimeMapViewModel.disruptions
            .sorted { $0.severity.rawValue > $1.severity.rawValue }
            .first
    }

    private func selectSuggestion(_ suggestion: MKLocalSearchCompletion) {
        let address = suggestion.title
        if selectedField == .start {
            startingAddress = address
        } else if selectedField == .destination {
            destinationAddress = address
        }
        mapViewModel.searchLocation(address: address) { coord in
            if selectedField == .start {
                self.startCoordinate = coord
            } else if selectedField == .destination {
                self.destinationCoordinate = coord
            }
            if startingAddress != "" && destinationAddress != "" {
                rechercherTrajet()
            }
        }
    }

    private func rechercherTrajet() {
        guard let userLoc = locationManager.userLocation, !destinationAddress.isEmpty else {
            return
        }
        self.startCoordinate = userLoc

        mapViewModel.searchLocation(address: destinationAddress) { destCoord in
            guard let destCoord = destCoord else { return }
            self.destinationCoordinate = destCoord

            mapViewModel.getRoute(from: userLoc, to: destCoord) { foundRoute in
                if let foundRoute = foundRoute {
                    self.route = foundRoute
                    withAnimation {
                        cameraPosition = .region(MKCoordinateRegion(
                            center: userLoc,
                            span: MKCoordinateSpan(latitudeDelta: 0.02, longitudeDelta: 0.02)
                        ))
                    }
                }
            }
        }
    }
}

// MARK: - Vehicle Marker View (point animé sur la carte)

struct VehicleMarkerView: View {
    let vehicle: VehiclePosition
    @State private var pulse = false

    var body: some View {
        ZStack {
            // Halo animé
            Circle()
                .fill(Color(hex: vehicle.transportType.color).opacity(0.25))
                .frame(width: 28, height: 28)
                .scaleEffect(pulse ? 1.3 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: pulse)

            // Icone du véhicule
            ZStack {
                Circle()
                    .fill(Color(hex: vehicle.transportType.color))
                    .frame(width: 22, height: 22)
                    .shadow(color: Color(hex: vehicle.transportType.color).opacity(0.5), radius: 4, x: 0, y: 2)

                Image(systemName: vehicle.transportType.iconName)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
            }
            .rotationEffect(.degrees(vehicle.bearing))

            // Numéro de ligne
            Text(vehicle.line)
                .font(.system(size: 7, weight: .heavy))
                .foregroundColor(.white)
                .padding(.horizontal, 3)
                .padding(.vertical, 1)
                .background(Color.black.opacity(0.7))
                .clipShape(Capsule())
                .offset(y: -16)
        }
        .onAppear { pulse = true }
    }
}

// MARK: - Vehicle Info Bubble (popup quand on tap un véhicule)

struct VehicleInfoBubble: View {
    let vehicle: VehiclePosition
    let onDismiss: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle()
                    .fill(Color(hex: vehicle.transportType.color))
                    .frame(width: 40, height: 40)
                Image(systemName: vehicle.transportType.iconName)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("Ligne \(vehicle.line)")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundColor(.primary)
                if !vehicle.direction.isEmpty {
                    Text("→ \(vehicle.direction)")
                        .font(.system(size: 13))
                        .foregroundColor(.secondary)
                }
                Text("ID: \(vehicle.id)")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }

            Spacer()

            Button(action: onDismiss) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundColor(.secondary)
            }
        }
        .padding(16)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: .black.opacity(0.15), radius: 10, x: 0, y: 5)
        .padding(.horizontal, 16)
    }
}

private struct TransitShapeSegment: Identifiable {
    let id: String
    let polyline: MKPolyline
    let transportType: VehiclePosition.TransportType
    let severity: LineDisruption.Severity

    var strokeColor: Color {
        switch severity {
        case .high:
            return Color(hex: "#FF7B72").opacity(0.95)
        case .medium:
            return Color(hex: "#F4C97A").opacity(0.9)
        case .low:
            return Color(hex: transportType.color).opacity(0.72)
        }
    }

    var lineWidth: CGFloat {
        let baseWidth: CGFloat
        switch transportType {
        case .metro:
            baseWidth = 4
        case .tram:
            baseWidth = 3.5
        case .bus:
            baseWidth = 3
        }

        switch severity {
        case .high:
            return baseWidth + 1.5
        case .medium:
            return baseWidth + 0.8
        case .low:
            return baseWidth
        }
    }
}

struct WaitingTimeMarkerView: View {
    let stop: WaitingTimeStop

    var body: some View {
        VStack(spacing: 4) {
            HStack(spacing: 6) {
                Text(stop.line)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundColor(.white)
                Text("\(stop.minutes) min")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(.white.opacity(0.95))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                Capsule(style: .continuous)
                    .fill(Color.black.opacity(0.72))
                    .overlay(
                        Capsule(style: .continuous)
                            .stroke(Color(hex: "#B5CFF8").opacity(0.8), lineWidth: 1)
                    )
            )

            Circle()
                .fill(Color(hex: "#CADBFF"))
                .frame(width: 8, height: 8)
                .overlay(Circle().stroke(Color.white, lineWidth: 1.5))
        }
    }
}

struct DisruptionBanner: View {
    let disruption: LineDisruption

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(severityColor)
                .frame(width: 10, height: 10)

            VStack(alignment: .leading, spacing: 4) {
                Text(disruption.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                    .lineLimit(1)

                Text("Ligne \(disruption.line)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white.opacity(0.74))
            }

            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(.ultraThinMaterial.opacity(0.95))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(severityColor.opacity(0.7), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private var severityColor: Color {
        switch disruption.severity {
        case .high:
            return Color(hex: "#FF7B72")
        case .medium:
            return Color(hex: "#F4C97A")
        case .low:
            return Color(hex: "#8CCF9B")
        }
    }
}


struct PulsatingUserLocationView: View {
    @State private var pulse = false
    
    var body: some View {
        ZStack {
            // Cercle animé (effet pulse)
            Circle()
                .fill(Color.blue.opacity(0.2))
                .frame(width: 40, height: 40)
                .scaleEffect(pulse ? 1.4 : 1.0)
                .animation(
                    Animation.easeOut(duration: 1).repeatForever(autoreverses: true),
                    value: pulse
                )
            
            // Cercle central (position actuelle)
            // Cercle central (position actuelle)
            Circle()
                .fill(Color(hex: "#4557A1"))
                .frame(width: 16, height: 16)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 3)
                )
        }
        .onAppear {
            pulse = true
        }
    }
}
