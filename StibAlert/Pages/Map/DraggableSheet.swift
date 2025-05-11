//
//  DraggableSheet.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//
import SwiftUI
import MapKit

struct DraggableBottomSheet: View {
    var onSubmitSearch: () -> Void
    @Binding var destinationAddress: String
    var searchResults: [MKLocalSearchCompletion]
    var onSelectSuggestion: (MKLocalSearchCompletion) -> Void
    @State private var homeLocation: String? = nil
    @State private var workLocation: String? = nil
    @Binding var selectedTransit: TransitMapView.TransitMode
    @Binding var isExpanded: Bool
    @ObservedObject var lijnenVM: LijnenViewModel

    private let collapsedHeight: CGFloat = 180

    private var filteredLijnen: [LijnModel] {
        lijnenVM.lijnen.filter { line in
            let transportType = line.typeTransport.lowercased()
            switch selectedTransit {
            case .bus:
                return transportType.contains("bus")
            case .metro:
                return transportType.contains("metro") || ["1", "2", "5", "6"].contains(line.lineid)
            case .tram:
                return transportType.contains("tram")
            }
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Barre de drag
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 6)
                .padding(.top, 8)
                .padding(.bottom, 4)

            // Barre de recherche
            destinationSearchSection

            // Boutons maison/travail
            VStack(spacing: 10) {
                shortcutButton(
                    icon: "house.fill",
                    label: "Maison",
                    value: homeLocation,
                    action: { homeLocation = "Rue de la Paix 10" }
                )
                shortcutButton(
                    icon: "briefcase.fill",
                    label: "Travail",
                    value: workLocation,
                    action: { workLocation = "Avenue Louise 234" }
                )
            }
            .padding(.horizontal)

            // Boutons de transport
            HStack(spacing: 16) {
                ForEach(TransitMapView.TransitMode.allCases) { mode in
                    let isSelected = (mode == selectedTransit)
                    Button {
                        selectedTransit = mode
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: iconName(for: mode))
                                .font(.system(size: 16, weight: .semibold))
                            Text(mode.rawValue.capitalized)
                                .font(.system(size: 14, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#4557A1"))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .frame(maxWidth: .infinity)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color(hex: "#F18F5D").opacity(0.37) : Color(hex: "#FAFAFD"))
                        )
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 8)

            if isExpanded {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(filteredLijnen) { line in
                            HStack(spacing: 12) {
                                Text(line.lineid)
                                    .font(.system(size: 18, weight: .bold))
                                    .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(LineColors.color(for: line.lineid))
                                    .cornerRadius(10)

                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.nomComplet)
                                        .font(.subheadline)
                                    if let retour = line.nomCompletRetour {
                                        Text(retour)
                                            .font(.caption)
                                            .foregroundColor(.gray)
                                    }
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .foregroundColor(.orange)
                            }
                            .padding(.horizontal)
                            .padding(.vertical, 6)
                        }
                    }
                    .padding(.bottom, 16)
                }
                .frame(maxHeight: 300)

                if lijnenVM.lijnen.isEmpty {
                    Text("Aucune ligne disponible.")
                        .foregroundColor(.gray)
                        .padding()
                }

                if let error = lijnenVM.errorMessage {
                    Text(error)
                        .foregroundColor(.red)
                        .padding()
                }
            } else {
                Spacer().frame(height: 16)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: isExpanded ? 320 : collapsedHeight, alignment: .top)
        .background(Color.white)
        .clipShape(TopCornersRoundedShape(radius: 16))
        .shadow(radius: 1)
        .animation(.easeInOut, value: isExpanded)
        .gesture(
            DragGesture()
                .onEnded { value in
                    withAnimation {
                        isExpanded = value.translation.height < -40
                    }
                }
        )
        .onChange(of: NetworkMonitor.shared.isConnected) { connected in
            if connected {
                lijnenVM.fetchLijnen()
            }
        }
    }

    private var destinationSearchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Où allons-nous ?", text: $destinationAddress)
                .padding()
                .background(Color.white)
                .cornerRadius(12)
                .overlay(RoundedRectangle(cornerRadius: 12).stroke(Color.gray.opacity(0.3), lineWidth: 1))
                .padding(.horizontal)
                .onSubmit {
                    onSubmitSearch()
                }

            if !searchResults.isEmpty {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(searchResults, id: \.self) { result in
                            Button(action: {
                                onSelectSuggestion(result)
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
                .padding(.horizontal)
                .frame(maxHeight: 200)
            }
        }
    }

    private func iconName(for mode: TransitMapView.TransitMode) -> String {
        switch mode {
        case .bus:
            return "bus"
        case .metro, .tram:
            return "tram.fill"
        }
    }

    private func shortcutButton(icon: String, label: String, value: String?, action: @escaping () -> Void) -> some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(.white)
                .frame(width: 24, height: 24)
                .background(Color(hex: "#4557A1"))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(label)
                    .font(.subheadline)
                if let value = value {
                    Text(value)
                        .font(.caption)
                        .foregroundColor(.gray)
                }
            }

            Spacer()

            Button(action: action) {
                Text(value == nil ? "Définir" : "Modifier")
                    .font(.footnote)
                    .foregroundColor(Color(hex: "#F18F5D"))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.white)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(Color(hex: "#F18F5D").opacity(0.5), lineWidth: 1)
                    )
                    .cornerRadius(8)
            }
        }
        .padding()
        .background(Color(hex: "#F2F6FB"))
        .cornerRadius(12)
    }
}
struct TopCornersRoundedShape: Shape {
    var radius: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()

        // Coin inférieur gauche
        path.move(to: CGPoint(x: 0, y: rect.height))
        path.addLine(to: CGPoint(x: 0, y: radius))

        // Coin supérieur gauche arrondi
        path.addQuadCurve(to: CGPoint(x: radius, y: 0),
                          control: CGPoint(x: 0, y: 0))

        // Ligne droite vers coin supérieur droit
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))

        // Coin supérieur droit arrondi
        path.addQuadCurve(to: CGPoint(x: rect.width, y: radius),
                          control: CGPoint(x: rect.width, y: 0))

        // Ligne droite jusqu'en bas à droite
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))

        // Fermer le chemin
        path.closeSubpath()
        return path
    }
}
