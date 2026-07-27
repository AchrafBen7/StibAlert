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
        // Terminus RÉEL résolu côté backend (`directionId` → nom de l'arrêt
        // final, via le même index statique que les positions) : exposé dans
        // `vehicle.destination`. C'est la vraie direction, plus une devinette.
        if let dest = vehicle.destination?.trimmingCharacters(in: .whitespacesAndNewlines),
           !dest.isEmpty {
            return dest.capitalized
        }
        // Repli : cache heuristique appris via les départs de l'arrêt ; sinon
        // header neutre et direction concrète donnée par le prochain arrêt.
        guard let direction = vehicle.direction,
              let mapped = destinationByDirection[direction]
        else { return nil }
        return mapped.capitalized
    }

    /// Le `stopNom` du véhicule est le pointId STIB vers lequel il roule :
    /// `distanceFromPoint > 0` ⇒ il s'en approche (prochain arrêt), `0` ⇒ il y
    /// est. Donne une indication de direction fiable, sans dépendre du terminus.
    private var isHeadingToStop: Bool {
        (vehicle.distanceFromPoint ?? 0) > 0
    }

    /// « Buissonnets · à 250 m ».
    ///
    /// On affiche la DISTANCE, pas un temps d'arrivée. La STIB ne fournit
    /// aucune ETA pour un véhicule : la déduire d'une vitesse moyenne
    /// reviendrait à inventer un « 2 min » qui se trompe dès le premier feu
    /// rouge — exactement le faux temps réel qu'on s'interdit. La distance,
    /// elle, est une donnée réelle et répond à « il est où ? ».
    private var nextStopValue: String {
        let stop = vehicle.stopNom?.capitalized ?? "—"
        guard isHeadingToStop, let metres = vehicle.distanceFromPoint, metres > 0 else {
            return stop
        }
        let distance = metres >= 1000
            ? String(format: "%.1f km", Double(metres) / 1000)
            : "\(metres) m"
        return "\(stop) · \(AppLocalizer.format("vehicle.at_distance", defaultValue: "à %@", distance))"
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
                    icon: isHeadingToStop ? "arrow.right.circle" : "mappin.and.ellipse",
                    label: isHeadingToStop
                        ? AppLocalizer.string("vehicle.next_stop", defaultValue: "Prochain arrêt")
                        : AppLocalizer.string("vehicle.current_stop", defaultValue: "Arrêt actuel"),
                    value: nextStopValue
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

    /// En-tête : le NUMÉRO DE LIGNE domine.
    ///
    /// Avant, un gros rond coloré portait l'icône du mode : on lisait « tram »
    /// avant « ligne 7 », alors que le voyageur cherche d'abord son numéro. Et
    /// la couleur forte représentait le mode, pas la ligne — lien impossible à
    /// faire. Désormais c'est le badge de ligne (même composant que partout
    /// ailleurs dans l'app), donc la couleur EST celle de la ligne.
    private var headerRow: some View {
        HStack(alignment: .center, spacing: 12) {
            LineBadge(line: vehicle.line ?? "?", size: .lg)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(mode.label.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                    Text("·")
                        .font(.system(size: 9, weight: .bold))
                    Text(AppLocalizer.string("vehicle.running", defaultValue: "EN CIRCULATION"))
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.2)
                }
                .foregroundStyle(DS.Color.inkMute)

                if let destinationLabel {
                    // « Vers Heysel » plutôt que « Direction Heysel » : plus
                    // court, plus naturel à lire, et ça dit la même chose.
                    Text(AppLocalizer.format("vehicle.towards", defaultValue: "Vers %@", destinationLabel))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.75)
                } else {
                    Text(AppLocalizer.string("vehicle.in_service", defaultValue: "En circulation"))
                        .font(.system(size: 19, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            // Croix volontairement DISCRÈTE : elle attirait presque autant
            // l'œil que l'information principale.
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(width: 26, height: 26)
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalizer.string("Fermer", defaultValue: "Fermer"))
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
