import SwiftUI

/// Véhicule temps réel sur la carte, dessiné comme un VRAI véhicule vu du
/// dessus (façon De Lijn) et orienté dans son sens de marche, au lieu d'une
/// pastille ronde générique. La silhouette change selon le mode : un tram/métro
/// est long et rectangulaire, un bus plus court et arrondi.
struct VehicleMarker: View {
    let vehicle: TransportVehicleDTO
    var bearing: Double? = nil

    private var mode: TransitLineMode { TransitLineMode.mode(for: vehicle.line) }

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    /// Dimensions de la caisse, en points. Un tram est nettement plus long
    /// qu'un bus : c'est ce qui rend les deux reconnaissables d'un coup d'œil,
    /// même sans lire l'icône.
    private var body_size: CGSize {
        switch mode {
        case .metro: return CGSize(width: 15, height: 34)
        case .tram:  return CGSize(width: 14, height: 32)
        case .bus:   return CGSize(width: 14, height: 25)
        }
    }

    var body: some View {
        ZStack {
            // Halo pulsé : signale que le véhicule est VIVANT (temps réel) et
            // le distingue des pins d'arrêt statiques de la même couleur.
            PulsingHalo(color: lineColor)
                .frame(width: 52, height: 52)

            vehicleBody
                // Le cap oriente la caisse : le véhicule "regarde" là où il va.
                // Sans cap connu, on le laisse droit plutôt que d'inventer une
                // direction (un sens faux est pire que pas de sens).
                .rotationEffect(.degrees(bearing ?? 0))
                .animation(.easeInOut(duration: 0.45), value: bearing)
        }
        .frame(width: 52, height: 52)
        .accessibilityElement()
        .accessibilityLabel(AppLocalizer.format("a11y.vehicle_line", defaultValue: "Véhicule ligne %@", vehicle.line ?? "?"))
    }

    /// Caisse blanche cerclée de la couleur de la ligne, avec pare-brise et
    /// feux — les repères qui font lire « véhicule » plutôt que « pastille ».
    private var vehicleBody: some View {
        let size = body_size
        let radius: CGFloat = mode == .bus ? 5 : 4

        return ZStack {
            // Ombre portée : décolle le véhicule du fond de carte.
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.black.opacity(0.22))
                .frame(width: size.width, height: size.height)
                .offset(y: 1.5)
                .blur(radius: 1.5)

            // Caisse
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .fill(Color.white)
                .frame(width: size.width, height: size.height)
                .overlay(
                    RoundedRectangle(cornerRadius: radius, style: .continuous)
                        .stroke(lineColor, lineWidth: 2)
                )

            VStack(spacing: 0) {
                // Pare-brise avant (vers l'avant du véhicule = haut)
                RoundedRectangle(cornerRadius: 1.5, style: .continuous)
                    .fill(lineColor.opacity(0.85))
                    .frame(width: size.width - 6, height: 4)
                    .padding(.top, 2.5)

                Spacer(minLength: 0)

                // Bande arrière (feux) : donne l'avant/arrière au premier coup d'œil
                RoundedRectangle(cornerRadius: 1, style: .continuous)
                    .fill(lineColor.opacity(0.5))
                    .frame(width: size.width - 8, height: 2.5)
                    .padding(.bottom, 2.5)
            }
            .frame(width: size.width, height: size.height)

            // Pointe de direction : petite flèche à l'avant, hors de la caisse.
            if bearing != nil {
                Image(systemName: "triangle.fill")
                    .font(.system(size: 7, weight: .black))
                    .foregroundStyle(lineColor)
                    .offset(y: -(size.height / 2) - 4)
            }
        }
        .frame(width: size.width, height: size.height)
    }
}

private struct PulsingHalo: View {
    let color: Color
    @State private var scale: CGFloat = 0.6
    @State private var opacity: Double = 0.55

    var body: some View {
        Circle()
            .fill(color.opacity(opacity))
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                    scale = 1.1
                    opacity = 0
                }
            }
    }
}
