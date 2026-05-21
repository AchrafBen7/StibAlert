import MapKit
import SwiftUI

struct HomeRouteOption: Identifiable {
    let id = UUID()
    let route: MKRoute?
    let backendAlternative: TransportAlternativeDTO?
    let originName: String
    let destinationName: String
    let durationText: String
    let transitSummary: String
    let walkingSummary: String
    let reliabilityText: String

    static func from(
        route: MKRoute?,
        index: Int,
        originName: String,
        destinationName: String,
        backendAlternative: TransportAlternativeDTO? = nil
    ) -> HomeRouteOption {
        let transitSteps = route?.steps.filter { $0.transportType == .transit } ?? []
        let walkingDistance = route?.steps.filter { $0.transportType == .walking }.map(\.distance).reduce(0, +) ?? 0
        let walkingMinutes = max(1, Int((walkingDistance / 75).rounded()))
        let transferCount = max(0, transitSteps.count - 1)
        let durationMinutes = backendAlternative?.totalDurationMinutes ?? max(1, Int((((route?.expectedTravelTime) ?? 60) / 60).rounded()))
        let transitSummary = backendAlternative.map(Self.transitSummary(from:)) ?? (transitSteps.isEmpty ? "à pied" : "\(transitSteps.count) transport")
        let walkingSummary = "\(backendAlternative?.walkingMinutes ?? walkingMinutes) min à pied"
        let reliabilityText = backendAlternative.map(Self.reliabilitySummary(from:)) ?? (transferCount == 0 ? "direct" : "\(transferCount) corresp.")

        return HomeRouteOption(
            route: route,
            backendAlternative: backendAlternative,
            originName: originName,
            destinationName: destinationName,
            durationText: "\(durationMinutes) min",
            transitSummary: transitSummary,
            walkingSummary: walkingSummary,
            reliabilityText: reliabilityText
        )
    }

    var detailSegments: [RouteItinerarySegment] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            return detailSegments(from: steps)
        }

        guard let route else { return [] }

        let startDate = Date()
        let usefulSteps = route.steps.filter { step in
            step.distance > 8 || !step.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }

        var elapsedMinutes = 0
        var segments: [RouteItinerarySegment] = [
            RouteItinerarySegment(
                timeText: elapsedMinutes.clockString(from: startDate),
                placeTitle: originName,
                icon: nil,
                accentColor: DS.Color.paper,
                stepCard: nil,
                durationBadge: nil
            )
        ]

        for (index, step) in usefulSteps.enumerated() {
            let durationMinutes = Self.estimatedMinutes(for: step)
            elapsedMinutes += durationMinutes

            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            let title = instruction.isEmpty ? Self.fallbackTitle(for: step, destinationName: destinationName) : instruction
            let lineCode = Self.extractLineCode(from: instruction)
            let isLastLeg = index == usefulSteps.count - 1

            segments.append(
                RouteItinerarySegment(
                    timeText: elapsedMinutes.clockString(from: startDate),
                    placeTitle: Self.placeTitle(for: step, isLastLeg: isLastLeg, destinationName: destinationName, lineCode: lineCode),
                    icon: Self.iconName(for: step),
                    accentColor: Self.accentColor(for: step, lineCode: lineCode),
                    stepCard: RouteItineraryStepCard(
                        style: step.transportType == .walking ? .white : .mint,
                        title: title,
                        subtitle: Self.subtitle(for: step),
                        lineBadge: lineCode,
                        serviceInfo: nil
                    ),
                    durationBadge: "\(durationMinutes) min",
                    stopCountText: Self.stopCountText(for: step)
                )
            )
        }

        if segments.last?.placeTitle != destinationName {
            segments.append(
                RouteItinerarySegment(
                    timeText: max(elapsedMinutes, Int((route.expectedTravelTime / 60).rounded())).clockString(from: startDate),
                    placeTitle: destinationName,
                    icon: nil,
                    accentColor: DS.Color.primary,
                    stepCard: nil,
                    durationBadge: nil
                )
            )
        }

        return segments
    }

    var routeCoordinates: [CLLocationCoordinate2D] {
        if let backendAlternative,
           let backendCoordinates = Self.coordinates(from: backendAlternative),
           !backendCoordinates.isEmpty {
            return backendCoordinates
        }

        guard let route else { return [] }
        let polyline = route.polyline
        return (0..<polyline.pointCount).map { polyline.points()[$0].coordinate }
    }

    var mapRectWithPadding: MKMapRect {
        let rect: MKMapRect
        if routeCoordinates.count > 1 {
            rect = MKPolyline(coordinates: routeCoordinates, count: routeCoordinates.count).boundingMapRect
        } else if let route {
            rect = route.polyline.boundingMapRect
        } else if let first = routeCoordinates.first {
            rect = MKMapRect(origin: MKMapPoint(first), size: MKMapSize(width: 1200, height: 1200))
        } else {
            rect = MKMapRect.world
        }
        return rect.insetBy(dx: -rect.width * 0.35, dy: -rect.height * 0.35)
    }

    func primaryBearing(from current: CLLocationCoordinate2D) -> Double? {
        let coords = routeCoordinates
        guard coords.count > 1 else { return nil }
        let nextCoord = nextCoordinate(from: current, in: coords) ?? coords[1]
        return current.bearing(to: nextCoord)
    }

    func arInstruction(from current: CLLocationCoordinate2D) -> RouteARInstruction {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            let nextStep = steps.first { step in
                guard let coordinate = Self.primaryCoordinate(for: step) else { return false }
                return current.distance(to: coordinate) > 20
            } ?? steps.first

            let primaryText = nextStep?.instruction ?? "Suivez l’itinéraire vers \(destinationName)"
            let secondaryText = nextStep.map(Self.summaryText(for:)) ?? walkingSummary
            let distanceText = nextStep
                .flatMap(Self.primaryCoordinate(for:))
                .map { current.distance(to: $0).distanceLabel }
                ?? durationText

            return RouteARInstruction(
                primaryText: primaryText,
                secondaryText: secondaryText,
                distanceText: distanceText
            )
        }

        guard let route else {
            return RouteARInstruction(
                primaryText: "Suivez l’itinéraire vers \(destinationName)",
                secondaryText: walkingSummary,
                distanceText: durationText
            )
        }

        let usefulSteps = route.steps.filter { !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        let nextStep = usefulSteps.first { step in
            guard let coord = step.polyline.firstCoordinate else { return false }
            return current.distance(to: coord) > 20
        } ?? usefulSteps.first

        let cleanedInstruction = nextStep?.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
        let primaryText = (cleanedInstruction?.isEmpty == false ? cleanedInstruction : nil) ?? "Suivez l’itinéraire vers \(destinationName)"
        let distance = nextStep?.distance ?? route.distance
        let transportType = nextStep?.transportType ?? .walking

        return RouteARInstruction(
            primaryText: primaryText,
            secondaryText: transportType == .transit ? transitSummary : walkingSummary,
            distanceText: distance.distanceLabel
        )
    }

    private func detailSegments(from steps: [TransportRouteStepDTO]) -> [RouteItinerarySegment] {
        let startDate = Date()
        var elapsedMinutes = 0
        var segments: [RouteItinerarySegment] = [
            RouteItinerarySegment(
                timeText: elapsedMinutes.clockString(from: startDate),
                placeTitle: originName,
                icon: nil,
                accentColor: DS.Color.paper,
                stepCard: nil,
                durationBadge: nil
            )
        ]

        let sortedSteps = steps.sorted { $0.order < $1.order }
        for (index, step) in sortedSteps.enumerated() {
            elapsedMinutes += max(1, step.durationMinutes)
            let isLastStep = index == sortedSteps.count - 1

            segments.append(
                RouteItinerarySegment(
                    timeText: elapsedMinutes.clockString(from: startDate),
                    placeTitle: placeTitle(for: step, isLastStep: isLastStep),
                    icon: Self.iconName(for: step),
                    accentColor: Self.accentColor(for: step),
                    stepCard: RouteItineraryStepCard(
                        style: Self.cardStyle(for: step),
                        title: step.instruction,
                        subtitle: Self.subtitle(for: step),
                        lineBadge: step.line,
                        serviceInfo: nil
                    ),
                    durationBadge: "\(max(1, step.durationMinutes)) min",
                    stopCountText: step.stopsCount.map { $0 > 1 ? "\($0) arrêts" : "1 arrêt" }
                )
            )
        }

        if segments.last?.placeTitle != destinationName {
            segments.append(
                RouteItinerarySegment(
                    timeText: max(elapsedMinutes, totalDurationMinutes).clockString(from: startDate),
                    placeTitle: destinationName,
                    icon: nil,
                    accentColor: DS.Color.primary,
                    stepCard: nil,
                    durationBadge: nil
                )
            )
        }

        return segments
    }

    var totalDurationMinutes: Int {
        backendAlternative?.totalDurationMinutes ?? max(1, Int((((route?.expectedTravelTime) ?? 60) / 60).rounded()))
    }

    var departureTimeText: String {
        realtimeDepartureTimeText ?? scheduledDepartureTimeText ?? Self.timeFormatter.string(from: Date())
    }

    var arrivalTimeText: String {
        realtimeArrivalTimeText
            ?? scheduledArrivalTimeText
            ?? Self.timeFormatter.string(from: Date().addingTimeInterval(TimeInterval(totalDurationMinutes * 60)))
    }

    var scheduledDepartureTimeText: String? {
        backendAlternative?.scheduledDepartureAt.map { Self.timeFormatter.string(from: $0) }
    }

    var scheduledArrivalTimeText: String? {
        backendAlternative?.scheduledArrivalAt.map { Self.timeFormatter.string(from: $0) }
    }

    var realtimeDepartureTimeText: String? {
        backendAlternative?.realtimeDepartureAt.map { Self.timeFormatter.string(from: $0) }
    }

    var realtimeArrivalTimeText: String? {
        backendAlternative?.realtimeArrivalAt.map { Self.timeFormatter.string(from: $0) }
    }

    var hasRealtimeTimingDelta: Bool {
        scheduledDepartureTimeText != realtimeDepartureTimeText || scheduledArrivalTimeText != realtimeArrivalTimeText
    }

    /// Single-line arrival-focused summary shown in the recommendation card.
    /// We dropped the "TEMPS RÉEL 16:58 → 17:01 / Prévu 17:14 → 17:50" dual
    /// display — users found it confusing to see two different timeframes for
    /// the same trip. The realtime arrival time is the one that matters; the
    /// scheduled value is reduced to a tiny delay note below when it differs.
    var timingHeadlineText: String {
        if let realtimeArrivalTimeText {
            return "Arrivée \(realtimeArrivalTimeText)"
        }
        if let scheduledArrivalTimeText {
            return "Arrivée vers \(scheduledArrivalTimeText)"
        }
        return "Arrivée \(arrivalTimeText)"
    }

    /// Short delay note, only when realtime is meaningfully later than the
    /// scheduled time. We compute it in minutes so the user sees "+ 3 min
    /// par rapport à l'horaire" instead of two separate clocks.
    var timingSecondaryText: String? {
        guard hasRealtimeTimingDelta,
              let realtime = backendAlternative?.realtimeArrivalAt,
              let scheduled = backendAlternative?.scheduledArrivalAt else { return nil }
        let deltaMin = Int(realtime.timeIntervalSince(scheduled) / 60.0)
        guard abs(deltaMin) >= 1 else { return nil }
        if deltaMin > 0 {
            return "+ \(deltaMin) min vs prévu"
        } else {
            return "\(deltaMin) min vs prévu"
        }
    }

    var arrivalSummaryText: String {
        "Arrivée \(arrivalTimeText)"
    }

    var nextDepartureInsight: RouteDepartureInsight? {
        guard let step = backendAlternative?.steps?
            .sorted(by: { $0.order < $1.order })
            .first(where: { step in
                guard let line = step.line else { return false }
                return !line.isEmpty && !["walk", "bike"].contains(step.mode.lowercased())
            }),
            let line = step.line else { return nil }

        let departureDate = step.realtimeDepartureAt ?? step.scheduledDepartureAt
        let departureText = departureDate.map(Self.timeFormatter.string(from:)) ?? departureTimeText
        let arrivalText = (step.realtimeArrivalAt ?? step.scheduledArrivalAt).map(Self.timeFormatter.string(from:))
        let waitText = step.realtimeDepartureMinutes.map(Self.waitText)
            ?? departureDate.map(Self.waitText)
            ?? "À \(departureText)"

        return RouteDepartureInsight(
            lineCode: line,
            modeText: Self.modeText(for: step),
            waitText: waitText,
            departureText: departureText,
            arrivalText: arrivalText,
            stopText: step.destination ?? step.arrivalStopName,
            isRealtime: step.realtimeDepartureAt != nil || step.realtimeDepartureMinutes != nil
        )
    }

    var primaryModeKey: String {
        if let backendAlternative {
            return Self.primaryMode(for: backendAlternative)
        }
        let transportTypes = Set((route?.steps ?? []).map { $0.transportType.rawValue })
        if transportTypes.contains(MKDirectionsTransportType.transit.rawValue) { return "transit" }
        if transportTypes.contains(MKDirectionsTransportType.walking.rawValue) && transportTypes.count == 1 { return "walk" }
        return "bike"
    }

    var primaryModeLabel: String {
        switch primaryModeKey {
        case "bike": return "Vélo"
        case "walk": return "À pied"
        default: return "Transport"
        }
    }

    var primaryModeIcon: String {
        switch primaryModeKey {
        case "bike": return "bicycle"
        case "walk": return "figure.walk"
        default: return "tram.fill"
        }
    }

    var transferSummary: String {
        let transfers = backendAlternative?.transfers ?? max(0, displayLineCodes.count - 1)
        return "\(transfers) corresp."
    }

    var displayLineCodes: [String] {
        if let backendAlternative, !backendAlternative.lines.isEmpty {
            return Array(backendAlternative.lines.prefix(4))
        }

        let extracted = (route?.steps ?? []).compactMap { step -> String? in
            guard step.transportType == .transit else { return nil }
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.extractLineCode(from: instruction)
        }
        return Array(NSOrderedSet(array: extracted).array as? [String] ?? [])
    }

    var terminalLabel: String {
        if let backendAlternative,
           let lastTransit = (backendAlternative.steps ?? []).last(where: { $0.line != nil }),
           let stop = lastTransit.arrivalStopName ?? lastTransit.destination {
            return stop
        }
        return destinationName
    }

    var dedupeKey: String {
        let lines = displayLineCodes.joined(separator: "-")
        return "\(primaryModeKey)|\(totalDurationMinutes)|\(lines)|\(terminalLabel)"
    }

    var leadingAccentColor: Color {
        if let first = displayLineCodes.first {
            return TransitLinePalette.fill(for: first)
        }
        switch primaryModeKey {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.inkMute.opacity(0.45)
        default: return DS.Color.primary
        }
    }

    var visualSegments: [RouteVisualSegment] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            return steps.map { step in
                RouteVisualSegment(
                    tint: Self.segmentColor(for: step),
                    weight: max(CGFloat(step.durationMinutes), 0.8)
                )
            }
        }

        let usefulSteps = (route?.steps ?? []).filter { $0.distance > 8 || !$0.instructions.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return usefulSteps.map { step in
            RouteVisualSegment(
                tint: step.transportType == .walking
                    ? DS.Color.ink.opacity(0.28)
                    : TransitLinePalette.fill(for: Self.extractLineCode(from: step.instructions) ?? "1"),
                weight: max(CGFloat(Self.estimatedMinutes(for: step)), 0.8)
            )
        }
    }

    var inlineSteps: [InlineRouteStepItem] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            return steps.sorted { $0.order < $1.order }.map { step in
                InlineRouteStepItem(
                    icon: Self.inlineIcon(for: step),
                    title: Self.inlineTitle(for: step),
                    meta: Self.inlineMeta(for: step),
                    lineCode: step.line,
                    timingBadge: Self.inlineTimingBadge(for: step),
                    timingDetail: Self.inlineTimingDetail(for: step)
                )
            }
        }

        return detailSegments.compactMap { segment in
            guard let stepCard = segment.stepCard else { return nil }
            return InlineRouteStepItem(
                icon: segment.icon,
                title: stepCard.title,
                meta: [segment.stopCountText, segment.durationBadge].compactMap { $0 }.joined(separator: " · "),
                lineCode: stepCard.lineBadge,
                timingBadge: nil,
                timingDetail: nil
            )
        }
    }

    func deltaText(comparedTo base: HomeRouteOption?) -> String? {
        guard let base else { return nil }
        let delta = totalDurationMinutes - base.totalDurationMinutes
        guard delta > 0 else { return nil }
        return "+\(delta) min"
    }

    private static func estimatedMinutes(for step: MKRoute.Step) -> Int {
        switch step.transportType {
        case .walking:
            return max(1, Int((step.distance / 75).rounded()))
        case .transit:
            return max(2, Int((step.distance / 280).rounded()))
        default:
            return max(2, Int((step.distance / 250).rounded()))
        }
    }

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.timeZone = TimeZone(identifier: "Europe/Brussels")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    private static func modeText(for step: TransportRouteStepDTO) -> String {
        switch step.mode.lowercased() {
        case "bus": return "Bus"
        case "metro": return "Métro"
        case "tram": return "Tram"
        default: return "Ligne"
        }
    }

    private static func waitText(_ minutes: Int) -> String {
        if minutes <= 0 { return "Maintenant" }
        if minutes == 1 { return "Dans 1 min" }
        return "Dans \(minutes) min"
    }

    private static func waitText(for date: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSince(Date()) / 60))
        if minutes <= 0 { return "Maintenant" }
        if minutes <= 90 { return waitText(minutes) }
        return "À \(timeFormatter.string(from: date))"
    }

    private static func extractLineCode(from instruction: String) -> String? {
        let pattern = #"\b(T?\d{1,3})\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(instruction.startIndex..<instruction.endIndex, in: instruction)
        guard let match = regex.firstMatch(in: instruction, range: range),
              let foundRange = Range(match.range(at: 1), in: instruction) else { return nil }
        return String(instruction[foundRange]).uppercased()
    }

    private static func iconName(for step: MKRoute.Step) -> String? {
        switch step.transportType {
        case .walking: return "figure.walk"
        case .transit: return "tram.fill"
        default: return nil
        }
    }

    private static func accentColor(for step: MKRoute.Step, lineCode: String?) -> Color {
        switch step.transportType {
        case .walking:
            return DS.Color.paper2
        case .transit:
            if let lineCode {
                return TransitLinePalette.fill(for: lineCode)
            }
            return DS.Color.community
        default:
            return DS.Color.inkMute
        }
    }

    private static func placeTitle(for step: MKRoute.Step, isLastLeg: Bool, destinationName: String, lineCode: String?, lineFallback: String = "Transport") -> String {
        if isLastLeg && step.transportType == .walking {
            return destinationName
        }
        if let lineCode {
            return "Ligne \(lineCode)"
        }
        switch step.transportType {
        case .walking: return "À pied"
        case .transit: return lineFallback
        default: return "Étape"
        }
    }

    private static func fallbackTitle(for step: MKRoute.Step, destinationName: String) -> String {
        switch step.transportType {
        case .walking:
            return "Marcher vers \(destinationName)"
        case .transit:
            return "Prendre le transport suivant"
        default:
            return "Suivre l’itinéraire"
        }
    }

    private static func subtitle(for step: MKRoute.Step) -> String {
        switch step.transportType {
        case .walking:
            return step.distance.distanceLabel
        case .transit:
            return "Étape transport"
        default:
            return "Suivez l’itinéraire"
        }
    }

    private static func stopCountText(for step: MKRoute.Step) -> String? {
        guard step.transportType == .transit else { return nil }
        let estimatedStops = max(1, Int((step.distance / 350).rounded()))
        return estimatedStops > 1 ? "\(estimatedStops) arrêts" : "1 arrêt"
    }

    private func placeTitle(for step: TransportRouteStepDTO, isLastStep: Bool) -> String {
        if isLastStep, step.mode == "walk" {
            return destinationName
        }
        if let stopName = step.stopName, !stopName.isEmpty {
            return stopName
        }
        if let arrivalStopName = step.arrivalStopName, !arrivalStopName.isEmpty {
            return arrivalStopName
        }
        if let line = step.line, !line.isEmpty {
            return "Ligne \(line)"
        }
        switch step.mode.lowercased() {
        case "bike": return "À vélo"
        case "walk": return "À pied"
        default: return "Correspondance"
        }
    }

    private static func transitSummary(from alternative: TransportAlternativeDTO) -> String {
        if !alternative.lines.isEmpty {
            let label = alternative.lines.count > 1 ? "lignes" : "ligne"
            return "\(alternative.lines.count) \(label)"
        }
        switch primaryMode(for: alternative) {
        case "bike": return "à vélo"
        case "walk": return "à pied"
        default: return "transport"
        }
    }

    private static func reliabilitySummary(from alternative: TransportAlternativeDTO) -> String {
        if alternative.transfers == 0 {
            return "direct"
        }
        return "\(alternative.transfers) corresp."
    }

    static func primaryMode(for alternative: TransportAlternativeDTO) -> String {
        let modes = Set((alternative.steps ?? []).map { $0.mode.lowercased() })
        if modes.contains("tram") || modes.contains("bus") || modes.contains("metro") {
            return "transit"
        }
        if modes.contains("bike") {
            return "bike"
        }
        return "walk"
    }

    private static func coordinates(from alternative: TransportAlternativeDTO) -> [CLLocationCoordinate2D]? {
        let points = (alternative.steps ?? []).flatMap { step in
            (step.path ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        }
        guard !points.isEmpty else { return nil }

        var deduped: [CLLocationCoordinate2D] = []
        for point in points {
            if deduped.last?.latitude == point.latitude && deduped.last?.longitude == point.longitude {
                continue
            }
            deduped.append(point)
        }
        return deduped
    }

    static func segmentCoordinates(for step: TransportRouteStepDTO) -> [CLLocationCoordinate2D] {
        let pathCoordinates = (step.path ?? []).map {
            CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng)
        }
        if pathCoordinates.count > 1 {
            return dedupedCoordinates(pathCoordinates)
        }

        var coordinates: [CLLocationCoordinate2D] = []
        if let lat = step.startLatitude, let lng = step.startLongitude {
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        if let lat = step.targetLatitude, let lng = step.targetLongitude {
            coordinates.append(CLLocationCoordinate2D(latitude: lat, longitude: lng))
        }
        return dedupedCoordinates(coordinates)
    }

    static func mapStrokeColor(for step: TransportRouteStepDTO) -> Color {
        if let line = step.line, !line.isEmpty {
            return TransitLinePalette.fill(for: line)
        }
        switch step.mode.lowercased() {
        case "bike":
            return DS.Color.villo
        case "walk":
            return DS.Color.ink.opacity(0.30)
        default:
            return DS.Color.primary
        }
    }

    static func mapStrokeWidth(for step: TransportRouteStepDTO) -> CGFloat {
        switch step.mode.lowercased() {
        case "walk":
            return 4
        case "bike":
            return 5
        default:
            return 6
        }
    }

    private static func primaryCoordinate(for step: TransportRouteStepDTO) -> CLLocationCoordinate2D? {
        if let lat = step.startLatitude, let lng = step.startLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let lat = step.targetLatitude, let lng = step.targetLongitude {
            return CLLocationCoordinate2D(latitude: lat, longitude: lng)
        }
        if let path = step.path?.first {
            return CLLocationCoordinate2D(latitude: path.lat, longitude: path.lng)
        }
        return nil
    }

    private static func iconName(for step: TransportRouteStepDTO) -> String? {
        switch step.mode.lowercased() {
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        case "bus": return "bus.fill"
        default: return "tram.fill"
        }
    }

    private static func accentColor(for step: TransportRouteStepDTO) -> Color {
        if let line = step.line {
            return TransitLinePalette.fill(for: line)
        }
        switch step.mode.lowercased() {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.paper2
        case "bus": return DS.Color.community
        case "metro": return DS.Color.primary
        default: return DS.Color.accent
        }
    }

    private static func cardStyle(for step: TransportRouteStepDTO) -> RouteItineraryStepCard.CardStyle {
        switch step.mode.lowercased() {
        case "walk": return .white
        default: return .mint
        }
    }

    private static func subtitle(for step: TransportRouteStepDTO) -> String {
        if let arrivalStopName = step.arrivalStopName, !arrivalStopName.isEmpty {
            return "Vers \(arrivalStopName)"
        }
        if let destination = step.destination, !destination.isEmpty {
            return "Direction \(destination)"
        }
        switch step.mode.lowercased() {
        case "bike": return "Étape à vélo"
        case "walk": return "Étape à pied"
        default: return "Étape transport"
        }
    }

    private static func summaryText(for step: TransportRouteStepDTO) -> String {
        if let line = step.line, !line.isEmpty {
            return "Ligne \(line)"
        }
        switch step.mode.lowercased() {
        case "bike": return "Pédalez vers la prochaine étape"
        case "walk": return "Marche en cours"
        default: return "Transport en cours"
        }
    }

    private static func segmentColor(for step: TransportRouteStepDTO) -> Color {
        if let line = step.line, !line.isEmpty {
            return TransitLinePalette.fill(for: line)
        }
        switch step.mode.lowercased() {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.ink.opacity(0.28)
        default: return DS.Color.ink.opacity(0.22)
        }
    }

    private static func inlineIcon(for step: TransportRouteStepDTO) -> String? {
        switch step.mode.lowercased() {
        case "walk": return "figure.walk"
        case "bike": return "bicycle"
        default: return nil
        }
    }

    private static func inlineTitle(for step: TransportRouteStepDTO) -> String {
        if let line = step.line, !line.isEmpty {
            let start = step.stopName ?? "Départ"
            let end = step.arrivalStopName ?? step.destination ?? "Arrivée"
            return "\(start) → \(end)"
        }

        if step.mode.lowercased() == "walk" {
            if let target = step.stopName ?? step.arrivalStopName ?? step.destination {
                return "Marche vers \(target)"
            }
            return "Marche"
        }

        if step.mode.lowercased() == "bike" {
            return "Vélo vers \(step.arrivalStopName ?? step.destination ?? "destination")"
        }

        return step.destination ?? "Correspondance"
    }

    private static func inlineMeta(for step: TransportRouteStepDTO) -> String {
        var parts: [String] = []
        if let stops = step.stopsCount {
            parts.append(stops > 1 ? "\(stops) arrêts" : "1 arrêt")
        } else if step.mode.lowercased() == "walk",
                  let startLat = step.startLatitude,
                  let startLng = step.startLongitude,
                  let endLat = step.targetLatitude,
                  let endLng = step.targetLongitude {
            let distance = CLLocation(latitude: startLat, longitude: startLng)
                .distance(from: CLLocation(latitude: endLat, longitude: endLng))
            parts.append(distance.distanceLabel.uppercased())
        }
        parts.append("\(max(1, step.durationMinutes)) min".uppercased())
        if let realtimeDepartureAt = step.realtimeDepartureAt {
            let departure = timeFormatter.string(from: realtimeDepartureAt)
            if let realtimeArrivalAt = step.realtimeArrivalAt {
                parts.append("\(departure)→\(timeFormatter.string(from: realtimeArrivalAt))")
            } else {
                parts.append("DÉP. \(departure)")
            }
        } else if let scheduledDepartureAt = step.scheduledDepartureAt {
            let departure = timeFormatter.string(from: scheduledDepartureAt)
            if let scheduledArrivalAt = step.scheduledArrivalAt {
                parts.append("\(departure)→\(timeFormatter.string(from: scheduledArrivalAt))")
            } else {
                parts.append("PRÉVU \(departure)")
            }
        }
        return parts.joined(separator: " · ")
    }

    private static func inlineTimingBadge(for step: TransportRouteStepDTO) -> String? {
        guard step.line != nil else { return nil }
        if let minutes = step.realtimeDepartureMinutes {
            return waitText(minutes)
        }
        if let realtimeDepartureAt = step.realtimeDepartureAt {
            return waitText(for: realtimeDepartureAt)
        }
        if let scheduledDepartureAt = step.scheduledDepartureAt {
            return "Prévu \(timeFormatter.string(from: scheduledDepartureAt))"
        }
        return nil
    }

    private static func inlineTimingDetail(for step: TransportRouteStepDTO) -> String? {
        let departureDate = step.realtimeDepartureAt ?? step.scheduledDepartureAt
        let arrivalDate = step.realtimeArrivalAt ?? step.scheduledArrivalAt
        guard let departureDate else { return nil }

        let source = (step.realtimeDepartureAt != nil || step.realtimeDepartureMinutes != nil) ? "Temps réel" : "Horaire prévu"
        let departure = timeFormatter.string(from: departureDate)
        if let arrivalDate {
            return "\(source) · \(departure) → \(timeFormatter.string(from: arrivalDate))"
        }
        return "\(source) · départ \(departure)"
    }

    private func nextCoordinate(from current: CLLocationCoordinate2D, in coords: [CLLocationCoordinate2D]) -> CLLocationCoordinate2D? {
        guard !coords.isEmpty else { return nil }
        let nearest = coords.enumerated().min { lhs, rhs in
            current.distance(to: lhs.element) < current.distance(to: rhs.element)
        }
        guard let nearest else { return nil }
        return coords[min(coords.count - 1, nearest.offset + 1)]
    }

    private static func dedupedCoordinates(_ coordinates: [CLLocationCoordinate2D]) -> [CLLocationCoordinate2D] {
        var deduped: [CLLocationCoordinate2D] = []
        for point in coordinates {
            if deduped.last?.latitude == point.latitude && deduped.last?.longitude == point.longitude {
                continue
            }
            deduped.append(point)
        }
        return deduped
    }
}
