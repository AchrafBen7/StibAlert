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
            Map(coordinateRegion: $region)
                .edgesIgnoringSafeArea(.all)
            
            VStack(spacing: 0) {
                ZStack(alignment: .top) {
                    Color.white
                        .edgesIgnoringSafeArea(.top)
                        .frame(height: 170) // ✅ Réduit pour moins d'espace blanc
                    
                    VStack(spacing: 12) {
                        TextField("Adresse de départ", text: $startingAddress)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                        
                        TextField("Destination", text: $destinationAddress)
                            .padding()
                            .background(Color.white)
                            .cornerRadius(12)
                            .overlay(
                                RoundedRectangle(cornerRadius: 12)
                                    .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                            )
                            .padding(.horizontal, 24)
                    }
                    .padding(.top, 15) // ✅ moins d’espace sous la notch
                    
                    // Bouton entre les champs MAIS aligné à droite
                    VStack {
                        Spacer().frame(height: 55) // Ajuste pour qu’il tombe bien entre les champs
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
                            .padding(.trailing, 45) // ✅ Aligne à droite
                        }
                    }
                }
                
                Spacer()
            }
            .frame(maxWidth: .infinity, alignment: .top)
            .zIndex(1)
            
            DraggableBottomSheet(selectedTransit: $selectedTransit, isExpanded: $bottomSheetExpanded)
            
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




struct TransitMapView_Previews: PreviewProvider {
    static var previews: some View {
        TransitMapView()
    }
}
