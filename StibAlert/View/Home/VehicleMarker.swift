import SwiftUI

/// Véhicule temps réel sur la carte.
///
/// Deux couches superposées, et c'est volontaire :
///  • la CAISSE (colorée, allongée, nez blanc) **tourne** selon le cap → elle
///    dit où va le véhicule ;
///  • le PICTOGRAMME du mode (tram / bus / métro) **ne tourne pas** → il reste
///    lisible à l'endroit et dit ce que c'est.
///
/// Une silhouette seule ne suffit pas : à 30 px, un rectangle arrondi se lit
/// comme un téléphone, quels que soient les détails ajoutés (vitres,
/// rétroviseurs…). C'est le pictogramme qui lève l'ambiguïté ; la forme et le
/// nez donnent le sens de marche.
struct VehicleMarker: View {
    let vehicle: TransportVehicleDTO
    var bearing: Double? = nil

    private var mode: TransitLineMode { TransitLineMode.mode(for: vehicle.line) }

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    private var lineTextColor: Color {
        guard let line = vehicle.line else { return .white }
        return TransitLinePalette.foreground(for: line)
    }

    /// Un tram/métro est long, un bus plus trapu.
    private var size: CGSize {
        switch mode {
        case .metro: return CGSize(width: 22, height: 32)
        case .tram:  return CGSize(width: 22, height: 31)
        case .bus:   return CGSize(width: 21, height: 26)
        }
    }

    var body: some View {
        ZStack {
            PulsingHalo(color: lineColor)
                .frame(width: 54, height: 54)

            // Caisse orientée
            chassis
                .rotationEffect(.degrees(bearing ?? 0))
                .animation(.easeInOut(duration: 0.45), value: bearing)

            // Pictogramme TOUJOURS à l'endroit, même quand la caisse pivote.
            Image(systemName: mode.sfSymbol)
                .font(.system(size: 12, weight: .black))
                .foregroundStyle(lineTextColor)
                .shadow(color: lineColor.opacity(0.9), radius: 1)
        }
        .frame(width: 54, height: 54)
        .accessibilityElement()
        .accessibilityLabel(AppLocalizer.format("a11y.vehicle_line", defaultValue: "Véhicule ligne %@", vehicle.line ?? "?"))
    }

    private var chassis: some View {
        let w = size.width
        let h = size.height

        return ZStack {
            RoundedRectangle(cornerRadius: w * 0.34, style: .continuous)
                .fill(Color.black.opacity(0.25))
                .frame(width: w, height: h)
                .offset(y: 1.5)
                .blur(radius: 1.5)

            RoundedRectangle(cornerRadius: w * 0.34, style: .continuous)
                .fill(lineColor)
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: w * 0.34, style: .continuous)
                        .stroke(Color.white, lineWidth: 2)
                )

            // Nez blanc : marque l'avant sans dépendre d'une flèche externe.
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(Color.white)
                .frame(width: w * 0.5, height: 3.5)
                .offset(y: -h * 0.32)
        }
        .frame(width: w, height: h)
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
