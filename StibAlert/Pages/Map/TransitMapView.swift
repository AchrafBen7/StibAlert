//
//  TransitMapView.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//
import SwiftUI
import MapKit

struct TransitMapView: View {
    @State private var startingAddress: String = "Ma position actuelle"
    @State private var destinationAddress: String = ""
    @State private var region = MKCoordinateRegion(
        center: CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
        span: MKCoordinateSpan(latitudeDelta: 0.05, longitudeDelta: 0.05)
    )
    @State private var selectedTransit: TransitMode = .bus
    @State private var bottomSheetExpanded: Bool = false
    
    enum TransitMode: String, CaseIterable, Identifiable {
        case bus, metro, tram
        var id: String { self.rawValue }
    }
    
    var body: some View {
        ZStack(alignment: .bottom) {
            // 1) Carte en arrière-plan
            Map(coordinateRegion: $region)
                .edgesIgnoringSafeArea(.all)
            
            // 2) Champs d'adresses en haut
            VStack {
                HStack(spacing: 12) {
                    TextField("Adresse de départ", text: $startingAddress)
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                    
                    Button {
                        swap(&startingAddress, &destinationAddress)
                    } label: {
                        Image(systemName: "arrow.up.arrow.down")
                            .foregroundColor(.white)
                            .padding(10)
                            .background(Color("DarkBlue", bundle: nil))
                            .cornerRadius(8)
                    }
                    
                    TextField("Destination", text: $destinationAddress)
                        .padding(10)
                        .background(Color.white)
                        .cornerRadius(8)
                }
                .padding()
                
                Spacer()
            }
            .edgesIgnoringSafeArea(.top)
            
            // 3) Bottom sheet positionnée en bas sans padding additionnel (pour qu’elle soit collée au tab bar)
            DraggableBottomSheet(selectedTransit: $selectedTransit, isExpanded: $bottomSheetExpanded)
            
            // 4) Bouton flottant pour recentrer la carte
            FloatingLocationButton(region: $region, bottomSheetExpanded: bottomSheetExpanded)
        }
    }
}

fileprivate struct FloatingLocationButton: View {
    @Binding var region: MKCoordinateRegion
    let bottomSheetExpanded: Bool
    
    var body: some View {
        VStack {
            Spacer()
            HStack {
                Spacer()
                // Le bouton ne s’affiche que si la bottom sheet N’EST PAS étendue
                if !bottomSheetExpanded {
                    Button(action: {
                        region.center = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
                    }) {
                        Image(systemName: "location.fill")
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.blue)
                            .clipShape(Circle())
                    }
                    .padding(.trailing, 20)
                    .padding(.bottom, 80)
                    // Optional: vous pouvez ajouter une animation sur le if pour un effet de fade.
                }
            }
        }
    }
}



struct TransitMapView_Previews: PreviewProvider {
    static var previews: some View {
        TransitMapView()
    }
}
