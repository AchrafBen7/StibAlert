import SwiftUI
import MapKit

private enum StopDetailTab: String, CaseIterable, Identifiable {
    case live
    case lines
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
    private var stopCommunitySignalements: [SignalementDTO] {
        let stopName = effectiveStop.name
        return communitySignalements
            .filter { s in
                guard s.status != "resolved" else { return false }
                if case .populated(let arret) = s.arretId {
                    return arret.nom == stopName
                }
                return false
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
                    heroMap
                        .padding(.horizontal, 20)
                        .padding(.top, 4)

                    titleBlock
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

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

                    segmentedTabs
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    tabContent
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    Text("Mise à jour en direct · STIB-MIVB")
                        .font(DS.Font.eyebrow)
                        .foregroundStyle(DS.Color.inkMute.opacity(0.75))
                        .padding(.top, 24)

                    Color.clear.frame(height: 120)
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

    private func communityReportRow(_ signalement: SignalementDTO) -> some View {
        HStack(alignment: .top, spacing: 8) {
            LineBadge(line: signalement.ligne, size: .sm)
            VStack(alignment: .leading, spacing: 2) {
                Text(signalement.displayTypeProbleme)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Text(signalement.freshnessLabel)
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
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
                                active: selectedLineFilter == line || (selectedLineFilter == nil && selectedLineRoute == line)
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

    private var stickyCTA: some View {
        HStack(spacing: 8) {
            Button(action: openDirections) {
                Label("Itinéraire", systemImage: "location.north.line")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink, lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .buttonStyle(.plain)

            if canReportFromHere {
                Button(action: onReport) {
                    Label("Signaler", systemImage: "exclamationmark.triangle.fill")
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
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .shadow(DS.Shadow.floating)
    }

    private func tabTitle(_ tab: StopDetailTab) -> String {
        switch tab {
        case .live:
            return "Temps réel"
        case .lines:
            return "Lignes · \(servedLines.count)"
        case .around:
            return "Autour"
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

    private func filterChip(label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(active ? DS.Color.paper : DS.Color.ink)
                .padding(.horizontal, 10)
                .frame(height: 28)
                .background(active ? DS.Color.ink : DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(active ? DS.Color.ink : DS.Color.ink.opacity(0.2), lineWidth: 1)
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
        formatter.locale = Locale(identifier: "fr_BE")
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
