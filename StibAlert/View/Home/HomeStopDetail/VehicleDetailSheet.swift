import SwiftUI

/// Bottom sheet shown when the user taps a moving tram/bus pin on the map.
/// Tells them which stop the vehicle is at right now and which direction
/// it's heading, so they can recognise their own tram in the queue without
/// leaving focus mode.
struct VehicleDetailSheet: View {
    let vehicle: TransportVehicleDTO
    /// Direction → human-readable destination, derived from the active stop's
    /// `nextDepartures`. Empty when the stop hasn't loaded yet.
    let destinationByDirection: [String: String]
    let onClose: () -> Void

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    private var lineForegroundColor: Color {
        guard let line = vehicle.line else { return .white }
        return TransitLinePalette.foreground(for: line)
    }

    private var mode: TransitLineMode {
        TransitLineMode.mode(for: vehicle.line)
    }

    private var destinationLabel: String? {
        // Vraie destination résolue côté backend (STIB directionId → nom du
        // terminus) : la source de vérité. Le cache heuristique
        // direction→terminus ne sert plus que de repli pour un véhicule dont
        // le terminus n'a pas pu être résolu.
        if let destination = vehicle.destination,
           !destination.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return destination.capitalized
        }
        guard let direction = vehicle.direction,
              let mapped = destinationByDirection[direction]
        else { return nil }
        return mapped.capitalized
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            headerRow
                .padding(.horizontal, 18)
                .padding(.top, 14)
                .padding(.bottom, 12)

            divider

            VStack(spacing: 10) {
                infoRow(
                    icon: "mappin.and.ellipse",
                    label: "Arrêt actuel",
                    value: vehicle.stopNom?.capitalized ?? "—"
                )
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 14)
        }
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(DS.Shadow.overlay)
        .padding(.horizontal, 16)
    }

    private var headerRow: some View {
        HStack(alignment: .center, spacing: 14) {
            ZStack {
                Circle()
                    .fill(lineColor)
                    .shadow(color: lineColor.opacity(0.45), radius: 8, x: 0, y: 3)
                Image(systemName: mode.sfSymbol)
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(lineForegroundColor)
            }
            .frame(width: 52, height: 52)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mode.label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(DS.Color.inkMute)
                    Text("·")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                    Text("LIGNE \(vehicle.line ?? "?")")
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                        .foregroundStyle(DS.Color.inkMute)
                }
                if let destinationLabel {
                    Text(destinationLabel)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.85)
                } else {
                    Text("En circulation")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 32, height: 32)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
    }

    private var divider: some View {
        Rectangle()
            .fill(DS.Color.ink.opacity(0.08))
            .frame(height: 1)
    }

    private func infoRow(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(lineColor)
                .frame(width: 22, height: 22)
                .background(
                    Circle()
                        .fill(lineColor.opacity(0.12))
                )
            Text(label)
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
            Text(value)
                .font(.system(size: 14, weight: .semibold, design: .rounded))
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
        }
    }
}
