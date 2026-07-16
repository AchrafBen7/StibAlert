import MapKit
import SwiftUI

/// One leg of a journey, for the Google-style flow strip (walk vs a line).
enum RouteLegChip: Equatable {
    /// Marche, AVEC sa durée : une icône de piéton nue ne dit rien. Google
    /// écrit « 🚶 4 » — c'est la minute qui porte l'information, pas le
    /// pictogramme, et une rangée en alignait jusqu'à cinq, muets.
    case walk(minutes: Int)
    case line(RouteLineDescriptor)
}

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
        let transitSummary = backendAlternative.map(Self.transitSummary(from:)) ?? (transitSteps.isEmpty ? L10n.Routing.walk : L10n.Routing.transportCount(transitSteps.count))
        let walkingSummary = L10n.Routing.walkingMinutes(backendAlternative?.walkingMinutes ?? walkingMinutes)
        let reliabilityText = backendAlternative.map(Self.reliabilitySummary(from:)) ?? (transferCount == 0 ? L10n.Routing.direct : L10n.Routing.transferCount(transferCount))

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
            let lineDescriptor = lineCode.map { RouteLineDescriptor(code: $0) }
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
                        lineBadge: lineDescriptor,
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

    /// Modes qui ne sont PAS du transport en commun (marche, vélo).
    private static let nonTransitModes: Set<String> = [
        "walk", "walking", "foot", "pedestrian",
        "bike", "biking", "bicycle", "bicycling", "cycling",
    ]

    private static func isNonTransit(_ mode: String) -> Bool {
        nonTransitModes.contains(mode.lowercased())
    }

    /// Une suite de manœuvres marche/vélo réduite à UNE étape.
    private struct MergedStep {
        /// La première manœuvre du lot : elle porte le point de départ du segment.
        let step: TransportRouteStepDTO
        /// Somme RÉELLE des durées fusionnées (pas 1 min par manœuvre).
        let durationMinutes: Int
        let isMerged: Bool
    }

    /// Fusionne les manœuvres consécutives d'un même mode non-transport.
    ///
    /// ORS renvoie du guidage tour-par-tour : un trajet vélo de 25 min arrive en
    /// **36 manœuvres** (« Head west », « Turn right », « Turn slight left »…)
    /// de 0 à 1 min chacune. En rendre une rangée chacune donnait 36 lignes
    /// identiques « Vélo vers destination · 1 MIN », et le `max(1, …)` appliqué
    /// PAR manœuvre gonflait le temps cumulé bien au-delà de la durée réelle.
    /// Un écran de CHOIX d'itinéraire montre le trajet, pas le guidage : une
    /// seule rangée par segment à pied / à vélo, avec la durée vraiment cumulée.
    private func mergedSteps(from steps: [TransportRouteStepDTO]) -> [MergedStep] {
        var merged: [MergedStep] = []
        for step in steps.sorted(by: { $0.order < $1.order }) {
            let mode = step.mode.lowercased()
            if Self.isNonTransit(mode),
               let last = merged.last,
               last.step.mode.lowercased() == mode {
                merged[merged.count - 1] = MergedStep(
                    step: last.step,
                    durationMinutes: last.durationMinutes + step.durationMinutes,
                    isMerged: true
                )
            } else {
                merged.append(MergedStep(step: step, durationMinutes: step.durationMinutes, isMerged: false))
            }
        }
        return merged
    }

    /// Libellé propre d'un segment marche/vélo. Les manœuvres ORS arrivent en
    /// ANGLAIS (« Head west ») : on ne les affiche pas, on décrit le segment.
    private static func nonTransitTitle(mode: String, minutes: Int) -> String {
        let normalized = mode.lowercased()
        let isBike = normalized.contains("bik") || normalized.contains("cycl")
        return isBike
            ? AppLocalizer.format("routing.bike_minutes", defaultValue: "Vélo %lld min", minutes)
            : AppLocalizer.format("routing.walk_minutes", defaultValue: "Marche %lld min", minutes)
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

        let mergedList = mergedSteps(from: steps)
        for (index, merged) in mergedList.enumerated() {
            let step = merged.step
            let duration = max(1, merged.durationMinutes)
            elapsedMinutes += duration
            let isLastStep = index == mergedList.count - 1
            let lineDescriptor = Self.lineDescriptor(for: step)
            let nonTransit = Self.isNonTransit(step.mode)

            segments.append(
                RouteItinerarySegment(
                    timeText: elapsedMinutes.clockString(from: startDate),
                    placeTitle: placeTitle(for: step, isLastStep: isLastStep),
                    icon: Self.iconName(for: step),
                    accentColor: lineDescriptor?.fillColor ?? Self.accentColor(for: step),
                    stepCard: RouteItineraryStepCard(
                        style: Self.cardStyle(for: step),
                        title: nonTransit
                            ? Self.nonTransitTitle(mode: step.mode, minutes: duration)
                            : step.instruction,
                        subtitle: Self.subtitle(for: step),
                        lineBadge: lineDescriptor,
                        serviceInfo: nil
                    ),
                    durationBadge: "\(duration) min",
                    stopCountText: step.stopsCount.map(L10n.Routing.stopCount),
                    // Le backend ne renseigne ces deux listes que sur un tronçon
                    // transport STIB. Partout ailleurs (marche, De Lijn, TEC, SNCB)
                    // elles arrivent nil → vides → aucun chevron.
                    //
                    // La STIB nomme ses arrêts en CAPITALES (« DE WAND ») là où Google
                    // les rend en casse normale (« Gare de Bockstael »). On aligne
                    // l'affichage sur Google — les deux se côtoient dans la même carte.
                    intermediateStops: (step.intermediateStops ?? [])
                        .map { $0.capitalized(with: AppLocale.current) },
                    otherDepartures: Self.otherDepartures(from: step)
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

    /// True end-of-journey time. `realtimeArrivalAt` only reflects the
    /// realtime-tracked legs, so on a trip ending with a scheduled-only leg it
    /// can report an *intermediate* time (e.g. the first tram's arrival),
    /// which made the card show an arrival earlier than the last leg and a
    /// bogus "−25 min vs prévu". You can't arrive before the final scheduled
    /// leg completes, so take the later of the two.
    var effectiveArrivalDate: Date? {
        let realtime = backendAlternative?.realtimeArrivalAt
        let scheduled = backendAlternative?.scheduledArrivalAt
        switch (realtime, scheduled) {
        case let (r?, s?): return max(r, s)
        case let (r?, nil): return r
        case let (nil, s?): return s
        default: return nil
        }
    }

    var arrivalTimeText: String {
        if let date = effectiveArrivalDate {
            return Self.timeFormatter.string(from: date)
        }
        return Self.timeFormatter.string(from: Date().addingTimeInterval(TimeInterval(totalDurationMinutes * 60)))
    }

    /// « 12:54 – 13:08 » — la plage horaire du trajet, ligne 1 de la rangée
    /// compacte. `timeFormatter` est calé sur Europe/Brussels et sur la langue
    /// de l'app (et non sur `Locale.current`, que l'override de langue interne
    /// ne modifie pas). Les deux bornes ont un repli (départ = maintenant,
    /// arrivée = maintenant + durée), donc la plage est toujours affichable,
    /// y compris pour une option Apple Maps sans alternative backend.
    var scheduleRangeText: String {
        "\(departureTimeText) – \(arrivalTimeText)"
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
        L10n.Routing.arrivalAt(arrivalTimeText)
    }

    /// Short delay note — only when the trip is genuinely *late* vs the
    /// schedule. We no longer show "early" deltas: a realtime arrival earlier
    /// than the scheduled one is almost always an intermediate-leg artifact,
    /// not a real time saving, and showing "−25 min vs prévu" was misleading.
    var timingSecondaryText: String? {
        guard let realtime = backendAlternative?.realtimeArrivalAt,
              let scheduled = backendAlternative?.scheduledArrivalAt else { return nil }
        let deltaMin = Int(realtime.timeIntervalSince(scheduled) / 60.0)
        guard deltaMin >= 1 else { return nil }
        return L10n.Routing.lateBy(deltaMin)
    }

    var arrivalSummaryText: String {
        L10n.Routing.arrivalAt(arrivalTimeText)
    }

    var nextDepartureInsight: RouteDepartureInsight? {
        guard let step = backendAlternative?.steps?
            .sorted(by: { $0.order < $1.order })
            .first(where: { step in
                guard let line = Self.displayLine(for: step) else { return false }
                return !line.isEmpty && !["walk", "bike"].contains(step.mode.lowercased())
            }),
            let line = Self.displayLine(for: step) else { return nil }

        // L'HEURE DE CE TRAJET-CI, PAS « LE PROCHAIN À CET ARRÊT ».
        //
        // `realtimeDepartureMinutes` décrit le prochain passage de la ligne à
        // l'arrêt, calculé depuis MAINTENANT — il ne connaît pas l'itinéraire.
        // Le lire en priorité produisait deux mensonges visibles à l'écran :
        //   1. deux itinéraires « 10 → 88 » arrivant à 16:46 et à 17:01
        //      affichaient TOUS LES DEUX « Prochain 10 · Maintenant », alors
        //      qu'ils prennent deux trams différents ;
        //   2. « Maintenant » sur un trajet qui commence par 7 min de marche :
        //      ce tram-là, on ne peut PAS l'avoir. L'itinéraire, lui, tient
        //      déjà compte de la marche — c'est donc SON heure d'embarquement
        //      qui est la bonne, et elle seule.
        // On garde le temps réel uniquement quand il colle à ce départ-ci
        // (tolérance 10 min = un retard plausible, pas une autre course).
        let scheduled = step.scheduledDepartureAt
        let realtime = step.realtimeDepartureAt
        let realtimeMatchesThisTrip: Bool = {
            guard let realtime, let scheduled else { return false }
            return abs(realtime.timeIntervalSince(scheduled)) <= 10 * 60
        }()
        let departureDate = (realtimeMatchesThisTrip ? realtime : nil) ?? scheduled ?? realtime
        let departureText = departureDate.map(Self.timeFormatter.string(from:)) ?? departureTimeText
        let arrivalText = (step.realtimeArrivalAt ?? step.scheduledArrivalAt).map(Self.timeFormatter.string(from:))

        // GARDE-FOU : un départ qu'on ne peut PAS attraper ne s'annonce pas
        // comme attrapable.
        //
        // Le backend écrase l'heure du tronçon avec « le prochain passage à cet
        // arrêt » : sur un trajet avec 9 min de marche, le tram était donné pour
        // partir à l'instant même du départ du trajet. On affichait donc
        // « Maintenant » sur un tram qu'il faut 9 minutes pour rejoindre.
        // Si le départ tombe avant qu'on puisse physiquement être là, on cesse
        // de promettre un délai et on se contente de donner l'HEURE : c'est vrai,
        // et ça laisse l'utilisateur juger.
        let walkMinutesBefore = (backendAlternative?.steps ?? [])
            .sorted { $0.order < $1.order }
            .prefix { Self.isNonTransit($0.mode) }
            .reduce(0) { $0 + $1.durationMinutes }
        let isReachable: Bool = {
            guard let departureDate else { return true }
            let minutesUntil = departureDate.timeIntervalSinceNow / 60
            return minutesUntil >= Double(walkMinutesBefore)
        }()

        let waitText = isReachable
            ? (departureDate.map(Self.waitText) ?? L10n.Routing.atTime(departureText))
            : L10n.Routing.atTime(departureText)

        return RouteDepartureInsight(
            lineCode: line,
            modeText: Self.modeText(for: step),
            waitText: waitText,
            departureText: departureText,
            arrivalText: arrivalText,
            stopText: step.destination ?? step.arrivalStopName,
            // La pastille verte « temps réel » ne s'allume que si le temps réel
            // concerne VRAIMENT ce départ-ci. Sinon, on affiche une heure
            // théorique honnête plutôt qu'une fausse promesse de live.
            isRealtime: realtimeMatchesThisTrip
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
        case "bike": return L10n.Routing.bike
        case "walk": return L10n.Routing.walk
        default: return L10n.Routing.transport
        }
    }

    var transferSummary: String {
        let transfers = backendAlternative?.transfers ?? max(0, displayLineCodes.count - 1)
        return L10n.Routing.transferCount(transfers)
    }

    var displayLineCodes: [String] {
        let descriptors = displayLineDescriptors
        if !descriptors.isEmpty {
            return descriptors.map(\.code)
        }

        return []
    }

    var displayLineDescriptors: [RouteLineDescriptor] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            let descriptors = steps
                .sorted { $0.order < $1.order }
                .compactMap(Self.lineDescriptor(for:))
            let unique = NSOrderedSet(array: descriptors.map(\.code)).array.compactMap { $0 as? String }
            return Array(unique.compactMap { code in descriptors.first(where: { $0.code == code }) }.prefix(4))
        }

        if let backendAlternative, !backendAlternative.lines.isEmpty {
            return Array(backendAlternative.lines.prefix(4)).map { RouteLineDescriptor(code: $0) }
        }

        let extracted = (route?.steps ?? []).compactMap { step -> String? in
            guard step.transportType == .transit else { return nil }
            let instruction = step.instructions.trimmingCharacters(in: .whitespacesAndNewlines)
            return Self.extractLineCode(from: instruction)
        }
        return (NSOrderedSet(array: extracted).array as? [String] ?? []).map { RouteLineDescriptor(code: $0) }
    }

    /// Ordered journey legs for a Google-style flow strip
    /// (🚶 → line → line → 🚶). Consecutive walk legs are merged into one.
    var legChips: [RouteLegChip] {
        guard let steps = backendAlternative?.steps, !steps.isEmpty else {
            return displayLineDescriptors.map { .line($0) }
        }
        var chips: [RouteLegChip] = []
        for step in steps.sorted(by: { $0.order < $1.order }) {
            if Self.isNonTransit(step.mode) {
                // Marches consécutives fusionnées, avec la durée CUMULÉE : le
                // vélo/la marche arrivent en manœuvres tour-par-tour (ORS), et
                // une puce par manœuvre donnait une file d'icônes identiques.
                if case .walk(let minutes) = chips.last {
                    chips[chips.count - 1] = .walk(minutes: minutes + step.durationMinutes)
                } else {
                    chips.append(.walk(minutes: step.durationMinutes))
                }
            } else if let descriptor = Self.lineDescriptor(for: step) {
                chips.append(.line(descriptor))
            }
        }
        // Une marche de moins d'une minute n'est pas une étape : on la tait.
        chips = chips.filter { chip in
            if case .walk(let minutes) = chip { return minutes >= 1 }
            return true
        }
        return chips.isEmpty ? displayLineDescriptors.map { .line($0) } : chips
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
        if let first = displayLineDescriptors.first {
            return first.fillColor
        }
        switch primaryModeKey {
        case "bike": return DS.Color.villo
        case "walk": return DS.Color.inkMute.opacity(0.45)
        default: return DS.Color.primary
        }
    }

    /// Court tag expliquant POURQUOI cette option diffère (ex. "Plus fiable",
    /// "Moins de marche") au lieu d'un simple delta de minutes — vient du
    /// label déjà calculé par le scoring backend (routeScoringService),
    /// localisé FR/NL. Nil seulement en fallback Apple-Maps-only (aucune
    /// alternative backend) : le caller retombe alors sur `deltaText`.
    var comparisonTag: String? {
        guard let backendAlternative else { return nil }
        if let reason = backendAlternative.localizedReasons?.first, !reason.isEmpty {
            // Le backend renvoie parfois une PHRASE (« Het snelste traject blijft te
            // prefereren… ») là où on attend un label de chip (« Snelste »,
            // « Minder overstappen »). Une phrase se tronque en « … blijft te… » et
            // n'apprend rien : au-delà de 24 caractères, on considère que ce n'est pas
            // un tag. La carte reste alors nue — sa durée en gros suffit.
            return reason.count <= 24 ? reason : nil
        }
        // Fallback : le badge de TYPE. On NE réutilise PAS `backendAlternative.label`
        // (le scoring backend le code en dur en FRANÇAIS — « Meilleur compromis »,
        // « Plus fiable » —, ce qui fuitait tel quel dans l'app néerlandaise). On mappe
        // le `type` technique vers une trad FR/NL. Les types numérotés
        // (« alternative_1 »…) ne sont pas une raison de choix → aucun tag.
        switch backendAlternative.type {
        case "best_overall":   return AppLocalizer.string("route.type.best", defaultValue: "Meilleur compromis")
        case "most_reliable":  return AppLocalizer.string("route.type.reliable", defaultValue: "Plus fiable")
        case "fastest":        return AppLocalizer.string("route.type.fastest", defaultValue: "Le plus rapide")
        case "least_walking":  return AppLocalizer.string("route.type.least_walking", defaultValue: "Moins de marche")
        case "bike":           return AppLocalizer.string("route.type.bike", defaultValue: "Alternative vélo")
        case "walk":           return AppLocalizer.string("route.type.walk", defaultValue: "Alternative à pied")
        default:               return nil
        }
    }

    var inlineSteps: [InlineRouteStepItem] {
        if let backendAlternative, let steps = backendAlternative.steps, !steps.isEmpty {
            let sorted = steps.sorted { $0.order < $1.order }
            return sorted.enumerated().map { index, step in
                InlineRouteStepItem(
                    icon: Self.inlineIcon(for: step),
                    title: Self.inlineTitle(for: step),
                    meta: Self.inlineMeta(for: step),
                    lineCode: Self.displayLine(for: step),
                    lineDescriptor: Self.lineDescriptor(for: step),
                    timingBadge: Self.inlineTimingBadge(for: step),
                    timingDetail: Self.inlineTimingDetail(for: step),
                    waitAfterMinutes: Self.waitMinutes(after: step, next: index + 1 < sorted.count ? sorted[index + 1] : nil),
                    // La STIB nomme ses arrêts en CAPITALES (« DE WAND ») ; on aligne
                    // sur la casse de Google (« Gare de Bockstael »). Vide hors STIB
                    // → aucun dépliant (géré côté vue).
                    intermediateStops: (step.intermediateStops ?? [])
                        .map { $0.capitalized(with: AppLocale.current) },
                    otherDepartures: Self.otherDepartures(from: step)
                )
            }
        }

        return detailSegments.compactMap { segment in
            guard let stepCard = segment.stepCard else { return nil }
            return InlineRouteStepItem(
                icon: segment.icon,
                title: stepCard.title,
                meta: [segment.stopCountText, segment.durationBadge].compactMap { $0 }.joined(separator: " · "),
                lineCode: stepCard.lineBadge?.code,
                lineDescriptor: stepCard.lineBadge,
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

    /// Les autres passages de la ligne à cet arrêt, prêts à afficher.
    /// Un passage sans heure n'est PAS affiché : mieux vaut une liste plus courte
    /// qu'une ligne vide dans le dépliant.
    private static func otherDepartures(from step: TransportRouteStepDTO) -> [RouteOtherDeparture] {
        (step.otherDepartures ?? []).compactMap { departure in
            guard let scheduledAt = departure.scheduledAt else { return nil }
            return RouteOtherDeparture(
                timeText: timeFormatter.string(from: scheduledAt),
                realtimeText: departure.realtimeMinutes.map(L10n.Routing.inMinutes),
                isThisTrip: departure.isThisTrip ?? false,
                scheduledAt: scheduledAt
            )
        }
    }

    private static func modeText(for step: TransportRouteStepDTO) -> String {
        switch step.mode.lowercased() {
        case "bus": return L10n.Routing.bus
        case "metro", "subway": return L10n.Routing.metro
        case "tram": return L10n.Routing.tram
        case "train", "rail": return AppLocalizer.string("routing.train", defaultValue: "Train")
        default: return L10n.Routing.line
        }
    }

    private static func waitText(_ minutes: Int) -> String {
        if minutes <= 0 { return L10n.Routing.now }
        return L10n.Routing.inMinutes(minutes)
    }

    private static func waitText(for date: Date) -> String {
        let minutes = Int(ceil(date.timeIntervalSince(Date()) / 60))
        if minutes <= 0 { return L10n.Routing.now }
        if minutes <= 90 { return waitText(minutes) }
        return L10n.Routing.atTime(timeFormatter.string(from: date))
    }

    /// Wait at the connection after `step`: the gap between this leg's arrival
    /// and the next leg's departure. Returns nil for short (<3 min) or unknown
    /// gaps so we only surface meaningful waits.
    private static func waitMinutes(after step: TransportRouteStepDTO, next: TransportRouteStepDTO?) -> Int? {
        guard let next,
              let arrival = step.realtimeArrivalAt ?? step.scheduledArrivalAt,
              let departure = next.realtimeDepartureAt ?? next.scheduledDepartureAt else { return nil }
        let minutes = Int((departure.timeIntervalSince(arrival) / 60).rounded())
        return minutes >= 3 ? minutes : nil
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

    private static func placeTitle(for step: MKRoute.Step, isLastLeg: Bool, destinationName: String, lineCode: String?, lineFallback: String = L10n.Routing.transport) -> String {
        if isLastLeg && step.transportType == .walking {
            return destinationName
        }
        if let lineCode {
            return L10n.Routing.line(lineCode)
        }
        switch step.transportType {
        case .walking: return L10n.Routing.walk
        case .transit: return lineFallback
        default: return L10n.Routing.routeStep
        }
    }

    private static func fallbackTitle(for step: MKRoute.Step, destinationName: String) -> String {
        switch step.transportType {
        case .walking:
            return L10n.Routing.walkTo(destinationName)
        case .transit:
            return L10n.Routing.takeNextTransport
        default:
            return L10n.Routing.followItinerary
        }
    }

    private static func subtitle(for step: MKRoute.Step) -> String {
        switch step.transportType {
        case .walking:
            return step.distance.distanceLabel
        case .transit:
            return L10n.Routing.transportStep
        default:
            return L10n.Routing.followItinerary
        }
    }

    private static func stopCountText(for step: MKRoute.Step) -> String? {
        guard step.transportType == .transit else { return nil }
        let estimatedStops = max(1, Int((step.distance / 350).rounded()))
        return L10n.Routing.stopCount(estimatedStops)
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
        if let line = Self.displayLine(for: step) {
            return L10n.Routing.line(line)
        }
        switch step.mode.lowercased() {
        case "bike": return L10n.Routing.bike
        case "walk": return L10n.Routing.walk
        default: return L10n.Routing.connection
        }
    }

    private static func transitSummary(from alternative: TransportAlternativeDTO) -> String {
        if !alternative.lines.isEmpty {
            return L10n.Routing.transitSummary(alternative.lines.count)
        }
        switch primaryMode(for: alternative) {
        case "bike": return L10n.Routing.bike.lowercased(with: AppLocale.current)
        case "walk": return L10n.Routing.walk.lowercased(with: AppLocale.current)
        default: return L10n.Routing.transport.lowercased(with: AppLocale.current)
        }
    }

    private static func displayLine(for step: TransportRouteStepDTO) -> String? {
        [step.displayLine, step.line]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .first { !$0.isEmpty }
    }

    private static func lineDescriptor(for step: TransportRouteStepDTO) -> RouteLineDescriptor? {
        guard let code = displayLine(for: step) else { return nil }
        return RouteLineDescriptor(
            code: code,
            operatorId: step.operatorId,
            colorHex: step.routeColor,
            textColorHex: step.routeTextColor
        )
    }

    private static func reliabilitySummary(from alternative: TransportAlternativeDTO) -> String {
        if alternative.transfers == 0 {
            return L10n.Routing.direct
        }
        return L10n.Routing.transferCount(alternative.transfers)
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
        if let descriptor = lineDescriptor(for: step) {
            return descriptor.fillColor
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

    /// Le backend émet `walk` / `bike` / `bus` / `tram` / `metro` / `train`
    /// (vérifié en prod). L'ancien `default: "tram.fill"` faisait donc porter
    /// une icône de TRAM au métro ET au train SNCB — factuellement faux, et
    /// visible : la ligne 6 (métro) s'affichait avec un tram.
    private static func iconName(for step: TransportRouteStepDTO) -> String? {
        switch step.mode.lowercased() {
        case "walk", "walking", "foot", "pedestrian": return "figure.walk"
        case "bike", "biking", "bicycle", "bicycling", "cycling": return "bicycle"
        case "bus": return "bus.fill"
        case "metro", "subway": return "tram.fill.tunnel"
        case "train", "rail": return "train.side.front.car"
        case "tram": return "tram.fill"
        default: return "tram.fill"
        }
    }

    private static func accentColor(for step: TransportRouteStepDTO) -> Color {
        if let descriptor = lineDescriptor(for: step) {
            return descriptor.fillColor
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
            return L10n.Routing.toward(arrivalStopName)
        }
        if let destination = step.destination, !destination.isEmpty {
            return L10n.Routing.direction(destination)
        }
        switch step.mode.lowercased() {
        case "bike": return L10n.Routing.bikeStep
        case "walk": return L10n.Routing.walkStep
        default: return L10n.Routing.transportStep
        }
    }

    private static func summaryText(for step: TransportRouteStepDTO) -> String {
        if let line = displayLine(for: step) {
            return L10n.Routing.line(line)
        }
        switch step.mode.lowercased() {
        case "bike": return L10n.Routing.bikeToNextStep
        case "walk": return L10n.Routing.walkInProgress
        default: return L10n.Routing.transportInProgress
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
        if displayLine(for: step) != nil {
            let start = step.stopName ?? L10n.Routing.departure
            let end = step.arrivalStopName ?? step.destination ?? L10n.Routing.arrival
            return "\(start) → \(end)"
        }

        if step.mode.lowercased() == "walk" {
            if let target = step.stopName ?? step.arrivalStopName ?? step.destination {
                return L10n.Routing.walkTo(target)
            }
            return L10n.Routing.walking
        }

        if step.mode.lowercased() == "bike" {
            return L10n.Routing.bikeTo(step.arrivalStopName ?? step.destination ?? L10n.Routing.destination)
        }

        return step.destination ?? L10n.Routing.connection
    }

    private static func inlineMeta(for step: TransportRouteStepDTO) -> String {
        var parts: [String] = []
        if let stops = step.stopsCount {
            parts.append(L10n.Routing.stopCount(stops))
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
        // Les horaires départ→arrivée vivent déjà sur la ligne `timingDetail` juste
        // au-dessus (« Realtime 17:52 → 18:04 »). Les répéter ici produisait
        // « 6 haltes · 12 MIN · 17:52→18:04 » : le même créneau deux fois. On ne
        // garde en meta que le nombre d'arrêts et la durée.
        return parts.joined(separator: " · ")
    }

    private static func inlineTimingBadge(for step: TransportRouteStepDTO) -> String? {
        guard displayLine(for: step) != nil else { return nil }
        if let minutes = step.realtimeDepartureMinutes {
            return waitText(minutes)
        }
        if let realtimeDepartureAt = step.realtimeDepartureAt {
            return waitText(for: realtimeDepartureAt)
        }
        if let scheduledDepartureAt = step.scheduledDepartureAt {
            return L10n.Routing.scheduledAt(timeFormatter.string(from: scheduledDepartureAt)).capitalized(with: AppLocale.current)
        }
        return nil
    }

    private static func inlineTimingDetail(for step: TransportRouteStepDTO) -> String? {
        let departureDate = step.realtimeDepartureAt ?? step.scheduledDepartureAt
        let arrivalDate = step.realtimeArrivalAt ?? step.scheduledArrivalAt
        guard let departureDate else { return nil }

        let source = (step.realtimeDepartureAt != nil || step.realtimeDepartureMinutes != nil) ? L10n.Routing.realtime : L10n.Routing.scheduled
        let departure = timeFormatter.string(from: departureDate)
        if let arrivalDate {
            return L10n.Routing.timingDetail(source, departure: departure, arrival: timeFormatter.string(from: arrivalDate))
        }
        return L10n.Routing.departureDetail(source, departure: departure)
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
