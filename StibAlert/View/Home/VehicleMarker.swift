import SwiftUI

struct VehicleMarker: View {
    let vehicle: TransportVehicleDTO
    var bearing: Double? = nil

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    private var lineTextColor: Color {
        guard let line = vehicle.line else { return .white }
        return TransitLinePalette.foreground(for: line)
    }

    private var modeIcon: String {
        TransitLineMode.mode(for: vehicle.line).sfSymbol
    }

    var body: some View {
        ZStack {
            // Pulsing halo so a live vehicle reads as "moving" even when
            // the map is still — it's the visual cue separating it from
            // the static stop pins which use the same line color.
            PulsingHalo(color: lineColor)
                .frame(width: 48, height: 48)

            // Bearing arrow points where the vehicle is heading.
            if let bearing {
                Image(systemName: "arrowtriangle.up.fill")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(lineColor)
                    .offset(y: -19)
                    .rotationEffect(.degrees(bearing))
            }

            // Single circular badge with just the transit-mode icon. We drop
            // the line number text — in focus mode the user already knows
            // which line they're watching, and the chip below clutters the
            // map when several vehicles cluster together.
            Image(systemName: modeIcon)
                .font(.system(size: 14, weight: .black))
                .foregroundStyle(lineTextColor)
                .frame(width: 30, height: 30)
                .background(
                    Circle()
                        .fill(lineColor)
                        .shadow(color: lineColor.opacity(0.55), radius: 6, x: 0, y: 2)
                )
                .overlay(
                    Circle()
                        .stroke(DS.Color.paper, lineWidth: 2.5)
                )
        }
        .frame(width: 48, height: 48)
        .accessibilityElement()
        .accessibilityLabel("Véhicule ligne \(vehicle.line ?? "?")")
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
