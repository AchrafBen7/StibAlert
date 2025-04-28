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
    @State private var startingAddress: String = ""
    @State private var destinationAddress: String = ""
    @State private var selectedField: FieldType? = nil
    
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var selectedTransit: TransitMode = .bus
    @State private var bottomSheetExpanded: Bool = false
    @StateObject private var lijnenVM = LijnenViewModel()
    @StateObject private var mapViewModel = MapViewModel()
    @State private var route: MKRoute? = nil
    @State private var startCoordinate: CLLocationCoordinate2D? = nil
    @State private var destinationCoordinate: CLLocationCoordinate2D? = nil
    
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
            Map(coordinateRegion: $region, annotationItems: annotations) { item in
                MapMarker(coordinate: item.coordinate, tint: item.isStart ? .green : .red)
            }
            .overlay(routeOverlay, alignment: .center)
            
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Color.white
                        .edgesIgnoringSafeArea(.top)
                        .frame(height: 170)
                    
                    VStack(spacing: 12) {
                        TextField("Adresse de départ", text: $startingAddress, onEditingChanged: { editing in
                            if editing {
                                selectedField = .start
                            }
                        })
                        .onChange(of: startingAddress) { newValue in
                            mapViewModel.updateSearch(queryFragment: newValue)
                        }
                        .onSubmit {
                            selectedField = .start
                            rechercherTrajet()
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 24)
                        .onChange(of: startingAddress) { newValue in
                            mapViewModel.updateSearch(queryFragment: newValue)
                        }
                        
                        TextField("Destination", text: $destinationAddress, onEditingChanged: { editing in
                            if editing {
                                selectedField = .destination
                            }
                        })
                        .onChange(of: destinationAddress) { newValue in
                            mapViewModel.updateSearch(queryFragment: newValue)
                        }
                        .onSubmit {
                            selectedField = .destination
                            rechercherTrajet()
                        }
                        
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                        .padding(.horizontal, 24)
                        .onChange(of: destinationAddress) { newValue in
                            mapViewModel.updateSearch(queryFragment: newValue)
                        }
                    }
                    .padding(.top, 15)
                    
                    VStack {
                        Spacer().frame(height: 55)
                        HStack {
                            Spacer()
                            Button(action: {
                                swap(&startingAddress, &destinationAddress)
                            }) {
                                Image(systemName: "arrow.up.arrow.down")
                                    .rotationEffect(.degrees(180))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(Color(hex: "#4557A1"))
                                    .cornerRadius(12)
                            }
                            .padding(.trailing, 45)
                        }
                    }
                }
                
                if !mapViewModel.searchResults.isEmpty {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(mapViewModel.searchResults, id: \.self) { result in
                                Button(action: {
                                    selectSuggestion(result)
                                }) {
                                    Text(result.title)
                                        .foregroundColor(.black)
                                        .padding()
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(Color.white)
                                }
                                .background(
                                    Rectangle()
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 0.5)
                                )
                            }
                        }
                    }
                    .background(Color.white)
                    .cornerRadius(8)
                    .padding(.horizontal, 24)
                    .frame(maxHeight: 200)
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .zIndex(1)
            
            DraggableBottomSheet(
                selectedTransit: $selectedTransit,
                isExpanded: $bottomSheetExpanded,
                lijnenVM: lijnenVM
            )
            .onAppear {
                lijnenVM.fetchLijnen()
            }
            
            FloatingLocationButton(region: $region, bottomSheetExpanded: bottomSheetExpanded)
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
        guard !startingAddress.isEmpty, !destinationAddress.isEmpty else {
            return
        }
        
        mapViewModel.searchLocation(address: startingAddress) { startCoord in
            guard let startCoord = startCoord else { return }
            self.startCoordinate = startCoord
            
            mapViewModel.searchLocation(address: destinationAddress) { destCoord in
                guard let destCoord = destCoord else { return }
                self.destinationCoordinate = destCoord
                
                mapViewModel.getRoute(from: startCoord, to: destCoord) { foundRoute in
                    if let foundRoute = foundRoute {
                        self.route = foundRoute
                        self.region.center = startCoord
                    }
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
}
 
 
fileprivate struct FloatingLocationButton: View {
    @Binding var region: MKCoordinateRegion
    let bottomSheetExpanded: Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                if !bottomSheetExpanded {
                    Button(action: {
                        region.center = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
                    }) {
                        Image(systemName: "dot.circle") // icône de localisation
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .frame(width: 20, height: 20)
                            .foregroundColor(.white)
                            .padding(14)
                            .background(Color(hex: "#4557A1")) // couleur bleue STIB
                            .cornerRadius(12) // pour avoir un rectangle arrondi
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 90)
                }
            }
        }
    }
}
