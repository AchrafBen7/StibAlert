import SwiftUI

struct VehicleMarker: View {
    let vehicle: TransportVehicleDTO

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    private var lineTextColor: Color {
        guard let line = vehicle.line else { return .white }
        return TransitLinePalette.foreground(for: line)
    }

    private var modeIcon: String {
        guard let line = vehicle.line else { return "bus.fill" }
        let n = Int(line) ?? 0
        if n >= 1 && n <= 6 { return "tram.tunnel.fill" }
        if n >= 7 && n <= 99 { return "tram.fill" }
        return "bus.fill"
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(lineColor.opacity(0.18))
                .frame(width: 38, height: 38)

            Circle()
                .fill(lineColor)
                .frame(width: 26, height: 26)
                .shadow(color: lineColor.opacity(0.45), radius: 4, x: 0, y: 2)

            if let line = vehicle.line {
                Text(line)
                    .font(.system(size: line.count > 2 ? 8 : 10, weight: .black, design: .rounded))
                    .foregroundStyle(lineTextColor)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            } else {
                Image(systemName: modeIcon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(.white)
            }
        }
        .frame(width: 38, height: 38)
    }
}
