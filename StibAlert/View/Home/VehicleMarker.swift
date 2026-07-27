import SwiftUI

/// Véhicule temps réel sur la carte, dans l'esprit De Lijn : une PETITE caisse
/// blanche étroite, cerclée d'un trait fin sombre, posée dans un HALO doux à la
/// couleur de la ligne.
///
/// Trois essais ont été nécessaires pour arriver là, et la leçon vaut d'être
/// écrite :
///  1. une caisse blanche large avec vitres et rétroviseurs → se lisait comme
///     un TÉLÉPHONE (rectangle arrondi de ce format = écran) ;
///  2. une caisse pleine avec pictogramme par-dessus → lisible, mais l'effet
///     « temps réel » avait disparu ;
///  3. la bonne réponse : ce n'est pas le DÉTAIL du véhicule qui fait l'effet,
///     c'est sa PETITESSE + le halo lumineux. Un véhicule doit être discret sur
///     la carte ; c'est la lueur qui attire l'œil et dit « ça bouge, là,
///     maintenant ».
///
/// Le repère coloré à l'avant donne le sens de marche sans flèche ajoutée.
struct VehicleMarker: View {
    let vehicle: TransportVehicleDTO
    var bearing: Double? = nil

    private var mode: TransitLineMode { TransitLineMode.mode(for: vehicle.line) }

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    /// Petit et ÉTROIT — c'est ce qui empêche la lecture « téléphone » et donne
    /// la silhouette d'un véhicule vu du dessus. Le bus est plus court.
    private var size: CGSize {
        switch mode {
        case .metro: return CGSize(width: 9, height: 22)
        case .tram:  return CGSize(width: 9, height: 21)
        case .bus:   return CGSize(width: 9, height: 17)
        }
    }

    var body: some View {
        ZStack {
            glow
            chassis
                // Sans cap connu, la caisse reste droite : un sens inventé
                // serait pire que pas de sens.
                .rotationEffect(.degrees(bearing ?? 0))
                .animation(.easeInOut(duration: 0.45), value: bearing)
        }
        .frame(width: 46, height: 46)
        .accessibilityElement()
        .accessibilityLabel(AppLocalizer.format("a11y.vehicle_line", defaultValue: "Véhicule ligne %@", vehicle.line ?? "?"))
    }

    /// Halo doux : trois cercles concentriques flous, pas une pastille nette.
    /// C'est LUI l'effet « temps réel » — il respire lentement pour montrer que
    /// la donnée est vivante, sans agiter la carte.
    private var glow: some View {
        ZStack {
            Circle().fill(lineColor.opacity(0.16)).frame(width: 40, height: 40).blur(radius: 7)
            Circle().fill(lineColor.opacity(0.26)).frame(width: 28, height: 28).blur(radius: 5)
            Circle().fill(lineColor.opacity(0.38)).frame(width: 19, height: 19).blur(radius: 3)
        }
        .modifier(BreathingGlow())
    }

    private var chassis: some View {
        let w = size.width
        let h = size.height

        return ZStack {
            RoundedRectangle(cornerRadius: 3, style: .continuous)
                .fill(Color.white)
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: 3, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.85), lineWidth: 0.9)
                )
                .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 1)

            // Repère avant à la couleur de la ligne = avant du véhicule.
            RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                .fill(lineColor)
                .frame(width: w - 3, height: 3)
                .offset(y: -h / 2 + 3.2)
        }
        .frame(width: w, height: h)
    }
}

/// Respiration lente du halo (1,8 s) : signale une donnée vivante sans créer
/// l'agitation d'une animation rapide quand plusieurs véhicules sont visibles.
private struct BreathingGlow: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.12 : 0.92)
            .opacity(pulse ? 1 : 0.75)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
