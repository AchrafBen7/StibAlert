import SwiftUI
import CoreLocation

struct HomeStopSurfaceOverlay: View {
    let previewStop: TransportStopSummaryDTO?
    let detailStop: TransportStopSummaryDTO?
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let detailError: String?
    let userCoordinate: CLLocationCoordinate2D?
    let shouldShowStopPreview: Bool
    let shouldShowStopDetail: Bool
    let nearbyStops: (TransportStopSummaryDTO) -> [TransportStopSummaryDTO]
    let nearbyVilloStations: (TransportStopSummaryDTO) -> [(station: VilloStation, distanceMeters: Int)]
    let onDismiss: () -> Void
    let onOpenDetail: (TransportStopSummaryDTO) -> Void
    let onOpenLine: (String) -> Void
    let selectedLineRoute: String?
    let onSelectLineRoute: (String) -> Void
    let onOpenStop: (TransportStopSummaryDTO) -> Void
    let onSelectSiblingStop: (TransportStopSummaryDTO) -> Void
    let onReport: (TransportStopSummaryDTO) -> Void
    let onRetry: () -> Void

    var body: some View {
        ZStack {
            stopPreviewLayer
            stopDetailLayer
        }
    }

    @ViewBuilder
    private var stopPreviewLayer: some View {
        if shouldShowStopPreview, let stop = previewStop {
            HomeStopPreviewCard(
                stopSummary: stop,
                stopDetail: stopDetail,
                isLoading: isLoading,
                detailError: detailError,
                nearbyStops: nearbyStops(stop),
                nearbyVilloStations: nearbyVilloStations(stop),
                onDismiss: onDismiss,
                onOpenDetail: {
                    onOpenDetail(stop)
                },
                selectedLineRoute: selectedLineRoute,
                onSelectLineRoute: onSelectLineRoute,
                onSelectSiblingStop: onSelectSiblingStop,
                onRetry: onRetry
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zLayer(.stopPreview)
        }
    }

    @ViewBuilder
    private var stopDetailLayer: some View {
        if shouldShowStopDetail, let stop = detailStop {
            ArretDetailPage(
                stopSummary: stop,
                stopDetail: stopDetail,
                isLoading: isLoading,
                userCoordinate: userCoordinate,
                nearbyStops: nearbyStops(stop),
                nearbyVilloStations: nearbyVilloStations(stop),
                onDismiss: onDismiss,
                onOpenLine: onOpenLine,
                selectedLineRoute: selectedLineRoute,
                onSelectLineRoute: onSelectLineRoute,
                onOpenStop: onOpenStop,
                onReport: {
                    onReport(stop)
                }
            )
            .transition(.opacity.combined(with: .move(edge: .bottom)))
            .zLayer(.stopDetail)
        }
    }
}

extension String {
    var normalizedStopKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

struct HomeVilloStationSheet: View {
    @Environment(\.openURL) private var openURL
    let station: VilloStation

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                Capsule()
                    .fill(DS.Color.ink.opacity(0.22))
                    .frame(width: 42, height: 5)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)

                heroCard

                HStack(spacing: 10) {
                    villoMetricCard(
                        title: "Vélos",
                        value: "\(station.availableBikes)",
                        accent: DS.Color.villo,
                        subtitle: station.availableBikes == 1 ? "disponible" : "disponibles"
                    )
                    villoMetricCard(
                        title: "Places",
                        value: "\(station.availableBikeStands)",
                        accent: DS.Color.accent,
                        subtitle: station.availableBikeStands == 1 ? "libre" : "libres"
                    )
                }

                stationFactsCard

                if let lastUpdate = station.lastUpdate {
                    let date = Date(timeIntervalSince1970: TimeInterval(lastUpdate) / 1000)
                    Text("Mis à jour \(RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date()))")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.horizontal, 2)
                }
            }
            .padding(20)
        }
        .background(DS.Color.paper)
        .presentationBackground(DS.Color.paper)
    }

    private var heroCard: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 7) {
                    Text("VILLO! · STATION \(station.number)")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(DS.Color.inkMute)

                    Text(station.displayName)
                        .font(.system(size: 23, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(2)

                    Text(station.address)
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 12)

                VStack(alignment: .trailing, spacing: 10) {
                    Text(station.statusLabel)
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(station.isOperational ? statusAccent : DS.Color.paper)
                        .padding(.horizontal, 10)
                        .frame(height: 28)
                        .background(station.isOperational ? statusAccent.opacity(0.15) : statusAccent)
                        .overlay(
                            Capsule()
                                .stroke(station.isOperational ? statusAccent.opacity(0.35) : statusAccent, lineWidth: 1.4)
                        )
                        .clipShape(Capsule())

                    ZStack {
                        Circle()
                            .fill(statusAccent.opacity(0.12))
                            .frame(width: 54, height: 54)
                        Image(systemName: "bicycle")
                            .font(.system(size: 22, weight: .bold))
                            .foregroundStyle(statusAccent)
                    }
                }
            }

            HStack(alignment: .lastTextBaseline, spacing: 8) {
                Text("\(station.availableBikes) vélos")
                    .font(.system(size: 26, weight: .black, design: .rounded))
                    .foregroundStyle(DS.Color.ink)
                Text("·")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
                Text("\(station.availableBikeStands) places")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Color.inkSoft)
            }

            Button {
                openWalkingDirections()
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "figure.walk")
                        .font(.system(size: 15, weight: .bold))
                    Text("ITINÉRAIRE À PIED")
                    Spacer(minLength: 0)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 14, weight: .bold))
                }
                .font(DS.Font.mono.weight(.bold))
                .tracking(1.1)
                .foregroundStyle(DS.Color.paper)
                .padding(.horizontal, 16)
                .frame(height: 54)
                .background(DS.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(18)
        .background(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [
                            DS.Color.paper2.opacity(0.78),
                            DS.Color.paper
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.4)
        )
    }

    private var stationFactsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("STATION")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)

            HStack(spacing: 10) {
                factPill(icon: "dock.rectangle", label: "Capacité", value: "\(station.bikeStands)")
                factPill(icon: station.banking ? "creditcard.fill" : "xmark.circle", label: "Paiement", value: station.banking ? "CB" : "Sans CB")
                factPill(icon: "number.square", label: "Numéro", value: "\(station.number)")
            }
        }
        .padding(16)
        .background(DS.Color.paper2.opacity(0.38))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.1), lineWidth: 1.2)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private var statusAccent: Color {
        if !station.isOperational { return DS.Color.inkMute }
        if station.availableBikes == 0 { return DS.Color.statusMajor }
        if station.availableBikeStands == 0 { return DS.Color.accent }
        if station.availableBikes <= 3 { return DS.Color.statusMinor }
        return DS.Color.villo
    }

    private func openWalkingDirections() {
        let latitude = station.coordinate.latitude
        let longitude = station.coordinate.longitude
        guard let url = URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)&dirflg=w") else { return }
        openURL(url)
    }

    private func villoMetricCard(title: String, value: String, accent: Color, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title)
                .font(DS.Font.monoSmall.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.1)
                .foregroundStyle(DS.Color.inkMute)

            Text(value)
                .font(.system(size: 31, weight: .black, design: .rounded))
                .foregroundStyle(DS.Color.ink)

            Text(subtitle)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.inkSoft)

            Capsule()
                .fill(accent.opacity(0.88))
                .frame(width: 42, height: 6)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1.4)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
    }

    private func factPill(icon: String, label: String, value: String) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle()
                    .fill(DS.Color.paper)
                    .frame(width: 34, height: 34)
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(label.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.1)
                    .foregroundStyle(DS.Color.inkMute)
                Text(value)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HomeStopPreviewCard: View {
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let detailError: String?
    let nearbyStops: [TransportStopSummaryDTO]
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let onDismiss: () -> Void
    let onOpenDetail: () -> Void
    let selectedLineRoute: String?
    let onSelectLineRoute: (String) -> Void
    let onSelectSiblingStop: (TransportStopSummaryDTO) -> Void
    let onRetry: () -> Void

    private var siblingStops: [TransportStopSummaryDTO] {
        let originLat = effectiveStop.latitude
        let originLng = effectiveStop.longitude
        guard let originLat, let originLng else { return [] }
        let origin = CLLocation(latitude: originLat, longitude: originLng)
        return nearbyStops
            .filter { stop in
                guard let lat = stop.latitude, let lng = stop.longitude else { return false }
                return origin.distance(from: CLLocation(latitude: lat, longitude: lng)) <= 90
            }
            .prefix(4)
            .map { $0 }
    }

    private func distanceMeters(to stop: TransportStopSummaryDTO) -> Int? {
        guard
            let lat = stop.latitude, let lng = stop.longitude,
            let originLat = effectiveStop.latitude, let originLng = effectiveStop.longitude
        else { return nil }
        let dist = CLLocation(latitude: originLat, longitude: originLng)
            .distance(from: CLLocation(latitude: lat, longitude: lng))
        return Int(dist.rounded())
    }

    private var effectiveStop: TransportStopSummaryDTO {
        stopDetail?.stop ?? stopSummary
    }

    private var displayedLines: [String] {
        var seen = Set<String>()
        // Realtime departures are the ground truth for this specific physical stop.
        // Arret.lignesDesservies in the backend is the UNION of lines across merged
        // sub-stops with the same name, so it shows lines that don't actually pass here.
        // Only fall back to catalog lines when no departures are available yet.
        let departureLines = stopDetail?.nextDepartures.map(\.line) ?? []
        let source = departureLines.isEmpty ? effectiveStop.lines : departureLines
        return source.compactMap { line in
            let normalized = Self.normalizedLineNumber(line)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .sorted { left, right in
            if let leftInt = Int(left), let rightInt = Int(right) { return leftInt < rightInt }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private struct DepartureGroup: Identifiable {
        let id: String
        let line: String
        let destination: String?
        let primary: TransportDepartureDTO
        let secondary: TransportDepartureDTO?
    }

    private var departureGroups: [DepartureGroup] {
        // Show the next 2 departures per (line, destination) so users see both
        // directions of every line, not just the soonest few across the whole stop.
        let all = (stopDetail?.nextDepartures ?? [])
            .sorted { $0.minutes < $1.minutes }
        var buckets: [String: [TransportDepartureDTO]] = [:]
        var order: [String] = []
        for dep in all {
            let key = "\(dep.line)|\(dep.destination ?? "")"
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append(dep)
        }
        return order.compactMap { key in
            guard let arr = buckets[key], let first = arr.first else { return nil }
            return DepartureGroup(
                id: key,
                line: first.line,
                destination: first.destination,
                primary: first,
                secondary: arr.dropFirst().first
            )
        }
    }

    private var villoSummary: String? {
        guard !nearbyVilloStations.isEmpty else { return nil }
        let bikes = nearbyVilloStations.reduce(0) { $0 + $1.station.availableBikes }
        let label = nearbyVilloStations.count == 1 ? "1 Villo! à proximité" : "\(nearbyVilloStations.count) Villo! à proximité"
        return "\(label) · \(bikes) vélos"
    }

    private static func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    var body: some View {
        VStack {
            Spacer()

            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 14) {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("ARRÊT" + (effectiveStop.stopId.map { " · \($0)" } ?? ""))
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)

                        Text(effectiveStop.name)
                            .font(DS.Font.displayH2)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(2)

                        if !displayedLines.isEmpty {
                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 6) {
                                    ForEach(displayedLines, id: \.self) { line in
                                        Button {
                                            onSelectLineRoute(line)
                                        } label: {
                                            LineBadge(line: line, size: .sm)
                                                .overlay(
                                                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                                        .stroke(selectedLineRoute == line ? DS.Color.ink : Color.clear, lineWidth: 2)
                                                )
                                        }
                                        .buttonStyle(.plain)
                                    }
                                }
                            }
                            .padding(.top, 2)
                        }
                    }

                    Spacer(minLength: 12)

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 18, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 44, height: 44)
                            .background(DS.Color.paper)
                            .overlay(
                                Circle()
                                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
                            )
                    }
                    .buttonStyle(.plain)
                }
                .padding(.horizontal, 18)
                .padding(.top, 18)
                .padding(.bottom, 18)

                Rectangle()
                    .fill(DS.Color.ink.opacity(0.12))
                    .frame(height: 1)

                VStack(alignment: .leading, spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute)
                        Text("PROCHAINS PASSAGES")
                            .font(DS.Font.mono.weight(.bold))
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)
                    }

                    if isLoading {
                        Text("Chargement des prochains passages…")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    } else if detailError != nil {
                        HStack(spacing: 10) {
                            Text("Impossible de charger les passages.")
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.inkMute)
                            Spacer()
                            Button(action: onRetry) {
                                Label("Réessayer", systemImage: "arrow.clockwise")
                                    .font(.system(size: 13, weight: .medium))
                                    .foregroundStyle(DS.Color.primary)
                            }
                            .buttonStyle(.plain)
                        }
                    } else if departureGroups.isEmpty {
                        Text("Aucun passage prévu pour le moment.")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkMute)
                    } else {
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(spacing: 10) {
                                ForEach(departureGroups) { group in
                                    HStack(spacing: 12) {
                                        LineBadge(line: group.line, size: .sm)
                                        Text("→ \(group.destination ?? "Direction en cours")")
                                            .font(.system(size: 15, weight: .medium))
                                            .foregroundStyle(DS.Color.ink)
                                            .frame(maxWidth: .infinity, alignment: .leading)
                                            .lineLimit(1)

                                        VStack(alignment: .trailing, spacing: 2) {
                                            Text(group.primary.minutes <= 0 ? "Imminent" : "\(group.primary.minutes) min")
                                                .font(DS.Font.displayH3)
                                                .foregroundStyle(DS.Color.ink)
                                            if let secondary = group.secondary {
                                                Text("puis \(secondary.minutes) min")
                                                    .font(DS.Font.monoSmall.weight(.bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(DS.Color.inkMute)
                                            } else if let delay = group.primary.delayMinutes, delay > 2 {
                                                Text("+\(delay) min")
                                                    .font(DS.Font.monoSmall.weight(.bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(DS.Color.statusMajor)
                                            } else if group.primary.source == "scheduled" {
                                                Text("théorique")
                                                    .font(DS.Font.monoSmall.weight(.bold))
                                                    .tracking(0.8)
                                                    .foregroundStyle(DS.Color.inkMute)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        .frame(maxHeight: 220)
                    }

                    if let villoSummary {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.12))
                            .frame(height: 1)

                        Label(villoSummary, systemImage: "bicycle")
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkSoft)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.vertical, 16)

                if !siblingStops.isEmpty {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.12))
                        .frame(height: 1)

                    VStack(alignment: .leading, spacing: 10) {
                        HStack(spacing: 8) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 14, weight: .medium))
                                .foregroundStyle(DS.Color.inkMute)
                            Text("AUTRES QUAIS ICI")
                                .font(DS.Font.mono.weight(.bold))
                                .tracking(2)
                                .foregroundStyle(DS.Color.inkMute)
                        }

                        VStack(spacing: 6) {
                            ForEach(siblingStops) { stop in
                                Button {
                                    onSelectSiblingStop(stop)
                                } label: {
                                    HStack(spacing: 10) {
                                        Image(systemName: "arrow.triangle.swap")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DS.Color.inkMute)
                                            .frame(width: 18)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(stop.name)
                                                .font(.system(size: 14, weight: .semibold))
                                                .foregroundStyle(DS.Color.ink)
                                                .lineLimit(1)
                                            if let dist = distanceMeters(to: stop) {
                                                Text("\(dist) m · ARRÊT \(stop.stopId ?? stop.id)")
                                                    .font(DS.Font.monoSmall)
                                                    .foregroundStyle(DS.Color.inkMute)
                                            }
                                        }
                                        .frame(maxWidth: .infinity, alignment: .leading)

                                        Image(systemName: "chevron.right")
                                            .font(.system(size: 11, weight: .semibold))
                                            .foregroundStyle(DS.Color.inkMute)
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 8)
                                    .background(DS.Color.ink.opacity(0.04))
                                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                }

                Button(action: onOpenDetail) {
                    HStack {
                        Text("VOIR L'ARRÊT EN DÉTAIL")
                        Spacer()
                        Image(systemName: "chevron.right")
                    }
                    .font(DS.Font.mono.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 18)
                    .frame(height: 60)
                    .frame(maxWidth: .infinity)
                    .background(DS.Color.primary)
                }
                .buttonStyle(.plain)
            }
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .shadow(color: DS.Color.ink.opacity(0.16), radius: 18, y: 10)
            .frame(maxHeight: UIScreen.main.bounds.height * 0.72)
            .padding(.horizontal, 16)
            .padding(.bottom, 130)
        }
    }
}
