//
//  MeldingenPerHalteView.swift
//  StibAlert
//
//  Created by studentehb on 12/05/2025.
//import SwiftUI
import SwiftUI
import MapKit

struct MeldingenPerHalteView: View {
    let halte: HalteModel
    let lijn: LijnModel
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var meldingVM = MeldingHalteViewModel()
    @State private var region: MKCoordinateRegion

    init(halte: HalteModel, lijn: LijnModel) {
        self.halte = halte
        self.lijn = lijn
        _region = State(initialValue: MKCoordinateRegion(
            center: CLLocationCoordinate2D(latitude: halte.latitude, longitude: halte.longitude),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        ))
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            VStack(spacing: 8) {
                // === HEADER BLANC ===
                HStack(alignment: .center, spacing: 12) {
                    Button(action: {
                        presentationMode.wrappedValue.dismiss() // ➜ action correcte
                    }) {
                        Image(systemName: "chevron.left")
                            .font(.title3)
                            .foregroundColor(.blue)
                    }

                    Text(lijn.lineid)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundColor(.white)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(LineColors.color(for: lijn.lineid))
                        .clipShape(Capsule())


                    VStack(alignment: .leading, spacing: 2) {
                        Text(halte.nom)
                            .font(.headline)
                            .lineLimit(1)
                        if let type = halte.typeTransport.first {
                            Text(abbrForTransport(type))
                                .font(.system(size: 12, weight: .bold))
                                .foregroundColor(.white)
                                .frame(width: 24, height: 24)
                                .background(LineColors.color(for: abbrForTransport(type)))
                                .clipShape(Circle())
                        }

                    }

                    Spacer()

                    HStack(spacing: 16) {
                        Image(systemName: "star")
                        Image(systemName: "bell")
                    }
                    .foregroundColor(.gray)
                    .font(.title3)
                }
                .padding(.horizontal)
                .padding(.top, 16)
                .ignoresSafeArea(.all, edges: .bottom)
                .padding(.bottom, 8)
                .background(Color.white)
                .shadow(color: .black.opacity(0.05), radius: 5, y: 2)

                // === MAP JUSTE EN DESSOUS ===
                Map(coordinateRegion: $region, annotationItems: [halte]) { stop in
                    MapAnnotation(coordinate: CLLocationCoordinate2D(latitude: stop.latitude, longitude: stop.longitude)) {
                        VStack(spacing: 4) {
                            Text(stop.nom)
                                .font(.caption).bold()

                            HStack(spacing: 4) {
                                ForEach(stop.lignesDesservies, id: \.self) { ligne in
                                    LineBadgeView(line: ligne)
                                }
                            }
                        }
                        .padding(6)
                        .background(Color.white)
                        .cornerRadius(10)
                        .shadow(radius: 2)
                    }
                }

                .edgesIgnoringSafeArea(.bottom)
            }

            // === DRAGGABLE SHEET ===
            if !meldingVM.signalements.isEmpty {
                DraggableSheetView(
                    signalements: meldingVM.signalements,
                    typeTransport: halte.typeTransport.first
                )
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            meldingVM.fetchMeldingen(voor: halte._id)
        }
    }

    func abbrForTransport(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "tram": return "T"
        case "bus": return "B"
        case "metro": return "M"
        default: return "?"
        }
    }
    
    
    
    struct LineBadgeView: View {
        let line: String

        var body: some View {
            Text(line)
                .font(.caption).bold()
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(LineColors.color(for: line))
                .clipShape(Circle())
                .overlay(Circle().stroke(Color.white, lineWidth: 2))
                .shadow(radius: 1) 
        }
    }


}

