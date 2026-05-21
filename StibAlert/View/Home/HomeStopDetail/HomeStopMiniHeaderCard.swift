import SwiftUI
import CoreLocation

/// Compact stop "chip header" shown in place of the search bar when the user
/// taps a stop pin on the map. Lets them swap the focused line without
/// opening the full preview card — the map keeps the line-focus dim treatment
/// so they can watch live vehicles on the chosen tracé.
struct HomeStopMiniHeaderCard: View {
    let stop: TransportStopSummaryDTO
    let selectedLine: String?
    let nextDepartures: [TransportDepartureDTO]
    let isLoading: Bool
    let liveVehicleCount: Int
    let liveVehicles: [TransportVehicleDTO]
    let onClose: () -> Void
    let onSelectLine: (String) -> Void
    let onFollowVehicle: (TransportVehicleDTO) -> Void
    let onShowDetail: () -> Void

    /// Vehicle currently at or closest to the focused stop. Used to anchor
    /// the abstract "now / 2 min" pills to a real, named position on the
    /// line so the user can reconcile the live GPS markers with the
    /// scheduled departures.
    private var closestVehicle: TransportVehicleDTO? {
        guard let stopLat = stop.latitude, let stopLng = stop.longitude else { return nil }
        let user = CLLocation(latitude: stopLat, longitude: stopLng)
        return liveVehicles
            .compactMap { v -> (TransportVehicleDTO, Double)? in
                guard let lat = v.latitude, let lng = v.longitude else { return nil }
                let d = user.distance(from: CLLocation(latitude: lat, longitude: lng))
                return (v, d)
            }
            .min(by: { $0.1 < $1.1 })?
            .0
    }

    private var isVehicleAtStop: Bool {
        guard let closestVehicle, let stopName = closestVehicle.stopNom else { return false }
        return stopName.uppercased() == stop.name.uppercased()
    }

    private var displayedLines: [String] {
        // De-duplicate while preserving order; the API sometimes ships the
        // same line under both metro and tram catalogs.
        var seen = Set<String>()
        return stop.lines.filter { line in
            let key = line.trimmingCharacters(in: .whitespaces).uppercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private var lineDepartures: [TransportDepartureDTO] {
        guard let selectedLine else { return [] }
        let normalized = normalize(selectedLine)
        return nextDepartures
            .filter { normalize($0.line) == normalized }
            .prefix(6)
            .map { $0 }
    }

    /// Departures grouped by destination so the user can see at a glance
    /// which trams go which way. Preserves backend order within each group.
    private var departuresByDestination: [(destination: String, items: [TransportDepartureDTO])] {
        var order: [String] = []
        var bucket: [String: [TransportDepartureDTO]] = [:]
        for departure in lineDepartures {
            let key = (departure.destination?.uppercased()).flatMap { $0.isEmpty ? nil : $0 } ?? "—"
            if bucket[key] == nil {
                order.append(key)
            }
            bucket[key, default: []].append(departure)
        }
        return order.map { ($0, bucket[$0] ?? []) }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onShowDetail()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text("ARRÊT")
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(DS.Color.inkMute)
                            if selectedLine != nil {
                                liveCountBadge
                            }
                        }
                        Text(stop.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre les détails complets de l'arrêt")

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
                .accessibilityLabel("Fermer le détail")
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(displayedLines, id: \.self) { line in
                        lineChip(line)
                    }
                }
            }

            departuresRow

            if let closestVehicle, selectedLine != nil {
                closestVehicleRow(closestVehicle)
            }

            detailButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.Color.paper.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
        .shadow(DS.Shadow.overlay)
    }

    @ViewBuilder
    private var departuresRow: some View {
        if isLoading && lineDepartures.isEmpty {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text("Chargement des prochains passages…")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
        } else if lineDepartures.isEmpty {
            Text("Aucun passage prévu")
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
        } else {
            VStack(alignment: .leading, spacing: 6) {
                ForEach(departuresByDestination, id: \.destination) { group in
                    directionRow(destination: group.destination, items: Array(group.items.prefix(3)))
                }
            }
        }
    }

    private func directionRow(destination: String, items: [TransportDepartureDTO]) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 4) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 9, weight: .bold))
                Text(destination)
                    .font(.system(size: 10, weight: .bold))
                    .tracking(0.5)
                    .lineLimit(1)
            }
            .foregroundStyle(DS.Color.inkMute)
            .frame(minWidth: 90, alignment: .leading)

            ForEach(Array(items.enumerated()), id: \.offset) { _, departure in
                departurePill(departure)
            }
            Spacer(minLength: 0)
        }
    }

    private func departurePill(_ departure: TransportDepartureDTO) -> some View {
        let isRealtime = departure.source == "realtime"
        return HStack(spacing: 3) {
            if isRealtime {
                Circle()
                    .fill(DS.Color.statusOK)
                    .frame(width: 5, height: 5)
            }
            Text(minutesText(for: departure.minutes))
                .font(.system(size: 12, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.Color.ink)
        }
        .padding(.horizontal, 7)
        .frame(height: 22)
        .background(DS.Color.paper2.opacity(0.7))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(DS.Color.ink.opacity(0.10), lineWidth: 1))
    }

    private func minutesText(for minutes: Int) -> String {
        if minutes <= 0 { return "now" }
        return "\(minutes) min"
    }

    private func closestVehicleRow(_ vehicle: TransportVehicleDTO) -> some View {
        let mode = TransitLineMode.mode(for: vehicle.line)
        let stopText = vehicle.stopNom?.capitalized ?? "—"
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onFollowVehicle(vehicle)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: mode.sfSymbol)
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(isVehicleAtStop ? DS.Color.statusOK : DS.Color.inkMute)
                if isVehicleAtStop {
                    Text("Un \(mode.label.lowercased()) est à l'arrêt")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(DS.Color.statusOK)
                } else {
                    Text("Plus proche")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Color.inkMute)
                    Text("·")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                    Text(stopText)
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                Image(systemName: "scope")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.top, 2)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Centrer la carte sur le tram à \(stopText)")
    }

    /// Full-width row at the bottom that opens the standalone ArretDetailPage
    /// — the user wanted a clear path to the full detail screen (community
    /// reports, official disruptions, lines & destinations) from the mini
    /// card without losing the live focus context.
    private var detailButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onShowDetail()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("Voir l'arrêt en détail")
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(DS.Color.paper2.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var liveCountBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(liveVehicleCount > 0 ? DS.Color.statusOK : DS.Color.statusMinor)
                .frame(width: 5, height: 5)
            Text("\(liveVehicleCount) live")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(.horizontal, 6)
        .frame(height: 14)
        .background(DS.Color.paper2.opacity(0.6))
        .clipShape(Capsule())
    }

    private func lineChip(_ line: String) -> some View {
        let isSelected = selectedLine.map(normalize) == normalize(line)
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onSelectLine(line)
        } label: {
            LineBadge(line: line, size: .sm)
                .padding(2)
                .background(
                    Circle().stroke(
                        isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.0),
                        lineWidth: 2
                    )
                )
                .opacity(isSelected || selectedLine == nil ? 1 : 0.5)
        }
        .buttonStyle(.plain)
    }

    private func normalize(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces).uppercased()
    }
}
