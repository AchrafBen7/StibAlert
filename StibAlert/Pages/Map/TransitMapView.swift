//
//  TransitMapView.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//
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
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @StateObject private var locationManager = LocationManager()
    @State private var selectedTransit: TransitMode = .bus
    @State private var bottomSheetExpanded: Bool = false
    @StateObject private var lijnenVM = LijnenViewModel()
    @StateObject private var mapViewModel = MapViewModel()
    @State private var route: MKRoute? = nil
    @State private var startCoordinate: CLLocationCoordinate2D? = nil
    @State private var destinationCoordinate: CLLocationCoordinate2D? = nil
    @State private var showAddSignalement = false
    @State private var isHovering = false
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
            // Marqueurs classiques (départ/destination)
            Map(coordinateRegion: $region, annotationItems: annotations + userAnnotation) { item in
                MapAnnotation(coordinate: item.coordinate) {
                    if item.isUser {
                        PulsatingUserLocationView()
                    } else {
                        Circle()
                            .fill(item.isStart ? Color.green : Color.red)
                            .frame(width: 20, height: 20)
                            .overlay(Circle().stroke(Color.white, lineWidth: 2))
                    }
                }
            }
            .overlay(routeOverlay, alignment: .center)
            VStack {
                HStack {
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
                }
                .padding(.top, 60)
                .padding(.leading, 16)
                
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            
            
            .onReceive(locationManager.$userLocation) { newLocation in
                if let newLocation = newLocation {
                    withAnimation {
                        region = MKCoordinateRegion(
                            center: newLocation,
                            span: MKCoordinateSpan(latitudeDelta: 0.01, longitudeDelta: 0.01)
                        )
                    }
                }
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
            }
            
            
            if locationManager.showLocationError {
                VStack {
                    Text("Erreur de localisation. Activez la position.")
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
        
    }
    
    private var annotations: [AnnotationItem] {
        var items: [AnnotationItem] = []
        if let start = startCoordinate {
            items.append(AnnotationItem(coordinate: start, isStart: true))
        }
        if let dest = destinationCoordinate {
            items.append(AnnotationItem(coordinate: dest, isStart: false))
        }
        return items
    }
    
    private var userAnnotation: [AnnotationItem] {
        if let userLoc = locationManager.userLocation {
            return [AnnotationItem(coordinate: userLoc, isStart: false, isUser: true)]
        } else {
            return []
        }
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
                    self.region.center = userLoc
                }
            }
        }
    }
    
    private var routeOverlay: some View {
        GeometryReader { geo in
            if let route = route {
                Path { path in
                    let points = route.polyline.points()
                    let pointCount = route.polyline.pointCount
                    
                    if pointCount > 0 {
                        let firstPoint = points[0]
                        let start = CGPoint(
                            x: geo.size.width * CGFloat((firstPoint.coordinate.longitude - region.center.longitude) / region.span.longitudeDelta + 0.5),
                            y: geo.size.height * CGFloat((firstPoint.coordinate.latitude - region.center.latitude) / -region.span.latitudeDelta + 0.5)
                        )
                        path.move(to: start)
                        
                        for i in 1..<pointCount {
                            let nextPoint = points[i]
                            let next = CGPoint(
                                x: geo.size.width * CGFloat((nextPoint.coordinate.longitude - region.center.longitude) / region.span.longitudeDelta + 0.5),
                                y: geo.size.height * CGFloat((nextPoint.coordinate.latitude - region.center.latitude) / -region.span.latitudeDelta + 0.5)
                            )
                            path.addLine(to: next)
                        }
                    }
                }
                .stroke(Color(hex: "#F18F5D"), lineWidth: 4) // Orange STIB
            }
        }
    }
}

struct AnnotationItem: Identifiable {
    let id = UUID()
    var coordinate: CLLocationCoordinate2D
    var isStart: Bool
    var isUser: Bool = false
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
