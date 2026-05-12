import SwiftUI

struct VehicleTrackVisualizer: View {
    let liveLine: LiveLineDTO

    @State private var animatedProgress: Double = 0
    @State private var pulse = false

    private var visibleStops: [LiveLineStop] {
        let userIdx = liveLine.stops.firstIndex(where: \.isUserStop) ?? liveLine.stops.count / 2

        let earliestVehicleIdx = liveLine.vehicles
            .compactMap { $0.stopIndex }
            .min()
            .map { Int($0.rounded(.down)) } ?? userIdx

        let lowerBound = max(0, min(earliestVehicleIdx, userIdx) - 1)
        let upperBound = min(liveLine.stops.count - 1, userIdx + 1)

        let bounded = max(2, upperBound - lowerBound + 1)
        let targetMax = min(liveLine.stops.count - 1, lowerBound + min(7, bounded))
        let clamped = Array(liveLine.stops[lowerBound...max(lowerBound, targetMax)])
        return clamped
    }

    private var firstVisibleOrder: Int {
        visibleStops.first?.order ?? 0
    }

    private var lastVisibleOrder: Int {
        visibleStops.last?.order ?? 0
    }

    private var orderRange: Double {
        max(1.0, Double(lastVisibleOrder - firstVisibleOrder))
    }

    private var primaryVehicle: LiveLineVehicle? {
        liveLine.vehicles
            .filter { $0.stopIndex != nil }
            .min(by: { ($0.stopsAway ?? Double.infinity) < ($1.stopsAway ?? Double.infinity) })
    }

    private var lineColor: Color {
        if let hex = liveLine.couleur, !hex.isEmpty {
            return Color(hex: hex.hasPrefix("#") ? hex : "#\(hex)")
        }
        return DS.Color.primary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            header
            trackView
            footerStats
        }
        .padding(16)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(lineColor.opacity(0.25), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .onAppear {
            withAnimation(.easeOut(duration: 0.9)) {
                animatedProgress = 1
            }
            withAnimation(.easeInOut(duration: 1.2).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 10) {
            LineBadge(line: liveLine.lineId, size: .sm)
            VStack(alignment: .leading, spacing: 2) {
                Text("EN DIRECT")
                    .font(DS.Font.monoSmall.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(lineColor)
                Text(headlineText)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
            }
            Spacer()
            if let fetchedAt = liveLine.fetchedAt {
                Text(fetchedAt, style: .relative)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
    }

    private var headlineText: String {
        if let dest = liveLine.destination, !dest.isEmpty {
            return "→ \(dest.capitalized)"
        }
        if let dir = liveLine.direction {
            return "→ \(dir)"
        }
        return "Position temps réel"
    }

    // MARK: - Track

    private var trackView: some View {
        GeometryReader { geo in
            let trackHeight: CGFloat = 50
            let trackY = trackHeight / 2
            let leftPad: CGFloat = 12
            let rightPad: CGFloat = 12
            let usableWidth = max(20, geo.size.width - leftPad - rightPad)

            ZStack(alignment: .topLeading) {
                // Base line
                RoundedRectangle(cornerRadius: 3, style: .continuous)
                    .fill(DS.Color.ink.opacity(0.18))
                    .frame(width: usableWidth, height: 4)
                    .offset(x: leftPad, y: trackY - 2)

                // Animated progress segment (vehicle-side)
                if let vehicle = primaryVehicle, let stopIndex = vehicle.stopIndex {
                    let vehicleX = leftPad + xForStopIndex(stopIndex, usableWidth: usableWidth)
                    let userStopX: CGFloat = liveLine.userStopOrder != nil
                        ? leftPad + xForStopOrder(Double(liveLine.userStopOrder!), usableWidth: usableWidth)
                        : geo.size.width
                    let segmentX = min(vehicleX, userStopX)
                    let segmentWidth = max(0, abs(userStopX - vehicleX)) * animatedProgress

                    LinearGradient(
                        colors: [lineColor.opacity(0.85), lineColor.opacity(0.45)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: segmentWidth, height: 4)
                    .clipShape(RoundedRectangle(cornerRadius: 3))
                    .offset(x: segmentX, y: trackY - 2)
                }

                // Stops
                ForEach(visibleStops) { stop in
                    let stopX = leftPad + xForStopOrder(Double(stop.order), usableWidth: usableWidth)
                    stopDot(for: stop)
                        .offset(x: stopX - 6, y: trackY - 6)
                }

                // Vehicle marker
                if let vehicle = primaryVehicle, let stopIndex = vehicle.stopIndex {
                    let vehicleX = leftPad + xForStopIndex(stopIndex, usableWidth: usableWidth)
                    vehicleDot
                        .offset(x: vehicleX - 14, y: trackY - 14)
                }

                // Stop labels (only show user stop + nearest vehicle)
                ForEach(visibleStops) { stop in
                    let stopX = leftPad + xForStopOrder(Double(stop.order), usableWidth: usableWidth)
                    if stop.isUserStop || stopShouldShowLabel(stop) {
                        Text(stop.name)
                            .font(DS.Font.monoSmall.weight(stop.isUserStop ? .heavy : .regular))
                            .foregroundStyle(stop.isUserStop ? DS.Color.ink : DS.Color.inkMute)
                            .lineLimit(1)
                            .frame(width: 72)
                            .offset(x: stopX - 36, y: trackY + 12)
                    }
                }
            }
        }
        .frame(height: 80)
    }

    private func xForStopOrder(_ order: Double, usableWidth: CGFloat) -> CGFloat {
        let normalized = (order - Double(firstVisibleOrder)) / orderRange
        return CGFloat(max(0, min(1, normalized))) * usableWidth
    }

    private func xForStopIndex(_ index: Double, usableWidth: CGFloat) -> CGFloat {
        let stopOrder = orderForStopIndex(index)
        return xForStopOrder(stopOrder, usableWidth: usableWidth)
    }

    private func orderForStopIndex(_ index: Double) -> Double {
        let allStops = liveLine.stops
        guard !allStops.isEmpty else { return Double(firstVisibleOrder) }
        let lower = Int(index.rounded(.down))
        let upper = lower + 1
        if lower < 0 { return Double(allStops.first?.order ?? firstVisibleOrder) }
        if upper >= allStops.count { return Double(allStops.last?.order ?? lastVisibleOrder) }
        let lowerOrder = Double(allStops[lower].order)
        let upperOrder = Double(allStops[upper].order)
        let frac = index - Double(lower)
        return lowerOrder + (upperOrder - lowerOrder) * frac
    }

    private func stopDot(for stop: LiveLineStop) -> some View {
        let isUser = stop.isUserStop
        let size: CGFloat = isUser ? 14 : 10
        return ZStack {
            if isUser && pulse {
                Circle()
                    .fill(lineColor.opacity(0.25))
                    .frame(width: 26, height: 26)
                    .scaleEffect(pulse ? 1.0 : 0.8)
            }
            Circle()
                .fill(isUser ? lineColor : DS.Color.paper)
                .frame(width: size, height: size)
                .overlay(
                    Circle()
                        .stroke(isUser ? lineColor : DS.Color.ink.opacity(0.4), lineWidth: 2)
                )
        }
        .frame(width: 12, height: 12)
    }

    private var vehicleDot: some View {
        ZStack {
            Circle()
                .fill(lineColor.opacity(0.18))
                .frame(width: 36, height: 36)
                .scaleEffect(pulse ? 1.0 : 0.85)

            Circle()
                .fill(DS.Color.ink)
                .frame(width: 26, height: 26)
                .overlay(
                    Circle()
                        .stroke(lineColor, lineWidth: 2.5)
                )

            Image(systemName: vehicleIcon)
                .font(.system(size: 12, weight: .heavy))
                .foregroundStyle(lineColor)
        }
        .frame(width: 36, height: 36)
    }

    private var vehicleIcon: String {
        switch (liveLine.typeTransport ?? "").lowercased() {
        case "métro", "metro": return "tram.fill"
        case "tram": return "tram.fill"
        case "bus": return "bus.fill"
        default: return "tram.fill"
        }
    }

    private func stopShouldShowLabel(_ stop: LiveLineStop) -> Bool {
        guard let vehicle = primaryVehicle, let nearest = vehicle.nearestStopIndex else { return false }
        let allStops = liveLine.stops
        guard nearest >= 0, nearest < allStops.count else { return false }
        return allStops[nearest].order == stop.order
    }

    // MARK: - Footer stats

    private var footerStats: some View {
        HStack(spacing: 12) {
            if let primary = primaryVehicle {
                statBlock(
                    label: stopsAwayLabel(for: primary),
                    value: stopsAwayValue(for: primary)
                )
            }
            if let eta = liveLine.etaAtUserStop?.minutes {
                statBlock(
                    label: "ETA",
                    value: "\(eta) min"
                )
            }
            if let delay = liveLine.etaAtUserStop?.delayMinutes, delay > 0 {
                statBlock(
                    label: "Retard",
                    value: "+\(delay) min",
                    emphasized: true
                )
            }
            Spacer()
        }
    }

    private func stopsAwayLabel(for vehicle: LiveLineVehicle) -> String {
        guard let stopsAway = vehicle.stopsAway else { return "Position" }
        if stopsAway < 0.5 { return "À l'arrêt" }
        if stopsAway < 1.5 { return "Prochain arrêt" }
        return "Arrêts restants"
    }

    private func stopsAwayValue(for vehicle: LiveLineVehicle) -> String {
        guard let stopsAway = vehicle.stopsAway else { return "—" }
        if stopsAway < 0.5 { return "→ ici" }
        let n = Int(stopsAway.rounded())
        return "\(n)"
    }

    private func statBlock(label: String, value: String, emphasized: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.2)
                .foregroundStyle(DS.Color.inkMute)
            Text(value)
                .font(DS.Font.displayH3)
                .foregroundStyle(emphasized ? Color(hex: "#E94E1B") : DS.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
