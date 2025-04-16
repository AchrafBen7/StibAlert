//
//  DraggableSheet.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//
import SwiftUI

struct DraggableBottomSheet: View {
    @Binding var selectedTransit: TransitMapView.TransitMode
    @Binding var isExpanded: Bool
    
    let dummyLines: [String] = ["Ligne 1", "Ligne 2", "Ligne 3", "Ligne 4"]
    
    // Hauteur fermée fixée exactement à 60 pt (pour être identique au tab bar)
    private let collapsedHeight: CGFloat = 60
    
    var body: some View {
        VStack(spacing: 0) {
            // Barre de drag en haut
            Capsule()
                .fill(Color.gray.opacity(0.4))
                .frame(width: 40, height: 6)
                .padding(.top, 8)
                .padding(.bottom, 4)
            
            // Barre de transport (les 3 boutons)
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
            
            // Lorsque la feuille est réduite, nous ne voulons pas d'espace visible sous les boutons.
            // On n'ajoute donc pas de Spacer dans la version fermée.
            if isExpanded {
                Divider()
                ScrollView {
                    VStack(alignment: .leading, spacing: 10) {
                        ForEach(dummyLines, id: \.self) { line in
                            Text("\(selectedTransit.rawValue.capitalized) \(line)")
                                .padding(.horizontal)
                                .padding(.vertical, 8)
                                .background(Color.gray.opacity(0.1))
                                .cornerRadius(8)
                        }
                    }
                    .padding()
                }
                .frame(maxHeight: 300)
            }
        }
        .frame(maxWidth: .infinity)
        // La hauteur totale est exactement collapsedHeight (60) quand la sheet est fermée
        .frame(height: isExpanded ? nil : collapsedHeight, alignment: .top)
        .background(Color.white)
        // Appliquer une forme qui arrondit UNIQUEMENT les coins supérieurs,
        // laissant ainsi le bord inférieur parfaitement rectiligne pour qu'il "fusionne" avec le tab bar.
        .clipShape(TopCornersRoundedShape(radius: 16))
        .shadow(radius: 1) // Réduisez ou supprimez l'ombre si nécessaire
        .animation(.easeInOut, value: isExpanded)
        .gesture(
            DragGesture()
                .onEnded { value in
                    if value.translation.height < -50 {
                        withAnimation { isExpanded = true }
                    } else if value.translation.height > 50 {
                        withAnimation { isExpanded = false }
                    }
                }
        )
    }
    
    private func iconName(for mode: TransitMapView.TransitMode) -> String {
        switch mode {
        case .bus:
            return "bus"
        case .metro, .tram:
            return "tram.fill"
        }
    }
}

/// Shape qui arrondit seulement les coins supérieurs et laisse le bas rectiligne.
struct TopCornersRoundedShape: Shape {
    var radius: CGFloat
    
    func path(in rect: CGRect) -> Path {
        var path = Path()
        
        // Démarrer en bas à gauche (coin inférieur gauche reste rectiligne)
        path.move(to: CGPoint(x: 0, y: rect.height))
        // Monter verticalement vers le coin supérieur gauche (arrondi)
        path.addLine(to: CGPoint(x: 0, y: radius))
        // Arc pour le coin supérieur gauche
        path.addQuadCurve(to: CGPoint(x: radius, y: 0),
                          control: CGPoint(x: 0, y: 0))
        // Ligne droite vers le coin supérieur droit
        path.addLine(to: CGPoint(x: rect.width - radius, y: 0))
        // Arc pour le coin supérieur droit
        path.addQuadCurve(to: CGPoint(x: rect.width, y: radius),
                          control: CGPoint(x: rect.width, y: 0))
        // Descendre en ligne droite vers le coin inférieur droit (rectiligne)
        path.addLine(to: CGPoint(x: rect.width, y: rect.height))
        // Fermer le chemin
        path.closeSubpath()
        return path
    }
}

