import SwiftUI
import MapKit

private enum StopDetailTab: String, CaseIterable, Identifiable {
    case live
    case lines
    case schedule
    case around

    var id: String { rawValue }
}

private struct GroupedStopPassage: Identifiable {
    var id: String { "\(line)-\(destination)" }
    let line: String
    let destination: String
    let departures: [TransportDepartureDTO]
}

private struct StopDetailCatalogRoute: Decodable {
    let lineId: String
    let destinationFr: String?
    let destinationNl: String?
    let stops: [StopDetailCatalogRouteStop]
}

private struct StopDetailCatalogRouteStop: Decodable {
    let mergedStopId: Int
    let physicalStopId: String?
}

private struct StopDetailMergedCatalog: Decodable {
    let lines: [String: StopDetailCatalogRoute]
}

private enum StopDetailCatalogStore {
    private static var cached: StopDetailMergedCatalog?

    static func destinations(stopBackendId: String, stopId: String?, lineIds: [String]) -> [GroupedStopPassage] {
        guard let catalog = loadCatalog() else { return [] }

        let normalizedLines = Set(lineIds.map(normalizedLineNumber))
        guard !normalizedLines.isEmpty else { return [] }

        let rows = catalog.lines.values.compactMap { route -> GroupedStopPassage? in
            let normalizedLine = normalizedLineNumber(route.lineId)
            guard normalizedLines.contains(normalizedLine) else { return nil }

            let servesStop = route.stops.contains { stop in
                String(stop.mergedStopId) == stopBackendId || (stopId != nil && stop.physicalStopId == stopId)
            }
            guard servesStop else { return nil }

            let destination = [route.destinationFr, route.destinationNl]
                .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
                .first(where: { !$0.isEmpty }) ?? "Destination à confirmer"

            return GroupedStopPassage(line: normalizedLine, destination: destination, departures: [])
        }

        return rows
            .uniqued(by: \.id)
            .sorted { lhs, rhs in
                if lhs.line == rhs.line {
                    return lhs.destination.localizedStandardCompare(rhs.destination) == .orderedAscending
                }
                if let left = Int(lhs.line), let right = Int(rhs.line) {
                    return left < right
                }
                return lhs.line.localizedStandardCompare(rhs.line) == .orderedAscending
        }
    }

    private static func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private static func loadCatalog() -> StopDetailMergedCatalog? {
        if let cached { return cached }
        guard let url = Bundle.main.url(forResource: "stib-static-catalog-merged", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(StopDetailMergedCatalog.self, from: data) else {
            return nil
        }
        cached = decoded
        return decoded
    }
}

private extension Array {
    func uniqued<Key: Hashable>(by keyPath: KeyPath<Element, Key>) -> [Element] {
        var seen = Set<Key>()
        return filter { seen.insert($0[keyPath: keyPath]).inserted }
    }
}

struct ArretDetailPage: View {
    @EnvironmentObject private var session: AuthSession
    let stopSummary: TransportStopSummaryDTO
    let stopDetail: TransportStopDTO?
    let isLoading: Bool
    let userCoordinate: CLLocationCoordinate2D?
    let nearbyStops: [TransportStopSummaryDTO]
    let nearbyVilloStations: [(station: VilloStation, distanceMeters: Int)]
    let communitySignalements: [SignalementDTO]
    let onDismiss: () -> Void
    let onOpenLine: (String) -> Void
    let selectedLineRoute: String?
    let onSelectLineRoute: (String) -> Void
    let onOpenStop: (TransportStopSummaryDTO) -> Void
    let onReport: () -> Void

    @State private var selectedTab: StopDetailTab = .live
    @State private var selectedLineFilter: String? = nil
    @State private var isFavorite = false
    @State private var isUpdatingFavorite = false
    @State private var selectedDisruption: TransportIncidentDTO?

    // Onglet Horaires — théoriques GTFS chargés à la demande.
    @State private var scheduleData: StibStopSchedule?
    @State private var isLoadingSchedule = false
    @State private var selectedScheduleDayType: String = StibScheduleService.currentDayType()

    private var effectiveStop: TransportStopSummaryDTO {
        stopDetail?.stop ?? stopSummary
    }

    private var stopCoordinate: CLLocationCoordinate2D? {
        guard let latitude = effectiveStop.latitude, let longitude = effectiveStop.longitude else { return nil }
        return CLLocationCoordinate2D(latitude: latitude, longitude: longitude)
    }

    // Only show the "Signaler" CTA if the user is actually near this stop.
    // Matches QuickReportSheet's 120 m auto-selection radius — otherwise we'd
    // let people file reports for a stop they're nowhere near (the sheet would
    // still pre-fill it because the stop is in their bootstrap nearbyStops).
    private var canReportFromHere: Bool {
        guard let userCoordinate, let stopCoordinate else { return false }
        let user = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
        let stop = CLLocation(latitude: stopCoordinate.latitude, longitude: stopCoordinate.longitude)
        return user.distance(from: stop) <= 120
    }

    private var severityColor: Color {
        switch stopDetail?.severity {
        case "critical", "major":
            return DS.Color.statusMajor
        case "minor":
            return DS.Color.statusMinor
        default:
            return DS.Color.statusOK
        }
    }

    private var severityLabel: String {
        TransportViewAdapters.localizedSeverityLabel(
            severity: stopDetail?.severity,
            fallback: stopDetail?.label?.fr ?? "Service normal"
        )
    }

    private var stopSubline: String {
        if let stopId = effectiveStop.stopId {
            return "ARRÊT · \(stopId)"
        }
        return "ARRÊT"
    }

    private var servedLines: [String] {
        var seen = Set<String>()
        let merged = effectiveStop.lines
            + (stopDetail?.nextDepartures.map(\.line) ?? [])
        return merged.compactMap { line in
            let normalized = Self.normalizedLineNumber(line)
            guard !normalized.isEmpty, seen.insert(normalized).inserted else { return nil }
            return normalized
        }
        .sorted { left, right in
            if let leftInt = Int(left), let rightInt = Int(right) { return leftInt < rightInt }
            return left.localizedStandardCompare(right) == .orderedAscending
        }
    }

    private var groupedPassages: [GroupedStopPassage] {
        guard let stopDetail else { return [] }
        let allowedLines = Set(servedLines.map(Self.normalizedLineNumber).filter { !$0.isEmpty })
        let filtered = stopDetail.nextDepartures.filter { departure in
            let line = Self.normalizedLineNumber(departure.line)
            guard allowedLines.isEmpty || allowedLines.contains(line) else { return false }
            return selectedLineFilter == nil || Self.normalizedLineNumber(selectedLineFilter ?? "") == line
        }
        let groups = Dictionary(grouping: filtered) { departure in
            "\(departure.line)::\(departure.destination ?? "Direction inconnue")"
        }

        return groups.values
            .map { departures in
                GroupedStopPassage(
                    line: departures.first?.line ?? "—",
                    destination: departures.first?.destination ?? "Direction inconnue",
                    departures: departures.sorted { $0.minutes < $1.minutes }
                )
            }
            .sorted { lhs, rhs in
                // Tri par n° de ligne…
                if let left = Int(lhs.line), let right = Int(rhs.line), left != right {
                    return left < right
                }
                if lhs.line != rhs.line {
                    return lhs.line.localizedStandardCompare(rhs.line) == .orderedAscending
                }
                // FIX — …puis par destination pour DÉPARTAGER les 2 sens d'une
                // même ligne. Sans ce tiebreak, le tri n'est pas total et
                // l'ordre des sens dépendait de Dictionary.values (non
                // déterministe) → les directions « tremblaient » et
                // s'échangeaient à chaque rafraîchissement des horaires.
                return lhs.destination.localizedCaseInsensitiveCompare(rhs.destination) == .orderedAscending
            }
    }

    private static func normalizedLineNumber(_ value: String) -> String {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T"), trimmed.dropFirst().allSatisfy(\.isNumber) {
            return String(trimmed.dropFirst())
        }
        return trimmed
    }

    private var passagesAvailabilityText: String {
        if isLoading {
            return "Chargement des passages..."
        }

        guard let stopDetail else {
            return "Passages indisponibles pour le moment."
        }

        if !stopDetail.nextDepartures.isEmpty {
            let hasRealtime = stopDetail.nextDepartures.contains { $0.source != "scheduled" }
            let hasScheduled = stopDetail.nextDepartures.contains { $0.source == "scheduled" }
            if hasRealtime && hasScheduled {
                return "Temps réel complété par l'horaire prévu."
            }
            if hasRealtime {
                return "Temps réel STIB disponible."
            }
            if hasScheduled {
                return "Temps réel indisponible, horaires prévus affichés."
            }
        }

        if let message = stopDetail.officialDataMessage, !message.isEmpty {
            return message
        }

        switch stopDetail.officialDataStatus {
        case "unavailable":
            return "Passages indisponibles: source STIB temporairement inaccessible."
        case "limited":
            return "Données STIB limitées: derniers horaires fiables indisponibles."
        default:
            return "Aucun passage prévu pour le moment."
        }
    }

    private var lineDestinations: [GroupedStopPassage] {
        let catalogDestinations = StopDetailCatalogStore.destinations(
            stopBackendId: effectiveStop.id,
            stopId: effectiveStop.stopId,
            lineIds: servedLines
        )
        if !catalogDestinations.isEmpty {
            return catalogDestinations
        }

        if !groupedPassages.isEmpty {
            return groupedPassages
        }

        return servedLines.map {
            GroupedStopPassage(line: $0, destination: "Destination à confirmer", departures: [])
        }
    }

    private var disruptions: [TransportIncidentDTO] {
        stopDetail?.activeIncidents ?? []
    }

    // Community signalements scoped to this stop (most-recent first).
    // Match by the populated arret name — same predicate as the report sheet.
    // Also discards reports whose time-decayed confidence has rotted below
    // 0.18 (≈ Faible threshold), so a 6-hour-old "incivilité" doesn't keep
    // cluttering the stop card.
    private var stopCommunitySignalements: [SignalementDTO] {
        let stopName = effectiveStop.name
        return communitySignalements
            .filter { s in
                guard s.status != "resolved" else { return false }
                guard s.liveConfidence >= 0.18 else { return false }
                if case .populated(let arret) = s.arretId {
                    return arret.nom == stopName
                }
                return false
            }
            .sorted { ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast) }
    }

    /// Signalements on stops that are PROPAGATION-impacted by this stop's
    /// line(s): same line(s) and within a 1.5 km radius (rough proxy for
    /// the "±3 stops upstream/downstream" zone described in the Waze 2.0
    /// design doc). Excluded if already in `stopCommunitySignalements`.
    private var linePropagatedSignalements: [SignalementDTO] {
        guard let stopLat = effectiveStop.latitude, let stopLng = effectiveStop.longitude else { return [] }
        let stopCoord = CLLocation(latitude: stopLat, longitude: stopLng)
        let stopName = effectiveStop.name.uppercased()
        let lineSet = Set(effectiveStop.lines.map { $0.uppercased() })
        return communitySignalements
            .filter { s in
                guard s.status != "resolved" else { return false }
                guard s.liveConfidence >= 0.18 else { return false }
                // Same line as this stop
                guard lineSet.contains(s.ligne.uppercased()) else { return false }
                // Skip reports already attached to THIS stop
                if case .populated(let arret) = s.arretId, arret.nom.uppercased() == stopName {
                    return false
                }
                // Has coordinates within 1.5 km
                guard let lat = s.latitude, let lng = s.longitude else { return false }
                let dist = stopCoord.distance(from: CLLocation(latitude: lat, longitude: lng))
                return dist <= 1500
            }
            .sorted { ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast) }
    }

    private var signalementsLastHourCount: Int {
        let cutoff = Date().addingTimeInterval(-3600)
        return stopCommunitySignalements.filter { ($0.dateSignalement ?? .distantPast) >= cutoff }.count
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    topBar

                    titleBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 8)

                    if !disruptions.isEmpty {
                        disruptionBanner
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    if !stopCommunitySignalements.isEmpty {
                        communityReportsSection
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }

                    if !linePropagatedSignalements.isEmpty {
                        propagatedReportsSection
                            .padding(.horizontal, 20)
                            .padding(.top, 10)
                    }

                    segmentedTabs
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    tabContent
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    // Carte déplacée EN BAS (avant elle ouvrait la page) : on
                    // commence par le nom + les passages, la carte vient après.
                    heroMap
                        .padding(.horizontal, 20)
                        .padding(.top, 20)

                    Text("Mise à jour en direct · STIB-MIVB")
                        .font(DS.Font.eyebrow)
                        .foregroundStyle(DS.Color.inkMute.opacity(0.75))
                        .padding(.top, 20)

                    Color.clear.frame(height: canReportFromHere ? 96 : 28)
                }
            }
            .modifier(PaperGrainBackground())

            stickyCTA
        }
        .task(id: session.currentUser?.id) {
            syncFavoriteState()
        }
        .sheet(item: $selectedDisruption) { disruption in
            StopIncidentDetailSheet(
                incident: disruption,
                stopName: effectiveStop.name,
                onOpenLine: { line in
                    selectedDisruption = nil
                    onOpenLine(line)
                }
            )
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    private var topBar: some View {
        HStack {
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            HStack(spacing: 8) {
                iconButton(systemName: isFavorite ? "star.fill" : "star", tint: isFavorite ? DS.Color.primary : DS.Color.ink) {
                    Task { await toggleFavorite() }
                }
                .disabled(isUpdatingFavorite || session.currentUser == nil)
                iconButton(systemName: "square.and.arrow.up") {
                    shareStop()
                }
            }
        }
        .padding(.horizontal, 20)
        .padding(.top, 16)
    }

    private var heroMap: some View {
        let region = MKCoordinateRegion(
            center: stopCoordinate ?? CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517),
            span: MKCoordinateSpan(latitudeDelta: 0.005, longitudeDelta: 0.005)
        )

        return ZStack(alignment: .bottomTrailing) {
            Map(position: .constant(.region(region))) {
                Annotation("", coordinate: stopCoordinate ?? CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)) {
                    Circle()
                        .fill(DS.Color.primary)
                        .frame(width: 14, height: 14)
                        .overlay(Circle().stroke(DS.Color.ink, lineWidth: 2))
                }
            }
            .mapControls { }
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity)
            .aspectRatio(16 / 7, contentMode: .fit)
            .overlay(
                LinearGradient(
                    colors: [DS.Color.ink.opacity(0.10), .clear],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )

            Button(action: openDirections) {
                HStack(spacing: 6) {
                    Image(systemName: "location.north.line")
                        .font(.system(size: 11, weight: .bold))
                    Text("Ouvrir la carte")
                        .font(DS.Font.monoSmall.weight(.semibold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .buttonStyle(.plain)
            .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.ink.opacity(0.25), lineWidth: 1.5)
        )
    }

    private var titleBlock: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(effectiveStop.name)
                .font(DS.Font.displayH2)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text(stopSubline)
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.inkMute)
                .textCase(.uppercase)
                .tracking(1.0)

            HStack(spacing: 8) {
                statusPill(color: severityColor, text: severityLabel)
                metaPill(icon: "figure.roll", text: "PMR")
                if let villo = nearbyVilloStations.first {
                    metaPill(icon: "bicycle", text: "Villo \(villo.station.availableBikes)")
                }
            }
        }
        // Sans ça, le VStack se dimensionne à son contenu et se retrouve CENTRÉ
        // → le nom "ANCRE" paraissait décalé vers la droite alors que les tabs /
        // chips / passages sont collés à gauche. On force la pleine largeur +
        // alignement leading pour aligner le header sur la même grille (x=20).
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var disruptionBanner: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 11))
                Text("Perturbation · cet arrêt")
                    .font(DS.Font.eyebrow)
            }
            .foregroundStyle(DS.Color.statusMajor)

            ForEach(disruptions.prefix(3)) { disruption in
                Button {
                    selectedDisruption = disruption
                } label: {
                    HStack(alignment: .top, spacing: 8) {
                        if let line = disruption.line, !line.isEmpty {
                            LineBadge(line: line, size: .sm)
                        }
                        Text(disruption.description ?? disruption.type ?? "Perturbation en cours")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(2)
                        Spacer(minLength: 8)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.statusMajor.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.Color.statusMajor)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private var communityReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "bubble.left.and.bubble.right.fill")
                    .font(.system(size: 11))
                Text("Signalements communauté")
                    .font(DS.Font.eyebrow)
                Spacer()
                Text(lastHourCountText)
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.community)
            }
            .foregroundStyle(DS.Color.community)

            VStack(spacing: 6) {
                ForEach(stopCommunitySignalements.prefix(4)) { signalement in
                    communityReportRow(signalement)
                }
            }

            if stopCommunitySignalements.count > 4 {
                Text("+\(stopCommunitySignalements.count - 4) autres")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.community.opacity(0.08))
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(DS.Color.community)
                .frame(width: 2)
        }
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private var lastHourCountText: String {
        let count = signalementsLastHourCount
        if count == 0 {
            return "Aucun · 1 h"
        }
        return "\(count) · 1 h"
    }

    /// "À proximité sur la ligne" — propagated section showing community
    /// reports on the same line within 1.5 km. Visually de-emphasised (no
    /// left stripe, lighter background) so the user understands these are
    /// CONTEXT, not direct reports of this stop.
    private var propagatedReportsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "arrow.triangle.branch")
                    .font(.system(size: 11))
                Text("Sur la ligne · à proximité")
                    .font(DS.Font.eyebrow)
                Spacer()
                Text("\(linePropagatedSignalements.count)")
                    .font(DS.Font.eyebrow)
            }
            .foregroundStyle(DS.Color.inkMute)

            VStack(spacing: 6) {
                ForEach(linePropagatedSignalements.prefix(3)) { signalement in
                    communityReportRow(signalement, showsArretName: true)
                }
            }

            if linePropagatedSignalements.count > 3 {
                Text("+\(linePropagatedSignalements.count - 3) autres sur la ligne")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper2.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
    }

    private func communityReportRow(_ signalement: SignalementDTO, showsArretName: Bool = false) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LineBadge(line: signalement.ligne, size: .sm)
            VStack(alignment: .leading, spacing: 2) {
                Text(signalement.displayTypeProbleme)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                if showsArretName,
                   case .populated(let arret) = signalement.arretId {
                    Text(arret.nom.uppercased())
                        .font(.system(size: 9.5, weight: .bold, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
                HStack(spacing: 6) {
                    Text(signalement.freshnessLabel)
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DS.Color.inkMute)
                    confidenceDot(for: signalement)
                }
            }
            Spacer(minLength: 8)
            if let confirmations = signalement.community?.confirmations, confirmations > 0 {
                HStack(spacing: 3) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 10))
                    Text("\(confirmations)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                }
                .foregroundStyle(DS.Color.community)
            }
        }
    }

    /// Small colored dot indicating the live-decayed confidence band.
    /// Green = "Fraîche" (fresh + high-confidence), amber = "Modérée", grey
    /// = "Faible". Helps the user judge how trustworthy each report is
    /// without doing the time-math themselves.
    private func confidenceDot(for signalement: SignalementDTO) -> some View {
        HStack(spacing: 3) {
            Circle()
                .fill(confidenceDotColor(for: signalement))
                .frame(width: 5, height: 5)
            Text(signalement.liveConfidenceLabel)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
        }
    }

    private func confidenceDotColor(for signalement: SignalementDTO) -> Color {
        switch signalement.liveConfidence {
        case 0.7...: return DS.Color.statusOK
        case 0.35..<0.7: return DS.Color.statusMinor
        default: return DS.Color.inkMute.opacity(0.5)
        }
    }

    private var segmentedTabs: some View {
        HStack(spacing: 4) {
            ForEach(StopDetailTab.allCases) { tab in
                Button {
                    selectedTab = tab
                } label: {
                    Text(tabTitle(tab))
                        .font(DS.Font.monoSmall.weight(.bold))
                        .textCase(.uppercase)
                        .tracking(1.2)
                        .foregroundStyle(selectedTab == tab ? DS.Color.paper : DS.Color.inkMute)
                        .frame(maxWidth: .infinity, minHeight: 36)
                        .background(selectedTab == tab ? DS.Color.ink : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.Color.paper2)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .live:
            liveTab
        case .lines:
            linesTab
        case .schedule:
            scheduleTab
        case .around:
            aroundTab
        }
    }

    private var liveTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            if !servedLines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        filterChip(label: "Tout", active: selectedLineFilter == nil) {
                            selectedLineFilter = nil
                        }
                        ForEach(servedLines, id: \.self) { line in
                            filterChip(
                                label: line,
                                active: selectedLineFilter == line || (selectedLineFilter == nil && selectedLineRoute == line),
                                lineColor: TransitLinePalette.fill(for: line),
                                lineForeground: TransitLinePalette.foreground(for: line)
                            ) {
                                selectedLineFilter = selectedLineFilter == line ? nil : line
                                onSelectLineRoute(line)
                            }
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            HStack {
                Label("Prochains passages", systemImage: "clock")
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                if !groupedPassages.isEmpty {
                    Text(groupedPassages.flatMap(\.departures).contains { $0.source == "scheduled" } ? "PRÉVU" : "TEMPS RÉEL")
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(groupedPassages.flatMap(\.departures).contains { $0.source == "scheduled" } ? DS.Color.statusMinor : DS.Color.statusOK)
                }
            }

            Rectangle()
                .fill(DS.Color.ink)
                .frame(height: 2)

            if isLoading {
                StopSkeletonRows()
            } else if groupedPassages.isEmpty {
                Text(passagesAvailabilityText)
                    .font(DS.Font.body)
                    .italic()
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(groupedPassages) { group in
                        Button {
                            onOpenLine(group.line)
                        } label: {
                            passageRow(group)
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(height: 1)
                    }
                }
            }
        }
    }

    /// Converts raw minutes to a display string.
    /// < 60 min → "X min" ; ≥ 60 min → actual arrival time "HH:mm".
    private func formatPassageMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "‹1 min" }
        guard minutes < 60 else {
            let arrival = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: arrival)
        }
        return "\(minutes) min"
    }

    private func passageRow(_ group: GroupedStopPassage) -> some View {
        let next = group.departures.first
        let imminent = (next?.minutes ?? 99) <= 1
        let isFarAway = (next?.minutes ?? 0) >= 60

        return HStack(spacing: 12) {
            LineBadge(line: group.line, size: .lg)
            VStack(alignment: .leading, spacing: 2) {
                Text("Direction")
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.inkMute)
                Text("→ \(group.destination)")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                if let next {
                    let source = next.source == "scheduled" ? "prévu" : "temps réel"
                    Text("\(source) à \(formatPassageMinutes(next.minutes))")
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                    if let delay = next.delayMinutes, delay > 2 {
                        Text("retard +\(delay) min")
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.statusMajor)
                    }
                }
            }
            Spacer()
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                if let next {
                    if isFarAway {
                        // Show clock time instead of absurd minute count
                        Text(formatPassageMinutes(next.minutes))
                            .font(.system(size: 18, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Color.inkMute)
                    } else {
                        Text(next.minutes == 0 ? "‹1" : "\(next.minutes)")
                            .font(.system(size: 20, weight: .bold))
                            .foregroundStyle(imminent ? DS.Color.primary : DS.Color.ink)
                            .monospacedDigit()
                        Text("min")
                            .font(.system(size: 10))
                            .foregroundStyle(DS.Color.inkMute)
                            .textCase(.uppercase)
                            .tracking(1.2)
                        ForEach(Array(group.departures.dropFirst().prefix(2)), id: \.id) { departure in
                            Text("+\(departure.minutes)")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                } else {
                    Text("—")
                        .font(DS.Font.bodySmall)
                        .italic()
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private var linesTab: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Lignes & destinations")
                .font(DS.Font.eyebrow)
                .foregroundStyle(DS.Color.ink)
            Rectangle().fill(DS.Color.ink).frame(height: 2)

            if lineDestinations.isEmpty {
                Text("Aucune ligne référencée.")
                    .font(DS.Font.body)
                    .italic()
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else {
                VStack(spacing: 0) {
                    ForEach(lineDestinations) { item in
                        Button {
                            onOpenLine(item.line)
                        } label: {
                            HStack(spacing: 12) {
                                LineBadge(line: item.line, size: .lg)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Vers")
                                        .font(DS.Font.eyebrow)
                                        .foregroundStyle(DS.Color.inkMute)
                                    Text(item.destination)
                                        .font(DS.Font.bodyBold)
                                        .foregroundStyle(DS.Color.ink)
                                        .lineLimit(1)
                                }
                                Spacer()
                                Image(systemName: "arrow.right")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(height: 1)
                    }
                }
            }
        }
    }

    // MARK: - Schedule tab (horaires théoriques STIB)

    private var scheduleTab: some View {
        VStack(alignment: .leading, spacing: 16) {
            scheduleDayPicker

            if isLoadingSchedule && scheduleData == nil {
                HStack {
                    Spacer()
                    ProgressView()
                        .tint(DS.Color.ink)
                    Spacer()
                }
                .padding(.vertical, 30)
            } else if let lines = scheduleData?.lines, !lines.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(lines) { lineSchedule in
                        scheduleLineCard(lineSchedule)
                    }
                }
            } else if scheduleData != nil {
                emptyScheduleNotice
            }
        }
        .task(id: effectiveStop.id) {
            await loadScheduleIfNeeded()
        }
    }

    private var scheduleDayPicker: some View {
        HStack(spacing: 6) {
            ForEach(["weekday", "saturday", "sunday"], id: \.self) { dayType in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    selectedScheduleDayType = dayType
                } label: {
                    Text(scheduleDayLabel(dayType))
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1)
                        .foregroundStyle(selectedScheduleDayType == dayType ? DS.Color.paper : DS.Color.ink)
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(selectedScheduleDayType == dayType ? DS.Color.ink : DS.Color.paper2)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func scheduleLineCard(_ lineSchedule: StibScheduleLine) -> some View {
        let times = lineSchedule.departures(for: selectedScheduleDayType)
        let nextIndex = nextDepartureIndex(in: times)
        return VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                LineBadge(line: lineSchedule.line, size: .sm)
                if let destination = lineSchedule.destination {
                    Text("→ \(destination)")
                        .font(DS.Font.bodySmall.weight(.semibold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if selectedScheduleDayType == StibScheduleService.currentDayType(),
                   let nextIndex, times.indices.contains(nextIndex) {
                    Text("Prochain · \(times[nextIndex])")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundStyle(DS.Color.primary)
                }
            }

            if times.isEmpty {
                Text("Pas de passages prévus.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            } else {
                // LazyVGrid : grille adaptive 5-6 colonnes selon largeur, plus
                // simple qu'un FlowLayout custom et performant pour 50+ horaires.
                let columns = [GridItem(.adaptive(minimum: 56), spacing: 6)]
                LazyVGrid(columns: columns, alignment: .leading, spacing: 6) {
                    ForEach(Array(times.enumerated()), id: \.offset) { idx, time in
                        Text(time)
                            .font(DS.Font.monoSmall.weight(.semibold))
                            .foregroundStyle(idx == nextIndex ? DS.Color.paper : DS.Color.ink)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 5)
                            .background(idx == nextIndex ? DS.Color.primary : DS.Color.paper2)
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
            }
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private var emptyScheduleNotice: some View {
        VStack(spacing: 6) {
            Image(systemName: "clock.badge.questionmark")
                .font(.system(size: 26, weight: .light))
                .foregroundStyle(DS.Color.inkMute)
            Text("Horaires théoriques non disponibles pour cet arrêt.")
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
            Text("Consulte l'onglet « Temps réel » pour les prochains passages.")
                .font(.system(size: 11))
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 30)
    }

    private func scheduleDayLabel(_ dayType: String) -> String {
        switch dayType {
        case "weekday":  return "LUN-VEN"
        case "saturday": return "SAMEDI"
        case "sunday":   return "DIMANCHE"
        default:         return dayType.uppercased()
        }
    }

    /// Index du prochain passage à venir dans `times` selon l'heure
    /// courante Bruxelles. nil si aucun futur (tous les passages sont
    /// passés) ou si on n'est pas sur le bon dayType.
    private func nextDepartureIndex(in times: [String]) -> Int? {
        guard selectedScheduleDayType == StibScheduleService.currentDayType() else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        let now = calendar.dateComponents([.hour, .minute], from: Date())
        let nowMinutes = (now.hour ?? 0) * 60 + (now.minute ?? 0)
        for (idx, time) in times.enumerated() {
            let parts = time.split(separator: ":").compactMap { Int($0) }
            guard parts.count == 2 else { continue }
            let mins = parts[0] * 60 + parts[1]
            if mins >= nowMinutes { return idx }
        }
        return nil
    }

    @MainActor
    private func loadScheduleIfNeeded() async {
        guard scheduleData == nil, !isLoadingSchedule else { return }
        isLoadingSchedule = true
        defer { isLoadingSchedule = false }
        scheduleData = await StibScheduleService.fetch(stopId: effectiveStop.id)
    }

    private var aroundTab: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                Label("Arrêts à proximité", systemImage: "figure.walk")
                    .font(DS.Font.eyebrow)
                    .foregroundStyle(DS.Color.ink)
                Rectangle().fill(DS.Color.ink).frame(height: 2)

                if nearbyStops.isEmpty {
                    Text("Aucun arrêt voisin à moins de 350 m.")
                        .font(DS.Font.body)
                        .italic()
                        .foregroundStyle(DS.Color.inkMute)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 24)
                } else {
                    VStack(spacing: 0) {
                        ForEach(nearbyStops) { stop in
                            Button {
                                onOpenStop(stop)
                            } label: {
                                nearbyRow(stop)
                            }
                            .buttonStyle(.plain)
                            Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(height: 1)
                        }
                    }
                }
            }

            if !nearbyVilloStations.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Label("Villo! à proximité", systemImage: "bicycle")
                        .font(DS.Font.eyebrow)
                        .foregroundStyle(DS.Color.ink)
                    Rectangle().fill(DS.Color.ink).frame(height: 2)

                    VStack(spacing: 0) {
                        ForEach(Array(nearbyVilloStations.prefix(3)), id: \.station.id) { item in
                            villoRow(item.station, distanceMeters: item.distanceMeters)
                            Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(height: 1)
                        }
                    }
                }
            }
        }
    }

    private func nearbyRow(_ stop: TransportStopSummaryDTO) -> some View {
        HStack(spacing: 12) {
            VStack(alignment: .trailing, spacing: 0) {
                Text("\(stopDistanceMeters(to: stop))")
                    .font(.system(size: 15, weight: .bold))
                    .monospacedDigit()
                    .foregroundStyle(DS.Color.ink)
                Text("m")
                    .font(.system(size: 9))
                    .textCase(.uppercase)
                    .tracking(1.2)
                    .foregroundStyle(DS.Color.inkMute)
            }
            .frame(width: 40, alignment: .trailing)

            VStack(alignment: .leading, spacing: 4) {
                Text(stop.name)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                if !stop.lines.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(Array(stop.lines.prefix(6)), id: \.self) { line in
                            LineBadge(line: line, size: .sm)
                        }
                    }
                }
            }

            Spacer()

            Image(systemName: "arrow.right")
                .font(.system(size: 12))
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(.vertical, 12)
        .contentShape(Rectangle())
    }

    private func villoRow(_ station: VilloStation, distanceMeters: Int) -> some View {
        let bg: Color =
            !station.isOperational ? DS.Color.inkMute :
            station.availableBikes == 0 ? DS.Color.statusMajor :
            station.availableBikes <= 2 ? DS.Color.statusMinor :
            DS.Color.statusOK

        return HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .fill(bg)
                    .frame(width: 40, height: 40)
                Text(station.isOperational ? "\(station.availableBikes)" : "×")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.paper)
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(station.displayName)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Text(station.isOperational
                     ? "\(station.availableBikes) vélos · \(station.availableBikeStands) places · \(distanceMeters) m"
                     : "Fermée · \(distanceMeters) m")
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer()
        }
        .padding(.vertical, 12)
    }

    @ViewBuilder
    private var stickyCTA: some View {
        // Plus de bouton "Itinéraire" flottant ici (la carte est désormais en
        // bas de la page). On ne garde QUE "Signaler" quand on est à proximité
        // de l'arrêt ; sinon rien ne flotte au-dessus de la carte.
        if canReportFromHere {
            Button(action: onReport) {
                Label(L10n.StopDetail.report, systemImage: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.primaryForeground)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(DS.Color.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 16)
            .padding(.bottom, 12)
            .shadow(DS.Shadow.floating)
        }
    }

    private func tabTitle(_ tab: StopDetailTab) -> String {
        switch tab {
        case .live:
            return L10n.StopDetail.realtime
        case .lines:
            return L10n.StopDetail.lines(servedLines.count)
        case .schedule:
            return L10n.StopDetail.schedules
        case .around:
            return L10n.StopDetail.around
        }
    }

    private func statusPill(color: Color, text: String) -> some View {
        HStack(spacing: 6) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(text)
                .font(DS.Font.monoSmall.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(color)
        .background(color.opacity(0.10))
        .overlay(Capsule().stroke(color.opacity(0.4), lineWidth: 1.5))
        .clipShape(Capsule())
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).font(.system(size: 10))
            Text(text)
                .font(DS.Font.monoSmall.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.2)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .foregroundStyle(DS.Color.ink)
        .overlay(Capsule().stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5))
        .clipShape(Capsule())
    }

    /// Chip de filtre. Pour les chips de LIGNE on passe `lineColor` (couleur
    /// officielle STIB) + `lineForeground` (couleur texte contrastée) : la
    /// pastille prend la couleur de la ligne — fond teinté + bordure colorée au
    /// repos, fond plein quand active. "Tout" reste neutre (noir/blanc).
    private func filterChip(
        label: String,
        active: Bool,
        lineColor: Color? = nil,
        lineForeground: Color? = nil,
        action: @escaping () -> Void
    ) -> some View {
        let isLine = lineColor != nil
        let accent = lineColor ?? DS.Color.ink
        let background: Color = active ? accent : (isLine ? accent.opacity(0.14) : DS.Color.paper)
        let foreground: Color = active
            ? (isLine ? (lineForeground ?? .white) : DS.Color.paper)
            : DS.Color.ink
        return Button(action: action) {
            Text(label)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(foreground)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(background)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(active ? accent : accent.opacity(isLine ? 0.5 : 0.2), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
        .buttonStyle(.plain)
    }

    private func iconButton(systemName: String, tint: Color = DS.Color.ink, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 14))
                .foregroundStyle(tint)
                .frame(width: 36, height: 36)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                )
        }
        .buttonStyle(.plain)
    }

    private func stopDistanceMeters(to other: TransportStopSummaryDTO) -> Int {
        guard
            let fromLat = effectiveStop.latitude,
            let fromLng = effectiveStop.longitude,
            let toLat = other.latitude,
            let toLng = other.longitude
        else { return 0 }

        let radius = 6_371_000.0
        let dLat = (toLat - fromLat) * .pi / 180
        let dLng = (toLng - fromLng) * .pi / 180
        let lat1 = fromLat * .pi / 180
        let lat2 = toLat * .pi / 180
        let h = sin(dLat / 2) * sin(dLat / 2)
            + sin(dLng / 2) * sin(dLng / 2) * cos(lat1) * cos(lat2)
        return Int((2 * radius * atan2(sqrt(h), sqrt(1 - h))).rounded())
    }

    private func openDirections() {
        guard let coordinate = stopCoordinate else { return }
        let originQuery: String
        if let userCoordinate {
            originQuery = "saddr=\(userCoordinate.latitude),\(userCoordinate.longitude)&"
        } else {
            originQuery = "saddr=Current+Location&"
        }
        let urlString = "http://maps.apple.com/?\(originQuery)daddr=\(coordinate.latitude),\(coordinate.longitude)&dirflg=r"
        guard let url = URL(string: urlString) else { return }
        UIApplication.shared.open(url)
    }

    /// FIX — « Itinéraire » reste DANS l'app : on calcule le trajet vers cet
    /// arrêt avec le planificateur interne (carte StibAlert) au lieu d'ouvrir
    /// Apple Plans. On poste le deep link route (écouté par HomeView, qui
    /// bascule sur la carte + trace l'itinéraire) puis on ferme la fiche.
    /// Repli sur Plans seulement si la coordonnée de l'arrêt est inconnue.
    private func requestItinerary() {
        guard let coordinate = stopCoordinate else {
            openDirections()
            return
        }
        var info: [String: Any] = [
            "toName": effectiveStop.name,
            "toLat": coordinate.latitude,
            "toLng": coordinate.longitude,
        ]
        if let userCoordinate {
            info["fromName"] = "Ma position"
            info["fromLat"] = userCoordinate.latitude
            info["fromLng"] = userCoordinate.longitude
        }
        NotificationCenter.default.post(name: .routeDeepLink, object: nil, userInfo: info)
        onDismiss()
    }

    private func shareStop() {
        let text = "\(effectiveStop.name) · \(effectiveStop.id)"
        let controller = UIActivityViewController(activityItems: [text], applicationActivities: nil)
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
              let root = scene.windows.first?.rootViewController else { return }
        root.present(controller, animated: true)
    }

    private func syncFavoriteState() {
        guard let user = session.currentUser else {
            isFavorite = false
            return
        }

        let favoriteIds = Set(user.favoris ?? [])
        let detailedIds = Set((user.favorisDetails ?? []).map(\.id))
        isFavorite = favoriteIds.contains(effectiveStop.id) || detailedIds.contains(effectiveStop.id)
    }

    private func toggleFavorite() async {
        guard let user = session.currentUser else { return }
        guard !isUpdatingFavorite else { return }

        isUpdatingFavorite = true
        let previous = isFavorite
        isFavorite.toggle()
        defer { isUpdatingFavorite = false }

        do {
            let response = try await UtilisateurService.toggleFavori(userId: user.id, arretId: effectiveStop.id)
            if let updatedUser = session.currentUser.map({
                UtilisateurDTO(
                    id: $0.id,
                    nom: $0.nom,
                    email: $0.email,
                    photoProfil: $0.photoProfil,
                    langue: $0.langue,
                    notifications: $0.notifications,
                    role: $0.role,
                    favoris: response.favoris ?? $0.favoris,
                    favorisDetails: response.favorisDetails ?? $0.favorisDetails,
                    routine: $0.routine,
                    votes: $0.votes,
                    oneSignalPlayerId: $0.oneSignalPlayerId,
                    favoriteLines: $0.favoriteLines,
                    weeklyDigestEnabled: $0.weeklyDigestEnabled,
                    preTripPushEnabled: $0.preTripPushEnabled,
                    communityClusterPushEnabled: $0.communityClusterPushEnabled,
                    mercisPushEnabled: $0.mercisPushEnabled,
                    quietHoursEnabled: $0.quietHoursEnabled,
                    quietHoursStartHour: $0.quietHoursStartHour,
                    quietHoursEndHour: $0.quietHoursEndHour
                )
            }) {
                session.applyCurrentUserUpdate(updatedUser)
                syncFavoriteState()
            } else {
                await session.refreshCurrentUser()
                syncFavoriteState()
            }
        } catch {
            isFavorite = previous
            ErrorReporting.capture(error, tag: "stop.favoriteToggle")
        }
    }
}

private struct StopIncidentDetailSheet: View {
    let incident: TransportIncidentDTO
    let stopName: String
    let onOpenLine: (String) -> Void

    private var title: String {
        if let type = incident.type, !type.isEmpty { return type }
        return "Perturbation"
    }

    private var bodyText: String {
        if let description = incident.description, !description.isEmpty { return description }
        return "Information active sur cet arrêt."
    }

    private var dateText: String? {
        guard let date = incident.date else { return nil }
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLocale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }

    private var severityColor: Color {
        switch incident.severity?.lowercased() {
        case "major", "high", "critical":
            return DS.Color.statusMajor
        case "minor", "medium", "warning":
            return DS.Color.statusMinor
        case "ok", "low":
            return DS.Color.statusOK
        default:
            return DS.Color.primary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                if let line = incident.line, !line.isEmpty {
                    LineBadge(line: line, size: .lg)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.primaryForeground)
                        .frame(width: 44, height: 44)
                        .background(severityColor)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }

                VStack(alignment: .leading, spacing: 6) {
                    Text(title)
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)
                    Text(stopName)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                }

                Spacer()
            }

            Text(bodyText)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                metaPill(icon: "checkmark.seal.fill", text: incident.sourceLabel)
                if let dateText {
                    metaPill(icon: "clock", text: dateText)
                }
                if let confidence = incident.confidenceLabel {
                    metaPill(icon: "location.fill", text: confidence)
                }
            }

            if let line = incident.line, !line.isEmpty {
                Button {
                    onOpenLine(line)
                } label: {
                    HStack {
                        Text("Voir la ligne \(line)")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .textCase(.uppercase)
                            .tracking(1.4)
                        Spacer()
                        Image(systemName: "arrow.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 16)
                    .frame(height: 48)
                    .background(DS.Color.primary)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
                .buttonStyle(.plain)
            }

            Spacer(minLength: 0)
        }
        .padding(22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .modifier(PaperGrainBackground())
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(DS.Font.monoSmall.weight(.bold))
                .textCase(.uppercase)
                .tracking(1.0)
                .lineLimit(1)
        }
        .foregroundStyle(DS.Color.ink)
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(DS.Color.paper2)
        .overlay(Capsule().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.2))
        .clipShape(Capsule())
    }
}

private struct StopSkeletonRows: View {
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ForEach(0..<3, id: \.self) { _ in
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(DS.Color.paper2)
                        .frame(width: 48, height: 28)
                    VStack(alignment: .leading, spacing: 6) {
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Color.paper2)
                            .frame(width: 64, height: 10)
                        RoundedRectangle(cornerRadius: 2)
                            .fill(DS.Color.paper2)
                            .frame(maxWidth: .infinity)
                            .frame(height: 12)
                    }
                    RoundedRectangle(cornerRadius: 2)
                        .fill(DS.Color.paper2)
                        .frame(width: 48, height: 24)
                }
                .opacity(pulse ? 0.5 : 1.0)
                .padding(.vertical, 12)
                Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(height: 1)
            }
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.9).repeatForever()) {
                pulse.toggle()
            }
        }
    }
}
