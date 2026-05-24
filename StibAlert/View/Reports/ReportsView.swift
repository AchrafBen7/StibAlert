import SwiftUI
import UIKit


struct ReportsView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedScope: ReportContentScope = .reports
    @State private var selectedSegment: ReportSegment = .all
    @State private var selectedModeFilter: ReportTransportMode = .all
    @State private var selectedOperator: TransitOperator = .stib
    @State private var sncbGareSearch = ""
    @State private var selectedGareForDetail: SNCBStation?
    @State private var sncbRealtimeByGare: [String: SNCBRealtime] = [:]
    @State private var sncbDisruptions: [SNCBDisruption] = []
    @StateObject private var locationManager = HomeLocationManager()
    @State private var selectedSortMode: ReportSortMode = .recent
    @State private var reports: [SignalementDTO] = []
    @State private var events: [TransportEventImpactDTO] = []
    @State private var lineCatalog: [LigneCatalogDTO] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var lastUpdatedAt: Date? = nil
    @State private var loadError: String? = nil
    @State private var query = ""
    @State private var selectedLineFilter = "Tout"
    @State private var selectedReport: SignalementDTO? = nil
    @State private var selectedEvent: TransportEventImpactDTO? = nil
    /// LineId opened from the LineStatusGrid tap — drives a presentation
    /// sheet that pushes `LigneDetailPage` directly without going through
    /// the Signalements tab.
    @State private var selectedLineForDetail: String? = nil
    @State private var transportOverview: TransportOverviewDTO? = nil
    @State private var selectedLineTransport: TransportLineDTO? = nil
    @State private var selectedLineSummary: TransportPerturbationSummaryDTO? = nil
    @State private var isLoadingSummary = false
    @State private var isShowingSummary = false
    @State private var votingReportIds: Set<String> = []
    @State private var locallyUpvotedReportIds: Set<String> = []
    @State private var expandedFeedLineIds: Set<String> = []
    @State private var notificationLineInFlight: Set<String> = []
    @State private var activeNetworkCarouselIndex = 0
    @State private var lineDetailCache: [String: TransportLineDTO] = [:]
    @State private var lineDetailInFlight: Set<String> = []

    private func ensureLineDetail(for line: String) {
        let normalized = line.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        guard !normalized.isEmpty else { return }

        for variant in [normalized, "\(normalized):City", "\(normalized):Suburb"] {
            guard lineDetailCache[variant] == nil else { continue }
            guard !lineDetailInFlight.contains(variant) else { continue }
            lineDetailInFlight.insert(variant)
            Task {
                do {
                    let detail = try await TransportService.line(id: variant)
                    await MainActor.run {
                        lineDetailCache[variant] = detail
                        lineDetailInFlight.remove(variant)
                    }
                } catch {
                    await MainActor.run { lineDetailInFlight.remove(variant) }
                }
            }
        }
    }

    private func dossierStopContext(for item: NetworkIssueCarouselItem) -> (stops: [String], disruptedIndices: Set<Int>, disruptedName: String?) {
        guard let line = item.lines.first else { return ([], [], nil) }
        let key = line.uppercased()
        let candidates = [
            lineDetailCache["\(key):City"],
            lineDetailCache["\(key):Suburb"],
            lineDetailCache[key],
        ].compactMap { $0 }
        guard !candidates.isEmpty else { return ([], [], nil) }

        let structuredNeedles = [item.location]
            .compactMap { $0 }
            .map(ReportsStopMatching.normalize)
            .filter { $0.count >= 4 }
        let textNeedles = ReportsStopMatching.normalize(item.keyword + " " + item.detail)

        func context(for detail: TransportLineDTO) -> (stops: [String], disruptedIndices: Set<Int>, disruptedName: String?, score: Int) {
            let stopNames = detail.line.stops.map { $0.name }
            var disrupted: Set<Int> = []
            var disruptedName: String? = item.location
            var score = 0

            for (idx, stop) in detail.line.stops.enumerated() {
                let stopKey = ReportsStopMatching.normalize(stop.name)
                guard stopKey.count >= 4 else { continue }
                if structuredNeedles.contains(stopKey) {
                    disrupted.insert(idx)
                    disruptedName = stop.name
                    score += 100
                } else if textNeedles.contains(stopKey) {
                    disrupted.insert(idx)
                    if disruptedName == nil { disruptedName = stop.name }
                    score += 10
                }
            }

            if disrupted.isEmpty {
                for incident in detail.activeIncidents {
                    guard let stopName = incident.stop?.name else { continue }
                    let needle = ReportsStopMatching.normalize(stopName)
                    if let idx = detail.line.stops.firstIndex(where: { ReportsStopMatching.normalize($0.name) == needle }) {
                        disrupted.insert(idx)
                        if disruptedName == nil { disruptedName = stopName }
                        score += 50
                    }
                }
            }

            return (stopNames, disrupted, disruptedName, score)
        }

        guard let best = candidates
            .map(context(for:))
            .sorted(by: { left, right in
                if left.score != right.score { return left.score > right.score }
                return left.stops.count > right.stops.count
            })
            .first else { return ([], [], nil) }

        return (best.stops, best.disruptedIndices, best.disruptedName)
    }

    private var favoriteLines: Set<String> {
        Set(session.currentUser?.favoriteLines ?? [])
    }

    private var availableLineFilters: [String] {
        if selectedOperator == .sncb {
            return ["Tout", "SNCB"]
        }

        let catalogLines = lineCatalog.map(\.lineid)
        let fallbackLines = reports.map(\.ligne)
            + events.flatMap(\.impactedLines)
            + (transportOverview?.activeIncidents ?? []).compactMap(\.line)
            + (transportOverview?.perturbationSummary?.affectedLines ?? [])

        let source = catalogLines.isEmpty ? fallbackLines : catalogLines
        let lines = Set(sanitizedLines(source)).sorted {
            $0.compare($1, options: .numeric) == .orderedAscending
        }
        return ["Tout"] + lines
    }

    private var filteredReports: [SignalementDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return reports.filter { report in
            let matchesLine = selectedLineFilter == "Tout" || report.ligne == selectedLineFilter
            guard matchesLine else { return false }
            guard !trimmed.isEmpty else { return true }

            let stopName = arretName(for: report) ?? ""
            return report.ligne.localizedCaseInsensitiveContains(trimmed)
                || report.displayTypeProbleme.localizedCaseInsensitiveContains(trimmed)
                || report.description.localizedCaseInsensitiveContains(trimmed)
                || stopName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredEvents: [TransportEventImpactDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return events.filter { event in
            let matchesLine = selectedLineFilter == "Tout"
                || event.impactedLines.contains { Self.shortLineCode($0) == Self.shortLineCode(selectedLineFilter) }
            guard matchesLine else { return false }
            guard !trimmed.isEmpty else { return true }

            return event.title.localizedCaseInsensitiveContains(trimmed)
                || (event.venue ?? "").localizedCaseInsensitiveContains(trimmed)
                || (event.zoneLabel ?? "").localizedCaseInsensitiveContains(trimmed)
                || event.impactedStops.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
                || event.impactedLines.contains(where: { $0.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    private var nowItems: [EditorialNowItem] {
        if let summary = currentSummary, !summary.affectedLines.isEmpty {
            return Array(summary.affectedLines.prefix(8)).map {
                EditorialNowItem(id: "summary-\($0)", line: $0, reason: summary.shortText)
            }
        }

        var seen = Set<String>()
        return reports.compactMap { report in
            let type = feedType(for: report)
            guard type == .official || type == .mixed else { return nil }
            guard !seen.contains(report.ligne) else { return nil }
            seen.insert(report.ligne)
            return EditorialNowItem(id: report.id, line: report.ligne, reason: report.description)
        }
    }

    private var reportFeedItems: [EditorialFeedItem] {
        let reportItems = reports.compactMap { report -> EditorialFeedItem? in
            guard selectedLineFilter == "Tout" || report.ligne == selectedLineFilter else { return nil }
            return EditorialFeedItem(
                id: "report-\(report.id)",
                type: feedType(for: report),
                title: "Ligne \(report.ligne) · \(report.displayTypeProbleme)",
                body: report.description,
                timeLabel: relativeTimeLabel(from: report.dateSignalement),
                lines: [report.ligne],
                location: arretName(for: report),
                upvotes: report.votesPositifs,
                url: nil,
                attendance: nil,
                venueCapacity: nil,
                report: report,
                event: nil
            )
        }

        return (reportItems + officialTransportFeedItems)
            .filter(matchesCurrentFilters)
            .sorted(by: sortFeedItems)
    }

    private var eventFeedItems: [EditorialFeedItem] {
        let eventItems = events.compactMap { event -> EditorialFeedItem? in
            guard selectedLineFilter == "Tout"
                || event.impactedLines.contains(where: { Self.shortLineCode($0) == Self.shortLineCode(selectedLineFilter) })
            else { return nil }
            return EditorialFeedItem(
                id: "event-\(event.id)",
                type: .event,
                title: event.title,
                body: event.notesFr ?? event.venue ?? event.zoneLabel,
                timeLabel: eventTimeLabel(for: event),
                lines: event.impactedLines,
                location: event.address ?? event.venue ?? event.zoneLabel,
                upvotes: nil,
                url: event.url.flatMap(URL.init(string:)),
                attendance: event.expectedAttendance,
                venueCapacity: nil,
                report: nil,
                event: event
            )
        }

        return eventItems
            .filter(matchesCurrentFilters)
            .sorted(by: sortFeedItems)
    }

    private var feedItems: [EditorialFeedItem] {
        let scopedItems: [EditorialFeedItem]
        switch selectedScope {
        case .reports:
            // "En cours" → live signal: community reports + active official
            // incidents (everything happening right now).
            scopedItems = reportFeedItems
        case .official:
            // "Officiel" → STIB-published items only (scheduled works, planned
            // disruptions, official traffic info).
            scopedItems = reportFeedItems.filter { item in
                item.type == .official || item.type == .mixed
            }
        case .events:
            scopedItems = eventFeedItems
        }

        return scopedItems.sorted(by: sortFeedItems)
    }

    /// Incidents passed to the LineStatusGrid — also filtered per top tab so
    /// the corner badge on each line badge reflects the currently selected
    /// scope. On "Événements" we hide the grid entirely, so this returns []
    /// when scope is events.
    ///
    /// We *also* fold in any line listed in `currentSummary.affectedLines`
    /// that has no concrete incident in `currentOfficialIncidents` — that
    /// gap is exactly what made line 1 appear in the carousel sommaire but
    /// stay un-badged in the grid before. Synthetic incidents inherit the
    /// summary's source so they end up under "Officiel" too.
    // MARK: - SNCB (stations, not numbered lines)

    /// Active community reports on SNCB gares (ligne == "SNCB").
    private var sncbActiveReports: [SignalementDTO] {
        reports
            .filter { $0.status != "resolved" && $0.ligne.uppercased() == "SNCB" }
            .sorted { ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast) }
    }

    private func sncbGareName(_ report: SignalementDTO) -> String {
        if case .populated(let arret) = report.arretId { return arret.nom }
        return "Gare SNCB"
    }

    /// SNCB Infos trafic — mirrors the Horaires tab (nearest + search +
    /// province → gares drill-down), with the active community perturbations
    /// summarised on top. Tapping a gare opens *its* Infos trafic page (the
    /// En cours / Officiel / Twitter sub-tabs), exactly like a STIB line.
    @ViewBuilder
    private var sncbInfoTraficContent: some View {
        let active = sncbActiveReports
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            VStack(alignment: .leading, spacing: 10) {
                sncbSectionHeader(icon: active.isEmpty ? "checkmark.seal.fill" : "exclamationmark.triangle.fill",
                                  title: "Perturbations en cours", count: active.count,
                                  tint: active.isEmpty ? DS.Color.statusOK : DS.Color.statusMajor)
                if active.isEmpty {
                    sncbAllClearCard
                } else {
                    VStack(spacing: 8) {
                        ForEach(active) { sncbReportCard($0) }
                    }
                }
            }

            SncbGareDirectory(
                searchQuery: $sncbGareSearch,
                showsSearchField: true,
                userCoordinate: locationManager.userCoordinate,
                badgeTypes: { sncbBadgeTypes(for: $0) },
                onSelect: { selectedGareForDetail = $0 }
            )
        }
    }

    /// All the problem indicators for a gare, fed to the directory as per-type
    /// icons (deduped) — combining community reports, live iRail delays/
    /// cancellations (for the nearby gares we've fetched), and official network
    /// disturbances that name the gare. Like the STIB line badges, but for
    /// trains.
    private func sncbBadgeTypes(for station: SNCBStation) -> [String] {
        var types = sncbActiveReportTypes(for: station)

        // Live delays / cancellations (iRail liveboard) — only for the nearby
        // gares we proactively fetched (bounded calls).
        if let rt = sncbRealtimeByGare[station.id] {
            for d in rt.departures where d.canceled || d.delayMinutes > 0 {
                types.append(d.canceled ? "interruption" : "retard")
            }
        }

        // Official network disturbances that mention this gare by name.
        if !sncbDisruptions.isEmpty {
            let key = station.displayName.folding(options: .diacriticInsensitive, locale: .current).lowercased()
            if key.count >= 3 {
                let named = sncbDisruptions.contains { d in
                    (d.title + " " + d.description)
                        .folding(options: .diacriticInsensitive, locale: .current)
                        .lowercased()
                        .contains(key)
                }
                if named { types.append("perturbation") }
            }
        }
        return types
    }

    /// Problem types of the active community reports targeting a gare — one
    /// per report (duplicates kept), so the directory can show an accumulating
    /// set of per-type icons (retard, accident, panne…).
    private func sncbActiveReportTypes(for station: SNCBStation) -> [String] {
        sncbActiveReports.compactMap { report -> String? in
            guard case .populated(let arret) = report.arretId else { return nil }
            let matches = (arret.stopId == station.id)
                || (arret.nom.normalizedStopKey == station.displayName.normalizedStopKey)
            return matches ? report.typeProbleme : nil
        }
    }

    /// Fetch live SNCB data for the nearby gares (bounded calls, backend-cached)
    /// so the directory can badge them with real delays/disruptions. The
    /// network disturbances returned apply to every gare (name match).
    @MainActor
    private func loadSncbRealtime() async {
        guard selectedOperator == .sncb else { return }
        let nearest = SNCBStationService
            .nearbyStations(around: locationManager.userCoordinate, radiusMeters: 35_000, limit: 5)
            .map(\.station)
        guard !nearest.isEmpty else { return }

        var map: [String: SNCBRealtime] = [:]
        await withTaskGroup(of: (String, SNCBRealtime?).self) { group in
            for gare in nearest {
                group.addTask { (gare.id, await SNCBStationService.realtime(stationId: gare.id)) }
            }
            for await (id, rt) in group {
                if let rt { map[id] = rt }
            }
        }
        sncbRealtimeByGare = map
        if let disruptions = map.values.first?.disruptions, !disruptions.isEmpty {
            sncbDisruptions = disruptions
        }
    }

    private func sncbSectionHeader(icon: String, title: String, count: Int, tint: Color) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 28, height: 28)
                .background(tint.opacity(0.14))
                .clipShape(Circle())
            Text(title.uppercased())
                .font(DS.Font.eyebrow).tracking(2)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
            Text("\(count)")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(DS.Color.inkMute)
        }
    }

    private var sncbAllClearCard: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.Color.statusOK)
            VStack(alignment: .leading, spacing: 2) {
                Text("Réseau SNCB OK")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text("Aucune perturbation signalée sur les gares.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.statusOK.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.statusOK.opacity(0.25), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func sncbReportCard(_ report: SignalementDTO) -> some View {
        Button {
            selectedReport = report
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Color.statusMajor))
                VStack(alignment: .leading, spacing: 3) {
                    Text(sncbGareName(report))
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Text("\(report.displayTypeProbleme) · \(report.freshnessLabel)")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let confirmations = report.community?.confirmations, confirmations > 0 {
                    Text("\(confirmations)×")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.community)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    // MARK: - De Lijn / TEC Infos trafic

    /// Community signalements for a De Lijn / TEC stop (matched by the report's
    /// operator pseudo-line) + the official disruptions list.
    @ViewBuilder
    private func operatorInfoTraficContent(_ op: TransitOperator) -> some View {
        let community = operatorActiveReports(for: op)
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            if !community.isEmpty {
                VStack(alignment: .leading, spacing: 10) {
                    sncbSectionHeader(icon: "person.2.fill", title: "Signalements communauté", count: community.count, tint: DS.Color.community)
                    VStack(spacing: 8) {
                        ForEach(community) { operatorReportCard($0) }
                    }
                }
            }
            OperatorDisruptionsList(op: op, userCoordinate: locationManager.userCoordinate)
        }
    }

    private func operatorActiveReports(for op: TransitOperator) -> [SignalementDTO] {
        reports
            .filter { $0.status != "resolved" && reportMatchesOperator($0, op) }
            .sorted { ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast) }
    }

    private func reportMatchesOperator(_ s: SignalementDTO, _ op: TransitOperator) -> Bool {
        let l = s.ligne.uppercased().trimmingCharacters(in: .whitespaces)
        switch op {
        case .delijn: return l == "DE LIJN" || l == "DELIJN"
        case .tec: return l == "TEC"
        default: return false
        }
    }

    private func operatorStopName(_ report: SignalementDTO) -> String {
        if case .populated(let arret) = report.arretId { return arret.nom }
        return "Arrêt"
    }

    private func operatorReportCard(_ report: SignalementDTO) -> some View {
        Button {
            selectedReport = report
        } label: {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: SignalVisuals.icon(forType: report.typeProbleme))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(Circle().fill(DS.Color.statusMajor))
                VStack(alignment: .leading, spacing: 3) {
                    Text(operatorStopName(report))
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Text("\(report.displayTypeProbleme) · \(report.freshnessLabel)")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
                if let confirmations = report.community?.confirmations, confirmations > 0 {
                    Text("\(confirmations)×")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.community)
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var incidentsForLineGrid: [TransportIncidentDTO] {
        switch selectedScope {
        case .events:
            return []
        case .reports, .official:
            let base: [TransportIncidentDTO]
            if selectedScope == .official {
                base = currentOfficialIncidents.filter { incident in
                    let source = incident.source?.lowercased() ?? ""
                    return source.contains("official") || source.contains("stib")
                }
            } else {
                base = currentOfficialIncidents
            }
            return base + syntheticIncidentsFromSummary(missingFrom: base)
        }
    }

    /// Build placeholder `TransportIncidentDTO`s for every `affectedLines`
    /// entry in the current summary that isn't already represented in
    /// `incidentsBaseline`. Lets the LineStatusGrid badge those lines even
    /// when the backend ships them only in the summary aggregate.
    private func syntheticIncidentsFromSummary(missingFrom incidentsBaseline: [TransportIncidentDTO]) -> [TransportIncidentDTO] {
        var knownLines = Set(incidentsBaseline.compactMap { $0.line?.uppercased() })
        var synthesised: [TransportIncidentDTO] = []

        // 1. Lines mentioned in the perturbation summary's affected list.
        if let summary = currentSummary {
            let summaryType = summary.incidentTypes?.first ?? "perturbation"
            let summarySource = summary.source ?? summary.sourceLabel ?? "official"
            for line in summary.affectedLines {
                let normalized = line.uppercased()
                guard !knownLines.contains(normalized) else { continue }
                synthesised.append(TransportIncidentDTO(
                    id: "summary-\(normalized)",
                    type: summaryType,
                    description: summary.shortText,
                    severity: "minor",
                    confidence: nil,
                    legacyConfidence: nil,
                    source: summarySource,
                    line: line,
                    stop: nil,
                    date: nil,
                    community: nil
                ))
                knownLines.insert(normalized)
            }
        }

        // 2. Lines that show up as feed items (community reports + official
        // signals from `reportFeedItems`) but somehow weren't picked up by
        // either the activeIncidents list or the summary. Without this the
        // grid badge for métro 1 / tram 81 stayed empty while the feed
        // (sommaire) clearly listed them.
        for item in reportFeedItems {
            for line in item.lines {
                let normalized = line.uppercased()
                guard !normalized.isEmpty, !knownLines.contains(normalized) else { continue }
                let isOfficial = item.type == .official || item.type == .mixed
                synthesised.append(TransportIncidentDTO(
                    id: "feed-\(item.id)-\(normalized)",
                    type: item.title,
                    description: item.body,
                    severity: isOfficial ? "minor" : "minor",
                    confidence: nil,
                    legacyConfidence: nil,
                    source: isOfficial ? "official" : "community",
                    line: line,
                    stop: nil,
                    date: nil,
                    community: nil
                ))
                knownLines.insert(normalized)
            }
        }

        return synthesised
    }

    private func matchesCurrentFilters(_ item: EditorialFeedItem) -> Bool {
        guard matchesSelectedMode(lines: item.lines) else { return false }
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return true }
        let haystack = [
            item.title,
            item.body ?? "",
            item.location ?? "",
            item.lines.joined(separator: " ")
        ].joined(separator: " ")
        return haystack.localizedCaseInsensitiveContains(trimmed)
    }

    private var shouldHideOfficialFeedDuplicates: Bool {
        selectedScope == .reports
            && selectedSegment == .all
            && selectedLineFilter == "Tout"
            && currentSummary != nil
    }

    private var shouldGroupFeedByLine: Bool {
        guard selectedOperator != .sncb else { return false }
        // Group by line+mode on both "En cours" and "Officiel" — Événements
        // remains a flat chronological list because each event item
        // typically spans multiple lines.
        return (selectedScope == .reports || selectedScope == .official)
            && selectedLineFilter == "Tout"
    }

    private var groupedFeedItems: [EditorialLineGroup] {
        let grouped = Dictionary(grouping: feedItems.filter { !$0.lines.isEmpty }) { item in
            item.lines.first ?? "Réseau"
        }

        return grouped.map { line, items in
            EditorialLineGroup(
                id: line,
                line: line,
                items: items.sorted(by: sortFeedItems)
            )
        }
        .sorted { lhs, rhs in
            sortLineGroups(lhs, rhs)
        }
    }

    /// Top-level feed grouping: split the per-line groups into MÉTRO / TRAM
    /// / BUS sections so the user no longer scrolls a long mixed list.
    /// Order is fixed (metro → tram → bus) and empty sections are skipped.
    private var feedSections: [EditorialModeSection] {
        let groupsByMode = Dictionary(grouping: groupedFeedItems) { group in
            TransitLineMode.mode(for: group.line)
        }
        let order: [TransitLineMode] = [.metro, .tram, .bus]
        return order.compactMap { mode -> EditorialModeSection? in
            guard let groups = groupsByMode[mode], !groups.isEmpty else { return nil }
            return EditorialModeSection(id: mode, mode: mode, groups: groups)
        }
    }

    private var segmentCounts: [ReportSegment: Int] {
        let reportItems = reportFeedItems
        let officialCount = reportItems.reduce(0) { partial, item in
            partial + ((item.type == .official || item.type == .mixed) ? 1 : 0)
        }
        let communityCount = reportItems.reduce(0) { partial, item in
            partial + ((item.type == .community || item.type == .mixed) ? 1 : 0)
        }
        var counts: [ReportSegment: Int] = [:]
        counts[.all] = reportItems.count
        counts[.official] = officialCount
        counts[.community] = communityCount
        counts[.events] = eventFeedItems.count
        return counts
    }

    private var visibleLineFilters: [String] {
        if selectedOperator == .sncb {
            return ["Tout", "SNCB"]
        }

        // The line-filter dock is only shown on the Events scope, so the
        // useful chip set is "every line an event actually touches" — that way
        // each chip yields results and the user sees all the lines events
        // impact (instead of the first 40 catalog lines, which mostly have no
        // event). Normalised to short codes + numeric-sorted.
        let codes = events
            .flatMap(\.impactedLines)
            .map(Self.shortLineCode)
            .filter { !$0.isEmpty }
        let unique = Array(Set(codes)).sorted { $0.compare($1, options: .numeric) == .orderedAscending }
        return ["Tout"] + unique
    }

    var body: some View {
        ZStack {
            DS.Color.paper
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    editorialHeader
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.md)

                    statusHUD
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.md)

                    // The dossier carousel ("sommaire") is now folded into the
                    // LineStatusGrid below — each line's badge carries the
                    // same incident icon, so the user finds the same info on
                    // its line tile and can tap through to LigneDetailPage.

                    // SNCB hides the En cours / Officiel / Événements scope
                    // tabs — for trains those filters live *inside* each gare's
                    // Infos trafic page, not at the network level.
                    // Scope tabs (En cours / Officiel / Événements) are a
                    // STIB-only concept. SNCB filters live inside each gare;
                    // De Lijn / TEC show their official disruptions directly.
                    if selectedOperator == .stib {
                        scopeSegmentedTabs
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.top, DS.Spacing.lg)
                    }

                    if selectedOperator == .sncb {
                        // SNCB has stations, not numbered lines — mirror the
                        // Horaires drill-down (province → gares); a tap opens
                        // that gare's own Infos trafic page.
                        sncbInfoTraficContent
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.top, DS.Spacing.lg)
                    } else if selectedOperator == .delijn || selectedOperator == .tec {
                        operatorInfoTraficContent(selectedOperator)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.top, DS.Spacing.lg)
                    } else if !lineCatalog.isEmpty && selectedScope != .events {
                        LineStatusGrid(
                            catalog: lineCatalog,
                            incidents: incidentsForLineGrid,
                            onSelectLine: { lineId in
                                // Open LigneDetailPage directly as a sheet
                                // instead of routing through the Signalements
                                // tab — the user only wants the line detail
                                // from this tap, not the broader signalements
                                // landing.
                                selectedLineForDetail = lineId
                            }
                        )
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.lg)
                    }

                    if let loadError {
                        errorBanner(loadError)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.top, DS.Spacing.lg)
                    }

                    // Sommaire / feed has been removed entirely from Infos
                    // trafic: every line shown there is now reachable via the
                    // LineStatusGrid badge above (tap → LigneDetailPage with
                    // the same details under the Infos trafic sub-tab).
                    // Set to true on the Événements tab to keep the events
                    // feed visible (no grid equivalent yet).
                    if selectedOperator == .stib && selectedScope == .events {
                        Section(header: editorialStickySegments) {
                            editorialFeedSection
                        }
                    }
            }
                .padding(.bottom, 140)
            }
            .refreshable {
                await loadData(force: true)
            }

            VStack {
                Spacer()
                HStack {
                    Spacer()
                    editorialFAB
                        .padding(.trailing, DS.Spacing.xl)
                        .padding(.bottom, 104)
                }
            }
        }
        .modifier(PaperGrainBackground())
        .toolbar(.hidden, for: .navigationBar)
        .sheet(item: $selectedReport) { report in
            SignalementDetailView(
                signalement: report,
                onDismiss: { selectedReport = nil }
            )
            .presentationDetents([.large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $selectedEvent) { event in
            EventImpactDetailSheet(
                event: event,
                relatedEvents: relatedEvents(for: event)
            )
                .environmentObject(nav)
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
        .fullScreenCover(isPresented: Binding(
            get: { selectedLineForDetail != nil },
            set: { if !$0 { selectedLineForDetail = nil } }
        )) {
            if let lineId = selectedLineForDetail {
                // Full-screen cover instead of a bottom sheet — the user
                // wants the line detail to feel like a real page push, not a
                // modal. Closing happens via LigneDetailPage's own back
                // button (which calls `dismiss()` from the inner scope).
                LigneDetailPage(lineId: lineId, initialTab: .traffic)
                    .environmentObject(session)
                    .environmentObject(nav)
            }
        }
        .fullScreenCover(item: $selectedGareForDetail) { gare in
            // Same full-page treatment as a STIB line, opened on the gare's
            // Infos trafic tab. "Signaler cette gare" routes back to the
            // standard report flow.
            GareDetailPage(station: gare, initialTab: .traffic, onReport: { _ in
                selectedGareForDetail = nil
                nav.showReportSheet = true
            })
            .environmentObject(session)
            .environmentObject(nav)
        }
        .sheet(isPresented: $isShowingSummary) {
            if let summary = currentSummary {
                ReportsSummarySheet(
                    summary: summary,
                    lineLabel: selectedLineFilter == "Tout" ? nil : selectedLineFilter
                )
                    .presentationDetents([.medium, .large])
                    .presentationDragIndicator(.visible)
            }
        }
        .task {
            locationManager.start()
            applyPendingScopeIfPossible()
            await loadData()
            applyPendingReportFocusIfPossible()
            await loadSncbRealtime()
        }
        .onChange(of: selectedOperator) { _, _ in
            Task { await loadSncbRealtime() }
        }
        .onChange(of: reports.count) { _, _ in
            applyPendingReportFocusIfPossible()
        }
        .onChange(of: nav.pendingReportsScopeRawValue) { _, _ in
            applyPendingScopeIfPossible()
        }
        .onChange(of: selectedLineFilter) { _, _ in
            Task { await loadSummary(force: true) }
        }
        .onChange(of: selectedScope) { _, _ in
            if selectedScope == .events {
                selectedSegment = .events
            } else if selectedSegment == .events {
                selectedSegment = .all
            }
            Task { await loadData(force: true) }
        }
        .onChange(of: selectedModeFilter) { _, _ in
            if selectedLineFilter != "Tout", !matchesSelectedMode(lines: [selectedLineFilter]) {
                selectedLineFilter = "Tout"
            }
        }
    }

    private func relatedEvents(for event: TransportEventImpactDTO) -> [TransportEventImpactDTO] {
        let venueKey = (event.venue ?? event.zoneLabel ?? event.title)
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()

        return events
            .filter {
                let key = ($0.venue ?? $0.zoneLabel ?? $0.title)
                    .trimmingCharacters(in: .whitespacesAndNewlines)
                    .lowercased()
                return key == venueKey
            }
            .sorted { lhs, rhs in
                switch (lhs.startsAt, rhs.startsAt) {
                case let (l?, r?):
                    return l < r
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                default:
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }
            }
    }

    private var currentSummary: TransportPerturbationSummaryDTO? {
        if selectedLineFilter == "Tout" {
            return transportOverview?.perturbationSummary
        }
        return selectedLineSummary
    }

    private var currentOfficialIncidents: [TransportIncidentDTO] {
        if selectedLineFilter == "Tout" {
            return transportOverview?.activeIncidents ?? []
        }
        return selectedLineTransport?.activeIncidents ?? []
    }

    private var officialTransportFeedItems: [EditorialFeedItem] {
        let directItems = currentOfficialIncidents
            .filter { incident in
                let source = incident.source?.lowercased() ?? ""
                return source.contains("official") || source.contains("stib")
            }
            .map { incident in
                let primaryLine = incident.line?.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = primaryLine.map { [$0] } ?? []
                return EditorialFeedItem(
                    id: "official-transport-\(incident.id)",
                    type: .official,
                    title: primaryLine.map { "Ligne \($0) · \(incident.type ?? "Information STIB")" } ?? (incident.type ?? "Information STIB"),
                    body: incident.description,
                    timeLabel: relativeTimeLabel(from: incident.date),
                    lines: lines,
                    location: incident.stop?.name,
                    upvotes: nil,
                    url: nil,
                    attendance: nil,
                    venueCapacity: nil,
                    report: nil,
                    event: nil
                )
            }

        guard let summary = currentSummary,
              (summary.sourceBreakdown?.official ?? 0) > 0 || (summary.sourceLabel?.lowercased() == "officiel")
        else {
            return directItems
        }

        let bullets = summary.bullets.isEmpty ? [summary.shortText] : summary.bullets
        let summaryItems = bullets.prefix(4).enumerated().map { index, bullet in
            EditorialFeedItem(
                id: "official-summary-\(index)",
                type: .official,
                title: summary.affectedLines.first.map { "Ligne \($0) · Information STIB" } ?? "Information STIB",
                body: bullet,
                timeLabel: "source officielle",
                lines: summary.affectedLines,
                location: summary.affectedStops.first,
                upvotes: nil,
                url: nil,
                attendance: nil,
                venueCapacity: nil,
                report: nil,
                event: nil
            )
        }

        return directItems + (shouldHideOfficialFeedDuplicates ? [] : summaryItems)
    }

    private var editorialHeader: some View {
        ReportsMasthead(
            selectedScope: $selectedScope,
            onScopeChange: selectScope(_:)
        )
    }

    /// Belgian transit operators row. Now extracted into the shared
    /// `TransitOperatorRow` component so the Horaires tab can reuse the
    /// exact same masthead.
    private var statusHUD: some View {
        TransitOperatorRow(
            activeOperator: selectedOperator,
            enabledOperators: [.stib, .sncb, .delijn, .tec],
            onSelect: { transitOperator in
                selectedOperator = transitOperator
                selectedLineFilter = "Tout"
                selectedModeFilter = transitOperator == .sncb ? .sncb : .all
            }
        )
    }

    private var editorialSearchSection: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(DS.Color.ink)

            TextField(
                "",
                text: $query,
                prompt: Text("Rechercher une ligne, un arrêt ou un problème")
                    .foregroundStyle(DS.Color.inkMute)
            )
            .font(DS.Font.body)
            .foregroundStyle(DS.Color.ink)
            .textInputAutocapitalization(.words)
            .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(DS.Color.paper)
        .clipShape(Capsule())
        .overlay(
            Capsule()
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
        )
        .shadow(DS.Shadow.raised)
    }

    /// Top-level 3-tab segmented control: En cours / Officiel / Événements.
    /// Drives both the LineStatusGrid badge filtering (above) and the feed
    /// filtering (below). Replaces the older 2-mode toggle plus inline
    /// segments — all three filters now live in a single horizontal bar.
    private var scopeSegmentedTabs: some View {
        HStack(spacing: 4) {
            ForEach(ReportContentScope.allCases) { scope in
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedScope = scope
                        // Reset segment when leaving .reports so the filter
                        // logic stays predictable for sub-scopes.
                        if scope == .events {
                            selectedSegment = .events
                        } else {
                            selectedSegment = .all
                        }
                    }
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: scope.icon)
                            .font(.system(size: 12, weight: .bold))
                        Text(scope.title)
                            .font(DS.Font.bodyBold)
                            .tracking(0.4)
                    }
                    .foregroundStyle(selectedScope == scope ? DS.Color.paper : DS.Color.ink)
                    .padding(.horizontal, 12)
                    .frame(maxWidth: .infinity)
                    .frame(height: 38)
                    .background(selectedScope == scope ? DS.Color.ink : DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                            .stroke(DS.Color.ink.opacity(selectedScope == scope ? 0 : 0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.Color.paper2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var editorialStickySegments: some View {
        ReportsFilterDock(
            // The new top-level `scopeSegmentedTabs` already covers segment
            // filtering, so the inline ReportsFilterDock segments would
            // duplicate that UI. We keep the dock only for the line/mode
            // /sort sub-filters, hidden on the Événements tab.
            showsReportFilters: false,
            selectedSegment: selectedSegment,
            selectedMode: selectedModeFilter,
            selectedLine: selectedLineFilter,
            selectedSort: selectedSortMode,
            lineFilters: visibleLineFilters,
            segmentCounts: segmentCounts,
            helperText: scopeHelperText,
            updatedText: lastUpdatedAt.map { "Mis à jour \(relativeTimeLabel(from: $0))" },
            onSelectSegment: { segment in
                if segment == .events {
                    selectedScope = .events
                    selectedSegment = .events
                } else {
                    selectedScope = .reports
                    selectedSegment = segment
                }
            },
            onSelectMode: { selectedModeFilter = $0 },
            onSelectLine: { selectedLineFilter = $0 },
            onSelectSort: { selectedSortMode = $0 }
        )
        .background(DS.Color.paper.ignoresSafeArea(edges: .top))
        .zLayer(.modalDropdown)
    }

    private var scopeHelperText: String {
        switch selectedScope {
        case .reports:
            return "Signalements en temps réel — communauté + perturbations actives."
        case .official:
            return "Informations officielles STIB : travaux planifiés, perturbations à venir."
        case .events:
            return "Événements et lieux qui peuvent augmenter l’affluence autour de certaines lignes."
        }
    }

    @ViewBuilder
    private var editorialFeedSection: some View {
        ReportsFeedView(
            isLoading: isLoading,
            hasLoaded: hasLoaded,
            feedItems: feedItems,
            shouldGroupFeedByLine: shouldGroupFeedByLine,
            feedSections: feedSections,
            favoriteLines: favoriteLines,
            expandedFeedLineIds: $expandedFeedLineIds,
            votingReportIds: votingReportIds,
            locallyUpvotedReportIds: locallyUpvotedReportIds,
            notificationLineInFlight: notificationLineInFlight,
            onOpenItem: openFeedItem(_:),
            onUpvote: { report in Task { await upvoteReport(report) } },
            onNotifyLine: { line in Task { await enableLineNotifications(for: line) } }
        )
    }

    private func openFeedItem(_ item: EditorialFeedItem) {
        if let report = item.report {
            selectedReport = report
        } else if let event = item.event {
            selectedEvent = event
        }
    }

    private var editorialFAB: some View {
        Button {
            nav.showReportSheet = true
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 20, weight: .heavy))
            .foregroundStyle(DS.Color.primaryForeground)
            .frame(width: 54, height: 54)
            .background(DS.Color.primary)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.statusMajor)
            Text(message)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkSoft)
            Spacer()
            Button {
                Task { await loadReports(force: true) }
            } label: {
                Text("Réessayer")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundStyle(DS.Color.primary)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.border, lineWidth: DS.Stroke.hairline)
        )
        .shadow(DS.Shadow.raised)
    }

    private func selectScope(_ scope: ReportContentScope) {
        selectedScope = scope
        selectedSegment = scope == .events ? .events : .all
    }

    @MainActor
    private func applyPendingScopeIfPossible() {
        guard let rawValue = nav.pendingReportsScopeRawValue else { return }
        if let scope = ReportContentScope(rawValue: rawValue) {
            selectedScope = scope
        }
        selectedSegment = rawValue == "events" ? .events : .all
        nav.pendingReportsScopeRawValue = nil
    }

    @MainActor
    private func loadData(force: Bool = false) async {
        await loadLineCatalog(force: force)
        await loadReports(force: force)
        await loadEvents(force: force)
        await loadSummary(force: force)
        lastUpdatedAt = Date()
    }

    @MainActor
    private func loadLineCatalog(force: Bool = false) async {
        guard AppConfig.isBackendEnabled else { return }
        if !force, !lineCatalog.isEmpty { return }
        do {
            lineCatalog = try await LigneService.toutesLesLignes()
        } catch {
            ErrorReporting.capture(error, tag: "reports.lineCatalog")
        }
    }

    @MainActor
    private func loadReports(force: Bool = false) async {
        guard AppConfig.isBackendEnabled else {
            hasLoaded = true
            return
        }
        guard !isLoading else { return }
        if hasLoaded && !force { return }

        isLoading = true
        loadError = nil
        defer {
            isLoading = false
            hasLoaded = true
        }

        do {
            async let mixedResponse = SignalementService.liste(page: 1, limit: 100)
            async let officialResponse = SignalementService.liste(page: 1, limit: 100, source: "official")
            let mixed = try await mixedResponse
            let official = try await officialResponse
            var seenReportIds = Set<String>()
            let merged = (mixed.signalements + official.signalements).filter { report in
                seenReportIds.insert(report.id).inserted
            }
            reports = merged.sorted {
                ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast)
            }
            if !availableLineFilters.contains(selectedLineFilter) {
                selectedLineFilter = "Tout"
            }
        } catch {
            loadError = error.localizedDescription
            ErrorReporting.capture(error, tag: "reports.load")
        }
    }

    @MainActor
    private func loadSummary(force: Bool = false) async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingSummary else { return }
        // Summary feeds both "En cours" and "Officiel" tabs (the
        // LineStatusGrid badges) so we load it for both. We skip only the
        // Événements scope where the grid isn't visible.
        guard selectedScope != .events else { return }
        if selectedLineFilter == "Tout", transportOverview != nil && !force { return }
        if selectedLineFilter != "Tout", selectedLineSummary != nil && !force { return }

        isLoadingSummary = true
        defer { isLoadingSummary = false }

        do {
            if selectedLineFilter == "Tout" {
                transportOverview = try await TransportService.overview()
                selectedLineTransport = nil
                selectedLineSummary = nil
            } else {
                let line = try await TransportService.line(id: selectedLineFilter)
                selectedLineTransport = line
                selectedLineSummary = line.perturbationSummary
            }
        } catch {
            ErrorReporting.capture(error, tag: "reports.summary")
        }
    }

    @MainActor
    private func loadEvents(force: Bool = false) async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoading else { return }
        if hasLoaded && !force && !events.isEmpty { return }

        do {
            let response = try await TransportService.events(
                line: selectedLineFilter == "Tout" ? nil : selectedLineFilter,
                query: query,
                activeOnly: false,
                limit: 80
            )
            events = response.events
        } catch {
            ErrorReporting.capture(error, tag: "reports.events")
        }
    }

    @MainActor
    private func applyPendingReportFocusIfPossible() {
        guard let reportId = nav.pendingReportFocus?.trimmingCharacters(in: .whitespacesAndNewlines), !reportId.isEmpty else {
            return
        }

        if let match = reports.first(where: { $0.id == reportId }) {
            if selectedLineFilter != "Tout", selectedLineFilter != match.ligne {
                selectedLineFilter = match.ligne
            }
            selectedReport = match
            nav.pendingReportFocus = nil
        }
    }

    private func arretName(for report: SignalementDTO) -> String? {
        if case .populated(let arret) = report.arretId {
            return arret.nom
        }
        return nil
    }

    private func feedType(for report: SignalementDTO) -> EditorialFeedItemType {
        let label = report.sourceLabel.lowercased()
        if label.contains("stib +") {
            return .mixed
        }
        if label.contains("stib") || label.contains("officiel") {
            return .official
        }
        return .community
    }

    private func matchesSelectedMode(lines: [String]) -> Bool {
        if selectedOperator == .sncb {
            return lines.contains { transportMode(for: $0) == .sncb }
        }
        if selectedOperator != .stib {
            return false
        }
        guard selectedModeFilter != .all else { return true }
        return lines.contains { transportMode(for: $0) == selectedModeFilter }
    }

    private func transportMode(for line: String) -> ReportTransportMode {
        let normalized = line.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
        if normalized == "SNCB" || normalized == "NMBS" || normalized == "TRAIN" {
            return .sncb
        }
        if normalized.hasPrefix("T") { return .tram }
        guard let number = Int(normalized) else { return .bus }
        if (1...6).contains(number) { return .metro }
        if [7, 8, 9, 10, 19, 25, 39, 44, 51, 55, 62, 81, 82, 92, 93].contains(number) {
            return .tram
        }
        return .bus
    }

    private func sortFeedItems(_ lhs: EditorialFeedItem, _ rhs: EditorialFeedItem) -> Bool {
        switch selectedSortMode {
        case .personal:
            let lhsFavorite = lhs.lines.contains { favoriteLines.contains($0) }
            let rhsFavorite = rhs.lines.contains { favoriteLines.contains($0) }
            if lhsFavorite != rhsFavorite { return lhsFavorite }
        case .urgent:
            let lhsUrgency = urgencyScore(lhs)
            let rhsUrgency = urgencyScore(rhs)
            if lhsUrgency != rhsUrgency { return lhsUrgency > rhsUrgency }
        case .recent:
            break
        }

        let lhsIsCommunity = lhs.type == .community || lhs.type == .mixed
        let rhsIsCommunity = rhs.type == .community || rhs.type == .mixed

        if lhsIsCommunity, rhsIsCommunity {
            let lhsScore = communityRankScore(lhs)
            let rhsScore = communityRankScore(rhs)
            if lhsScore != rhsScore { return lhsScore > rhsScore }
        }

        switch (lhs.event?.startsAt, rhs.event?.startsAt, lhs.report?.dateSignalement, rhs.report?.dateSignalement) {
        case let (l?, r?, _, _):
            return l > r
        case let (_, _, l?, r?):
            return l > r
        default:
            return lhs.title < rhs.title
        }
    }

    private func sortLineGroups(_ lhs: EditorialLineGroup, _ rhs: EditorialLineGroup) -> Bool {
        switch selectedSortMode {
        case .personal:
            let lhsFavorite = favoriteLines.contains(lhs.line)
            let rhsFavorite = favoriteLines.contains(rhs.line)
            if lhsFavorite != rhsFavorite { return lhsFavorite }
        case .urgent:
            let lhsScore = lhs.items.map(urgencyScore).max() ?? 0
            let rhsScore = rhs.items.map(urgencyScore).max() ?? 0
            if lhsScore != rhsScore { return lhsScore > rhsScore }
        case .recent:
            break
        }

        if lhs.items.count != rhs.items.count {
            return lhs.items.count > rhs.items.count
        }
        return lhs.line.compare(rhs.line, options: .numeric) == .orderedAscending
    }

    private func urgencyScore(_ item: EditorialFeedItem) -> Int {
        var score = 0
        switch item.type {
        case .official: score += 5
        case .mixed: score += 7
        case .community: score += 2
        case .event: score += 1
        }

        let text = "\(item.title) \(item.body ?? "")".lowercased()
        if text.contains("interrompu") || text.contains("bloqué") || text.contains("accident") {
            score += 8
        }
        if text.contains("travaux") || text.contains("dévi") || text.contains("retard") {
            score += 4
        }
        if item.lines.contains(where: { favoriteLines.contains($0) }) {
            score += 3
        }
        return score
    }

    private func communityRankScore(_ item: EditorialFeedItem) -> Int {
        guard let report = item.report else { return 0 }
        let upvotes = report.votesPositifs ?? 0
        let downvotes = report.votesNegatifs ?? 0
        let confirmations = report.community?.confirmations ?? 0
        return max(0, upvotes - downvotes) + confirmations * 2
    }

    @MainActor
    private func upvoteReport(_ report: SignalementDTO) async {
        guard !votingReportIds.contains(report.id) else { return }
        if locallyUpvotedReportIds.contains(report.id) { return }

        votingReportIds.insert(report.id)
        defer { votingReportIds.remove(report.id) }

        do {
            let response = try await SignalementService.voter(signalementId: report.id, vote: "up")
            locallyUpvotedReportIds.insert(report.id)
            if let updated = response.signalement {
                replaceReport(updated)
            } else {
                incrementLocalUpvote(for: report.id)
            }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func enableLineNotifications(for line: String) async {
        guard let user = session.currentUser else {
            nav.authInitialRoute = .signIn
            nav.showAuthFlow = true
            return
        }
        guard !favoriteLines.contains(line), !notificationLineInFlight.contains(line) else { return }

        notificationLineInFlight.insert(line)
        defer { notificationLineInFlight.remove(line) }

        do {
            let updatedLines = Array((favoriteLines.union([line]))).sorted {
                $0.compare($1, options: .numeric) == .orderedAscending
            }
            let updated = try await UtilisateurService.mettreAJourProfil(
                userId: user.id,
                favoriteLines: updatedLines
            )
            session.applyCurrentUserUpdate(updated)
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        } catch {
            loadError = (error as? APIError)?.errorDescription ?? error.localizedDescription
        }
    }

    @MainActor
    private func replaceReport(_ updated: SignalementDTO) {
        if let index = reports.firstIndex(where: { $0.id == updated.id }) {
            reports[index] = updated
        }
        if selectedReport?.id == updated.id {
            selectedReport = updated
        }
    }

    @MainActor
    private func incrementLocalUpvote(for reportId: String) {
        guard let index = reports.firstIndex(where: { $0.id == reportId }) else { return }
        let current = reports[index]
        reports[index] = SignalementDTO(
            id: current.id,
            utilisateurId: current.utilisateurId,
            arretId: current.arretId,
            ligne: current.ligne,
            typeProbleme: current.typeProbleme,
            description: current.description,
            photo: current.photo,
            latitude: current.latitude,
            longitude: current.longitude,
            confiance: current.confiance,
            source: current.source,
            votesPositifs: (current.votesPositifs ?? 0) + 1,
            votesNegatifs: current.votesNegatifs,
            dateSignalement: current.dateSignalement,
            status: current.status,
            community: current.community
        )
    }

    private func relativeTimeLabel(from date: Date?) -> String {
        guard let date else { return "il y a quelques min" }
        let minutes = max(0, Int(Date().timeIntervalSince(date) / 60))
        if minutes < 1 { return "à l’instant" }
        if minutes < 60 { return "il y a \(minutes) min" }
        return "il y a \(minutes / 60) h"
    }

    private func eventTimeLabel(for event: TransportEventImpactDTO) -> String {
        if let phase = event.phaseLabel, !phase.isEmpty {
            return phase
        }
        if let startsAt = event.startsAt {
            let formatter = DateFormatter()
            formatter.locale = AppLocale.current
            formatter.dateFormat = "HH:mm"
            return formatter.string(from: startsAt)
        }
        return "—"
    }

    private func summaryCarousel(_ summary: TransportPerturbationSummaryDTO) -> some View {
        let items = networkIssueCarouselItems(for: summary)

        return ReportsCarousel(
            items: items,
            activeIndex: $activeNetworkCarouselIndex,
            reduceMotion: reduceMotion,
            stopContext: dossierStopContext(for:),
            onEnsureLineDetail: ensureLineDetail(for:),
            onOpenSummary: { isShowingSummary = true }
        )
    }

    private func networkIssueCarouselItems(for summary: TransportPerturbationSummaryDTO) -> [NetworkIssueCarouselItem] {
        let officialItems = currentOfficialIncidents
            .filter { incident in
                let source = incident.source?.lowercased() ?? ""
                let isOfficial = source.contains("official") || source.contains("stib")
                let matchesLine = selectedLineFilter == "Tout"
                    || incident.line == selectedLineFilter
                    || incident.line == nil
                return isOfficial && matchesLine
            }
            .prefix(8)
            .compactMap { incident -> NetworkIssueCarouselItem? in
                let structuredLines = sanitizedLines([incident.line].compactMap { $0 })
                let extractedLines = ReportsLineExtraction.extract(from: [
                    incident.type,
                    incident.description,
                    incident.stop?.name,
                ].compactMap { $0 }.joined(separator: " "))
                let summaryLines = sanitizedLines(Array(summary.affectedLines.prefix(4)))
                let lines = !structuredLines.isEmpty
                    ? structuredLines
                    : (!extractedLines.isEmpty ? extractedLines : summaryLines)
                guard matchesSelectedMode(lines: lines) else { return nil }
                return NetworkIssueCarouselItem(
                    id: "official-\(incident.id)",
                    keyword: issueKeyword(from: incident.type ?? incident.description ?? summary.shortText),
                    detail: incident.description ?? summary.shortText,
                    lines: lines,
                    location: incident.stop?.name,
                    sourceLabel: "Officiel STIB",
                    tint: DS.Color.statusMinor
                )
            }

        if !officialItems.isEmpty {
            return Array(officialItems)
        }

        var items: [NetworkIssueCarouselItem] = []

        if let crowding = summary.crowdingRisk {
            items.append(
                NetworkIssueCarouselItem(
                    id: "crowding",
                    keyword: issueKeyword(from: crowding.title),
                    detail: crowding.shortText,
                    lines: crowding.impactedLines.isEmpty ? summary.affectedLines : crowding.impactedLines,
                    location: crowding.zoneLabel,
                    sourceLabel: "Affluence",
                    tint: summaryDotColor(for: summary)
                )
            )
        }

        let bullets = summary.bullets.isEmpty ? [summary.shortText] : summary.bullets
        items += bullets.prefix(6).enumerated().map { index, bullet in
            NetworkIssueCarouselItem(
                id: "summary-\(index)",
                keyword: issueKeyword(from: bullet),
                detail: bullet,
                lines: summary.affectedLines,
                location: summary.affectedStops.first,
                sourceLabel: sourcePreviewTitle(for: summary),
                tint: summaryDotColor(for: summary)
            )
        }

        if items.isEmpty {
            items.append(
                NetworkIssueCarouselItem(
                    id: "summary-fallback",
                    keyword: issueKeyword(from: summary.shortText),
                    detail: summary.shortText,
                    lines: summary.affectedLines,
                    location: summary.affectedStops.first,
                    sourceLabel: sourcePreviewTitle(for: summary),
                    tint: summaryDotColor(for: summary)
                )
            )
        }

        return items.map(enrichLines(in:))
    }

    /// Some upstream payloads omit `incident.line` (especially for "Travaux"-
    /// type announcements where the line number lives only in the description).
    /// Fall back to a regex-based scan over keyword + detail so the dossier
    /// card still renders the right badge / colour / stops.
    private func enrichLines(in item: NetworkIssueCarouselItem) -> NetworkIssueCarouselItem {
        let cleaned = sanitizedLines(item.lines)
        guard cleaned.isEmpty else {
            guard cleaned != item.lines else { return item }
            return NetworkIssueCarouselItem(
                id: item.id,
                keyword: item.keyword,
                detail: item.detail,
                lines: cleaned,
                location: item.location,
                sourceLabel: item.sourceLabel,
                tint: item.tint
            )
        }

        let extracted = ReportsLineExtraction.extract(from: item.keyword + " " + item.detail)
        guard !extracted.isEmpty else { return item }
        return NetworkIssueCarouselItem(
            id: item.id,
            keyword: item.keyword,
            detail: item.detail,
            lines: extracted,
            location: item.location,
            sourceLabel: item.sourceLabel,
            tint: item.tint
        )
    }

    /// Normalised short line code — strips a ":City"/":Suburb" suffix and a
    /// leading T/B/M mode prefix, uppercased, so an event's impactedLines
    /// match the filter chips regardless of formatting ("T82", "82:City" → "82").
    private static func shortLineCode(_ raw: String) -> String {
        var token = raw
        if let colon = token.range(of: ":") { token = String(token[..<colon.lowerBound]) }
        token = token.trimmingCharacters(in: .whitespaces).uppercased()
        if let first = token.first, "TBM".contains(first), token.dropFirst().allSatisfy(\.isNumber) {
            token = String(token.dropFirst())
        }
        return token
    }

    private func sanitizedLines(_ lines: [String]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { raw in
            let value = raw.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
            guard !value.isEmpty, value != "?" else { return nil }
            guard !seen.contains(value) else { return nil }
            seen.insert(value)
            return value
        }
    }

    private func issueKeyword(from text: String) -> String {
        let value = text.lowercased()
        if value.contains("interrompu") || value.contains("interruption") { return "Interrompu" }
        if value.contains("travaux") || value.contains("works") { return "Travaux" }
        if value.contains("dévi") || value.contains("devi") { return "Dévié" }
        if value.contains("retard") || value.contains("attente") { return "Retard" }
        if value.contains("bondé") || value.contains("affluence") || value.contains("plein") { return "Affluence" }
        if value.contains("accident") || value.contains("collision") { return "Accident" }
        if value.contains("arrêt") || value.contains("halte") { return "Arrêt touché" }
        return "À vérifier"
    }

    private func summaryDotColor(for summary: TransportPerturbationSummaryDTO) -> Color {
        if let crowding = summary.crowdingRisk {
            switch crowding.level.lowercased() {
            case "high":
                return DS.Color.statusMajor
            case "moderate":
                return DS.Color.statusMinor
            default:
                break
            }
        }
        if !summary.affectedLines.isEmpty {
            return DS.Color.statusMinor
        }
        return summary.sourceLabel?.lowercased() == "officiel" ? DS.Color.statusOK : DS.Color.community
    }

    private func sourcePreviewTitle(for summary: TransportPerturbationSummaryDTO) -> String {
        switch summary.sourceLabel?.lowercased() {
        case "officiel":
            return "Officiel"
        case "communauté":
            return "Communauté"
        default:
            return "Mixte"
        }
    }

    private func sourcePreviewTint(for summary: TransportPerturbationSummaryDTO) -> Color {
        switch summary.sourceLabel?.lowercased() {
        case "officiel":
            return DS.Color.paper.opacity(0.9)
        case "communauté":
            return DS.Color.community.opacity(0.18)
        default:
            return DS.Color.paper.opacity(0.75)
        }
    }

    private func crowdingBadgeTitle(for risk: TransportCrowdingRiskDTO) -> String {
        switch risk.level {
        case "high":
            return "Affluence forte"
        case "moderate":
            return "Affluence probable"
        default:
            return "Affluence à surveiller"
        }
    }

    private func crowdingBadgeTint(for risk: TransportCrowdingRiskDTO) -> Color {
        switch risk.level {
        case "high":
            return DS.Color.statusCritical.opacity(0.18)
        case "moderate":
            return DS.Color.statusMinor.opacity(0.25)
        default:
            return DS.Color.statusOK.opacity(0.18)
        }
    }
}

private struct EditorialPingDot: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.75))
                .frame(width: 8, height: 8)
                .scaleEffect(animate ? 2.2 : 1)
                .opacity(animate ? 0 : 0.75)
            Circle()
                .fill(color)
                .frame(width: 8, height: 8)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.2).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

private struct EditorialNowCard: View {
    let item: EditorialNowItem

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            LineBadge(line: item.line, size: .lg)
            VStack(alignment: .leading, spacing: 2) {
                Text("Officiel STIB")
                    .font(DS.Font.monoSmall)
                    .tracking(1.4)
                    .foregroundStyle(DS.Color.statusMajor)
                Text(item.reason)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(3)
                    .multilineTextAlignment(.leading)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(width: 260, alignment: .topLeading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

struct EditorialLineGroupCard<NestedContent: View>: View {
    let group: EditorialLineGroup
    let isExpanded: Bool
    let isFavoriteLine: Bool
    let onToggle: () -> Void
    @ViewBuilder let nestedContent: NestedContent

    private var officialCount: Int {
        group.items.filter { $0.type == .official || $0.type == .mixed }.count
    }

    private var communityCount: Int {
        group.items.filter { $0.type == .community || $0.type == .mixed }.count
    }

    private var headline: String {
        let count = group.items.count
        if count == 1 {
            return group.items.first?.body ?? group.items.first?.title ?? "Information réseau"
        }
        return "\(count) infos à vérifier sur cette ligne"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button(action: onToggle) {
                HStack(alignment: .center, spacing: 12) {
                    LineBadge(line: group.line, size: .lg)

                    VStack(alignment: .leading, spacing: 5) {
                        HStack(spacing: 6) {
                            Text("Ligne \(group.line)")
                                .font(DS.Font.bodyBold)
                                .foregroundStyle(DS.Color.ink)
                            if isFavoriteLine {
                                ReportsMetaBadge(title: "Concerne ta ligne", tint: DS.Color.statusMinor.opacity(0.18))
                            }
                        }

                        Text(headline)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkSoft)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 6) {
                            if officialCount > 0 {
                                ReportsMetaBadge(title: "\(officialCount) officiel", tint: DS.Color.statusMajor.opacity(0.12))
                            }
                            if communityCount > 0 {
                                ReportsMetaBadge(title: "\(communityCount) communauté", tint: DS.Color.community.opacity(0.12))
                            }
                        }
                    }

                    Spacer(minLength: 8)

                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if isExpanded {
                nestedContent
                    .padding(.top, 2)
            }
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(isFavoriteLine ? DS.Color.statusMinor.opacity(0.42) : DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(DS.Shadow.raised)
    }
}

struct EditorialFeedCard: View {
    let item: EditorialFeedItem
    var isFavoriteLine: Bool = false
    var isVoting: Bool = false
    var hasUpvoted: Bool = false
    var isNotificationLoading: Bool = false
    var isNotificationEnabled: Bool = false
    var onUpvote: ((SignalementDTO) -> Void)? = nil
    var onNotifyLine: ((String) -> Void)? = nil

    private var meta: EditorialTypeMeta { .for(item.type) }

    private var affluence: Double? {
        guard item.type == .event,
              let attendance = item.attendance,
              let capacity = item.venueCapacity,
              capacity > 0 else { return nil }
        return min(1.0, Double(attendance) / Double(capacity))
    }

    var body: some View {
        switch item.type {
        case .event:
            eventCard
        case .official, .community, .mixed:
            reportCard
        }
    }

    private var eventCard: some View {
        HStack(spacing: 0) {
            Rectangle()
                .fill(meta.stripe)
                .frame(width: meta.stripeWidth)

            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: meta.iconSystemName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(meta.accent)
                    Text(meta.label)
                        .font(DS.Font.monoSmall)
                        .tracking(1.4)
                        .foregroundStyle(meta.accent)
                    Text("·")
                        .foregroundStyle(DS.Color.inkMute.opacity(0.6))
                    Text(item.timeLabel)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)

                    if let up = item.upvotes {
                        Spacer()
                        HStack(spacing: 2) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 10, weight: .bold))
                            Text("\(up)")
                                .font(DS.Font.monoSmall.weight(.bold))
                        }
                        .foregroundStyle(DS.Color.ink)
                    }
                }

                Text(item.title)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .multilineTextAlignment(.leading)

                if let body = item.body {
                    Text(body)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkSoft)
                        .lineLimit(2)
                        .multilineTextAlignment(.leading)
                }

                if !item.lines.isEmpty || item.location != nil || item.url != nil {
                    HStack(spacing: 8) {
                        ForEach(Array(item.lines.prefix(5)), id: \.self) { line in
                            LineBadge(line: line, size: .sm)
                        }
                        if let location = item.location {
                            HStack(spacing: 4) {
                                Image(systemName: "mappin")
                                    .font(.system(size: 10))
                                Text(location)
                                    .lineLimit(1)
                            }
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.inkMute)
                        }
                        if let url = item.url {
                            Spacer()
                            Link(destination: url) {
                                HStack(spacing: 4) {
                                    Text("Billetterie")
                                        .font(DS.Font.bodySmall.weight(.semibold))
                                        .underline()
                                    Image(systemName: "arrow.up.right.square")
                                        .font(.system(size: 10))
                                }
                                .foregroundStyle(DS.Color.ink)
                            }
                        }
                    }
                    .padding(.top, 2)
                }

                if let affluence {
                    HStack(spacing: 8) {
                        Text("Affluence prévue")
                            .font(DS.Font.monoSmall)
                            .tracking(1.4)
                            .foregroundStyle(DS.Color.inkMute)
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Rectangle()
                                    .fill(DS.Color.paper2)
                                    .overlay(Rectangle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                                Rectangle()
                                    .fill(DS.Color.event)
                                    .frame(width: geo.size.width * affluence)
                            }
                        }
                        .frame(height: 4)
                    }
                    .padding(.top, 2)
                }
            }
            .padding(.leading, 12)
            .padding(.trailing, 14)
            .padding(.vertical, 14)
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .shadow(DS.Shadow.raised)
    }

    private var reportCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                sourceAvatar

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline, spacing: 7) {
                        Text(sourceTitle)
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)
                        Text(sourceHandle)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                        Text("·")
                            .foregroundStyle(DS.Color.inkMute.opacity(0.65))
                        Text(item.timeLabel)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }

                    HStack(spacing: 6) {
                        Image(systemName: sourceBadgeIcon)
                            .font(.system(size: 10, weight: .semibold))
                        Text(sourceBadgeTitle)
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(1.4)
                    }
                    .foregroundStyle(sourceBadgeColor)

                    if isFavoriteLine {
                        HStack(spacing: 5) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text("CONCERNE TA LIGNE")
                                .font(DS.Font.monoSmall.weight(.bold))
                                .tracking(1.2)
                        }
                        .foregroundStyle(DS.Color.statusMajor)
                    }
                }

                Spacer()
            }

            Text(primaryText)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .multilineTextAlignment(.leading)
                .padding(.top, 12)
                .fixedSize(horizontal: false, vertical: true)

            if !item.lines.isEmpty || item.location != nil {
                HStack(spacing: 8) {
                    ForEach(Array(item.lines.prefix(3)), id: \.self) { line in
                        LineBadge(line: line, size: .sm)
                    }

                    if let location = item.location {
                        HStack(spacing: 4) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10, weight: .semibold))
                            Text(location)
                                .lineLimit(1)
                        }
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                    }

                    Spacer(minLength: 0)
                }
                .padding(.top, 12)
            }

            HStack(spacing: 16) {
                if item.type == .community || item.type == .mixed,
                   let report = item.report {
                    Button {
                        onUpvote?(report)
                    } label: {
                        HStack(spacing: 5) {
                            if isVoting {
                                ProgressView()
                                    .scaleEffect(0.62)
                                    .tint(hasUpvoted ? DS.Color.primary : DS.Color.inkMute)
                            } else {
                                Image(systemName: hasUpvoted ? "arrow.up.circle.fill" : "arrow.up")
                                    .font(.system(size: 12, weight: .bold))
                            }
                            Text("\(item.upvotes ?? 0)")
                                .font(DS.Font.bodySmall.weight(.semibold))
                        }
                        .foregroundStyle(hasUpvoted ? DS.Color.primary : DS.Color.inkMute)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(hasUpvoted ? DS.Color.primary.opacity(0.10) : DS.Color.paper2.opacity(0.55))
                        .overlay(
                            Capsule()
                                .stroke(hasUpvoted ? DS.Color.primary.opacity(0.35) : DS.Color.ink.opacity(0.12), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .disabled(isVoting || hasUpvoted)
                } else if let up = item.upvotes {
                    HStack(spacing: 4) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .bold))
                        Text("\(up)")
                            .font(DS.Font.bodySmall.weight(.semibold))
                    }
                    .foregroundStyle(DS.Color.inkMute)
                }

                if let report = item.report, let confirmationText = report.confirmationsSummaryLabel {
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(confirmationText)
                            .lineLimit(1)
                    }
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                } else if item.type == .official || item.type == .mixed {
                    HStack(spacing: 4) {
                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 11, weight: .semibold))
                        Text(item.type == .official ? "Certifié STIB" : "Signal croisé")
                    }
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(item.type == .official ? DS.Color.statusMajor : DS.Color.statusMinor)
                }

                if (item.type == .official || item.type == .mixed),
                   let line = item.lines.first {
                    Button {
                        onNotifyLine?(line)
                    } label: {
                        HStack(spacing: 4) {
                            if isNotificationLoading {
                                ProgressView()
                                    .scaleEffect(0.58)
                            } else {
                                Image(systemName: isNotificationEnabled ? "bell.fill" : "bell")
                                    .font(.system(size: 11, weight: .semibold))
                            }
                            Text(isNotificationEnabled ? "Suivie" : "Me prévenir")
                        }
                        .font(DS.Font.bodySmall.weight(.semibold))
                        .foregroundStyle(isNotificationEnabled ? DS.Color.statusMinor : DS.Color.ink)
                    }
                    .buttonStyle(.plain)
                    .disabled(isNotificationLoading || isNotificationEnabled)
                }

                Spacer()

                Text(reportFooterTag)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute.opacity(0.8))
            }
            .padding(.top, 14)
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        .shadow(DS.Shadow.raised)
    }

    private var primaryText: String {
        let preferred = (item.body?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty == false)
            ? item.body
            : item.title
        return preferred ?? item.title
    }

    private var sourceTitle: String {
        switch item.type {
        case .community:
            return "Voyageur · Bruxelles"
        case .official:
            return "STIB · Info trafic"
        case .mixed:
            return "Signal croisé"
        case .event:
            return meta.label
        }
    }

    private var sourceHandle: String {
        switch item.type {
        case .community:
            return "@communauté"
        case .official:
            return "@stib"
        case .mixed:
            return "@mixte"
        case .event:
            return "@événement"
        }
    }

    private var sourceBadgeTitle: String {
        switch item.type {
        case .community:
            return "COMMUNAUTÉ"
        case .official:
            return "CERTIFIÉ STIB"
        case .mixed:
            return "OFFICIEL + TERRAIN"
        case .event:
            return meta.label.uppercased()
        }
    }

    private var sourceBadgeIcon: String {
        switch item.type {
        case .community:
            return "person.2"
        case .official:
            return "checkmark.seal.fill"
        case .mixed:
            return "exclamationmark.triangle.fill"
        case .event:
            return meta.iconSystemName
        }
    }

    private var sourceBadgeColor: Color {
        switch item.type {
        case .community:
            return DS.Color.community
        case .official:
            return DS.Color.statusMajor
        case .mixed:
            return DS.Color.statusMinor
        case .event:
            return DS.Color.event
        }
    }

    @ViewBuilder
    private var sourceAvatar: some View {
        switch item.type {
        case .community:
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Color.paper)
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    Text("V.")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                )
        case .official:
            RoundedRectangle(cornerRadius: 12)
                .fill(DS.Color.paper)
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Color.statusMajor.opacity(0.35), lineWidth: 1)
                )
                .overlay(
                    ZStack(alignment: .bottomTrailing) {
                        Circle()
                            .fill(Color(red: 0.03, green: 0.33, blue: 0.64))
                            .frame(width: 28, height: 28)
                            .overlay(
                                Text("B")
                                    .font(.system(size: 16, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                            )

                        Image(systemName: "checkmark.seal.fill")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Color.statusMajor)
                            .background(DS.Color.paper.clipShape(Circle()))
                            .offset(x: 4, y: 4)
                    }
                )
        case .mixed:
            RoundedRectangle(cornerRadius: 12)
                .fill(
                    LinearGradient(
                        colors: [DS.Color.statusMajor.opacity(0.14), DS.Color.community.opacity(0.14)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 52, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                )
                .overlay(
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.statusMajor)
                )
        case .event:
            EmptyView()
        }
    }

    private var reportFooterTag: String {
        switch item.type {
        case .community:
            return "#com"
        case .official:
            return "#stib"
        case .mixed:
            return "#mixte"
        case .event:
            return "#event"
        }
    }
}

private struct EditorialTypeMeta {
    let label: String
    let iconSystemName: String
    let stripe: AnyShapeStyle
    let stripeWidth: CGFloat
    let accent: Color

    static func `for`(_ type: EditorialFeedItemType) -> EditorialTypeMeta {
        switch type {
        case .official:
            return .init(label: "Officiel STIB", iconSystemName: "shield.fill", stripe: AnyShapeStyle(DS.Color.statusMajor), stripeWidth: 4, accent: DS.Color.statusMajor)
        case .community:
            return .init(label: "Communauté", iconSystemName: "person.2.fill", stripe: AnyShapeStyle(DS.Color.community), stripeWidth: 4, accent: DS.Color.community)
        case .mixed:
            return .init(label: "Officiel + confirmé", iconSystemName: "exclamationmark.triangle.fill", stripe: AnyShapeStyle(LinearGradient(colors: [DS.Color.statusMajor, DS.Color.community], startPoint: .top, endPoint: .bottom)), stripeWidth: 6, accent: DS.Color.statusMajor)
        case .event:
            return .init(label: "Événement Bruxelles", iconSystemName: "ticket.fill", stripe: AnyShapeStyle(DS.Color.event), stripeWidth: 4, accent: DS.Color.event)
        }
    }
}

private struct EventImpactDetailSheet: View {
    let event: TransportEventImpactDTO
    let relatedEvents: [TransportEventImpactDTO]

    @EnvironmentObject private var nav: AppNavigation
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var nearbyStops: [NearbyStop] = []
    @State private var isLoadingNearbyStops = false

    private var venueTitle: String {
        event.venue ?? event.zoneLabel ?? "Lieu à Bruxelles"
    }

    private var addressLine: String {
        event.address ?? event.zoneLabel ?? "Bruxelles"
    }

    private var displayedEvents: [TransportEventImpactDTO] {
        relatedEvents.isEmpty ? [event] : relatedEvents
    }

    private var canonicalStopRows: [EventStopRow] {
        let local = (event.impactedStopDetails ?? []).map {
            EventStopRow(id: $0.id ?? $0.stopId, name: $0.name, distanceMeters: nil)
        }
        let fetched = nearbyStops.map {
            EventStopRow(id: $0.backendId, name: $0.name, distanceMeters: $0.distanceMeters)
        }

        var rows: [EventStopRow] = []
        var seen = Set<String>()
        for item in local + fetched {
            let key = (item.id ?? item.name).lowercased()
            guard !seen.contains(key) else { continue }
            seen.insert(key)
            rows.append(item)
        }
        return rows
    }

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    heroCard
                    actions
                    if !event.impactedLines.isEmpty { linesSection }
                    nearbyStopsSection
                    programmingSection
                }
                .padding(.horizontal, 20)
                .padding(.top, 16)
                .padding(.bottom, 36)
            }
        }
        .modifier(PaperGrainBackground())
        .task {
            await loadNearbyStops()
        }
    }

    private var heroCard: some View {
        VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("LIEU")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                Text(venueTitle)
                    .font(DS.Font.displayH2)
                    .foregroundColor(DS.Color.ink)

                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "mappin.and.ellipse")
                        .font(.system(size: 11))
                        .foregroundColor(DS.Color.inkSoft)
                        .padding(.top, 2)
                    Text(addressLine)
                        .font(DS.Font.bodySmall)
                        .foregroundColor(DS.Color.inkSoft)
                }
                .padding(.top, 4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, 12)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.15))
                .frame(height: 1.5)
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                heroStat(icon: "person.2.fill", label: "CAPACITÉ", value: formatNumber(event.expectedAttendance ?? 0))
                Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(width: 1)
                heroStat(icon: "calendar", label: "À VENIR", value: "\(displayedEvents.count)")
                Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(width: 1)
                heroStat(icon: "map", label: "ARRÊTS", value: "\(canonicalStopRows.count)")
            }

            if let note = event.notesFr, !note.isEmpty {
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.12))
                    .frame(height: 1)
                    .padding(.horizontal, 16)

                Text("« \(note) »")
                    .font(.system(size: 12).italic())
                    .foregroundColor(DS.Color.inkSoft)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
            }
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }

    private func heroStat(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 11))
                .foregroundColor(DS.Color.inkMute)
            Text(value)
                .font(DS.Font.monoLarge.weight(.bold))
                .foregroundColor(DS.Color.ink)
            Text(label)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
    }

    private var actions: some View {
        HStack(spacing: 8) {
            Button(action: openDirections) {
                HStack(spacing: 6) {
                    Image(systemName: "location.fill").font(.system(size: 13))
                    Text("Itinéraire").font(.system(size: 12.5, weight: .bold))
                }
                .frame(maxWidth: .infinity, minHeight: 44)
                .foregroundColor(DS.Color.ink)
                .background(DS.Color.paper)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink, lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
            .buttonStyle(PressableScaleStyle())

            if let raw = event.url, let url = URL(string: raw) {
                Link(destination: url) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.up.right.square").font(.system(size: 13))
                        Text("Site officiel").font(.system(size: 12.5, weight: .bold))
                    }
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .foregroundColor(DS.Color.ink)
                    .background(DS.Color.paper)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.25), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                }
            }
        }
    }

    private var linesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("LIGNES DESSERVANT LE LIEU")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
                .padding(.horizontal, 4)

            ReportsFlowLayout(horizontalSpacing: 8, verticalSpacing: 8) {
                ForEach(event.impactedLines, id: \.self) { line in
                    Button {
                        nav.pendingLineFocus = line
                        nav.currentPage = .signalements
                        dismiss()
                    } label: {
                        LineBadge(line: line, size: .lg)
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
            .padding(12)
            .background(DS.Color.paper)
            .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    private var nearbyStopsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("ARRÊTS À PROXIMITÉ")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
                .padding(.horizontal, 4)

            if isLoadingNearbyStops && canonicalStopRows.isEmpty {
                SkeletonList(count: 3, rowSpacing: 8, style: .row)
                    .padding(.vertical, 8)
                    .background(DS.Color.paper)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            } else if canonicalStopRows.isEmpty {
                Text("Aucun arrêt STIB dans le rayon défini.")
                    .font(DS.Font.bodySmall)
                    .foregroundColor(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(DS.Color.paper)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(canonicalStopRows.enumerated()), id: \.element.name) { idx, stop in
                        if idx > 0 {
                            Rectangle().fill(DS.Color.ink.opacity(0.12)).frame(height: 1)
                        }
                        Button {
                            openStop(stop)
                        } label: {
                            HStack(spacing: 12) {
                                Text(stop.distanceMeters.map(formatDistance) ?? "—")
                                    .font(DS.Font.monoSmall.weight(.bold))
                                    .foregroundColor(DS.Color.inkMute)
                                    .monospacedDigit()
                                    .frame(width: 48, alignment: .leading)
                                Text(stop.name)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundColor(DS.Color.ink)
                                    .lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                HStack(spacing: 4) {
                                    ForEach(linesForStop(stop).prefix(4), id: \.self) { line in
                                        LineBadge(line: line, size: .sm)
                                    }
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 12)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(PressableRowStyle())
                        .disabled(stop.id == nil)
                    }
                }
                .background(DS.Color.paper)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
        }
    }

    private var programmingSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROGRAMMATION")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundColor(DS.Color.inkMute)
                .tracking(1)
                .padding(.horizontal, 4)

            if displayedEvents.isEmpty {
                Text("Aucun événement annoncé.")
                    .font(DS.Font.bodySmall)
                    .foregroundColor(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .padding(16)
                    .background(DS.Color.paper)
                    .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            } else {
                VStack(spacing: 0) {
                    ForEach(Array(displayedEvents.enumerated()), id: \.element.id) { idx, item in
                        if idx > 0 {
                            Rectangle().fill(DS.Color.ink.opacity(0.12)).frame(height: 1)
                        }
                        programmingRow(item)
                    }
                }
                .background(DS.Color.paper)
                .overlay(RoundedRectangle(cornerRadius: DS.Radius.md).stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
            }
        }
    }

    private func programmingRow(_ item: TransportEventImpactDTO) -> some View {
        let date = item.startsAt ?? Date()
        let day = Calendar.current.component(.day, from: date)
        let monthFormatter = DateFormatter()
        monthFormatter.locale = AppLocale.current
        monthFormatter.dateFormat = "MMM"
        let month = monthFormatter.string(from: date).replacingOccurrences(of: ".", with: "").uppercased()

        let content = HStack(spacing: 12) {
            VStack(spacing: 4) {
                Text("\(day)")
                    .font(DS.Font.monoLarge.weight(.bold))
                    .foregroundColor(DS.Color.ink)
                Text(month)
                    .font(DS.Font.monoSmall.weight(.bold))
                    .foregroundColor(DS.Color.inkMute)
                    .tracking(1)
            }
            .frame(width: 48)

            Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(width: 1, height: 40)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text((item.category ?? "event").uppercased())
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundColor(DS.Color.primaryForeground)
                        .tracking(1)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 2)
                        .background(categoryColor(item.category))
                        .clipShape(RoundedRectangle(cornerRadius: 3))
                    if let startsAt = item.startsAt {
                        Text(timeLabel(for: startsAt))
                            .font(DS.Font.mono)
                            .foregroundColor(DS.Color.inkMute)
                    }
                    if item.soldOut == true {
                        Text("COMPLET")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .foregroundColor(DS.Color.destructive)
                    }
                    if item.phase == "cancelled" {
                        Text("ANNULÉ")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .foregroundColor(DS.Color.inkMute)
                            .strikethrough()
                    }
                }
                Text(item.title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundColor(DS.Color.ink)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            if item.url != nil {
                Image(systemName: "arrow.up.right.square")
                    .font(.system(size: 11))
                    .foregroundColor(DS.Color.inkMute)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())

        return Group {
            if let raw = item.url, let url = URL(string: raw) {
                Link(destination: url) { content }
            } else {
                content
            }
        }
    }

    private func linesForStop(_ stop: EventStopRow) -> [String] {
        if let fetched = nearbyStops.first(where: { ($0.backendId ?? "").lowercased() == (stop.id ?? "").lowercased() }) {
            return fetched.lines.map(\.number)
        }
        return event.impactedLines
    }

    private func loadNearbyStops() async {
        guard let latitude = event.latitude, let longitude = event.longitude else { return }
        isLoadingNearbyStops = true
        defer { isLoadingNearbyStops = false }
        do {
            nearbyStops = try await NearbyStopService.fetchNearby(lat: latitude, lng: longitude, radius: 800)
        } catch {
            nearbyStops = []
        }
    }

    private func openDirections() {
        guard let latitude = event.latitude, let longitude = event.longitude else { return }
        if let url = URL(string: "http://maps.apple.com/?daddr=\(latitude),\(longitude)") {
            openURL(url)
        }
    }

    private func openStop(_ stop: EventStopRow) {
        guard let stopId = stop.id else { return }
        nav.pendingMapStopFocusBackendId = stopId
        nav.currentPage = .home
        dismiss()
    }

    private func categoryColor(_ value: String?) -> Color {
        switch value?.lowercased() {
        case "concert":
            return DS.Color.event
        case "sport":
            return DS.Color.statusMajor
        case "spectacle":
            return DS.Color.noctis
        case "festival":
            return DS.Color.primary
        case "expo":
            return DS.Color.accent
        case "conference":
            return DS.Color.community
        default:
            return DS.Color.accent
        }
    }

    private func timeLabel(for date: Date) -> String {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.dateFormat = "HH:mm"
        return formatter.string(from: date)
    }

    private func formatDistance(_ meters: Int) -> String {
        meters < 1000 ? "\(meters) m" : String(format: "%.1f km", Double(meters) / 1000)
    }

    private func formatNumber(_ n: Int) -> String {
        let formatter = NumberFormatter()
        formatter.locale = AppLocale.current
        formatter.numberStyle = .decimal
        return formatter.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private struct EventStopRow: Hashable {
    let id: String?
    let name: String
    let distanceMeters: Int?
}

private struct ReportsFlowLayout: Layout {
    var horizontalSpacing: CGFloat = 0
    var verticalSpacing: CGFloat = 0

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var currentX: CGFloat = 0
        var currentY: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if currentX + size.width > maxWidth, currentX > 0 {
                currentX = 0
                currentY += rowHeight + verticalSpacing
                rowHeight = 0
            }

            rowHeight = max(rowHeight, size.height)
            currentX += size.width + horizontalSpacing
        }

        return CGSize(width: maxWidth.isFinite ? maxWidth : currentX, height: currentY + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var point = CGPoint(x: bounds.minX, y: bounds.minY)
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if point.x + size.width > bounds.maxX, point.x > bounds.minX {
                point.x = bounds.minX
                point.y += rowHeight + verticalSpacing
                rowHeight = 0
            }

            subview.place(at: point, proposal: ProposedViewSize(size))
            point.x += size.width + horizontalSpacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}

private struct ReportsSummarySheet: View {
    let summary: TransportPerturbationSummaryDTO
    let lineLabel: String?

    @State private var didCopy = false

    var body: some View {
        ZStack {
            DS.Color.background
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lineLabel.map { "Résumé ligne \($0)" } ?? "Résumé perturbations")
                            .displayH2()

                        HStack(alignment: .center, spacing: 10) {
                            HStack(spacing: 8) {
                                ReportsMetaBadge(
                                    title: sourceBadgeTitle,
                                    tint: sourceBadgeTint
                                )

                                if let source = summary.source, !source.isEmpty {
                                    ReportsMetaBadge(
                                        title: source.uppercased(),
                                        tint: DS.Color.secondary
                                    )
                                }
                            }

                            Spacer()

                            HStack(spacing: 8) {
                                Button {
                                    copySummary()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(didCopy ? "Copié" : "Copier")
                                            .font(DS.Font.monoSmall.weight(.bold))
                                    }
                                    .foregroundStyle(DS.Color.ink)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(DS.Color.paper)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(DS.Color.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary.title)
                            .font(DS.Font.displayH3)
                            .foregroundStyle(DS.Color.primary)

                        Text(summary.longText)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.inkSoft)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(DS.Spacing.xl)
                    .background(DS.Color.paper)
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(DS.Color.border, lineWidth: DS.Stroke.hairline)
                    )
                    .shadow(DS.Shadow.raised)

                    if !summary.affectedLines.isEmpty {
                        summarySection(title: "Lignes les plus touchées") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                                ForEach(summary.affectedLines, id: \.self) { line in
                                    LineBadge(line: line, size: .sm)
                                }
                            }
                        }
                    }

                    if !summary.affectedStops.isEmpty {
                        summarySection(title: "Zones / arrêts clés") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(summary.affectedStops, id: \.self) { stop in
                                    Text(stop)
                                        .font(DS.Font.body)
                                        .foregroundStyle(DS.Color.inkSoft)
                                }
                            }
                        }
                    }

                    if let incidentTypes = summary.incidentTypes, !incidentTypes.isEmpty {
                        summarySection(title: "Types dominants") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                                ForEach(incidentTypes, id: \.self) { type in
                                    ReportsMetaBadge(title: type, tint: DS.Color.secondary)
                                }
                            }
                        }
                    }

                    if let sourceBreakdown = summary.sourceBreakdown {
                        summarySection(title: "Origine des signaux") {
                            VStack(alignment: .leading, spacing: 10) {
                                SourceBreakdownRow(label: "Officiel STIB", value: sourceBreakdown.official ?? 0, tint: DS.Color.statusMajor)
                                SourceBreakdownRow(label: "Communauté", value: sourceBreakdown.community ?? 0, tint: DS.Color.community)
                                if (sourceBreakdown.mixed ?? 0) > 0 {
                                    SourceBreakdownRow(label: "Sources mixtes", value: sourceBreakdown.mixed ?? 0, tint: DS.Color.statusMinor)
                                }
                            }
                        }
                    }

                    if let crowdingRisk = summary.crowdingRisk, crowdingRisk.level != "none" {
                        summarySection(title: "Affluence probable") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    ReportsMetaBadge(
                                        title: crowdingRiskBadgeTitle(crowdingRisk),
                                        tint: crowdingRiskBadgeTint(crowdingRisk)
                                    )

                                    if let zoneLabel = crowdingRisk.zoneLabel, !zoneLabel.isEmpty {
                                        ReportsMetaBadge(
                                            title: zoneLabel,
                                            tint: DS.Color.secondary
                                        )
                                    }
                                }

                                Text(crowdingRisk.longText)
                                    .font(DS.Font.body)
                                    .foregroundStyle(DS.Color.inkSoft)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !crowdingRisk.eventNames.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Événements suivis")
                                            .font(DS.Font.eyebrow)
                                            .foregroundStyle(DS.Color.inkMute)
                                        ForEach(crowdingRisk.eventNames, id: \.self) { event in
                                            Text(event)
                                                .font(DS.Font.body)
                                                .foregroundStyle(DS.Color.inkSoft)
                                        }
                                    }
                                }

                                if !crowdingRisk.impactedLines.isEmpty {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                                        ForEach(crowdingRisk.impactedLines.prefix(6), id: \.self) { line in
                                            LineBadge(line: line, size: .sm)
                                        }
                                    }
                                }
                            }
                        }
                    }

                    if !summary.bullets.isEmpty {
                        summarySection(title: "Lecture rapide") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(summary.bullets, id: \.self) { bullet in
                                    HStack(alignment: .top, spacing: 10) {
                                        Circle()
                                            .fill(DS.Color.primary)
                                            .frame(width: 7, height: 7)
                                            .padding(.top, 6)
                                        Text(bullet)
                                            .font(DS.Font.body)
                                            .foregroundStyle(DS.Color.inkSoft)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                            }
                        }
                    }
                }
                .padding(.horizontal, 21)
                .padding(.top, 28)
                .padding(.bottom, 36)
            }
        }
        .modifier(PaperGrainBackground())
    }

    private var sourceBadgeTitle: String {
        switch summary.sourceLabel?.lowercased() {
        case "officiel":
            return "Officiel"
        case "communauté":
            return "Communauté"
        default:
            return "Mixte"
        }
    }

    private var sourceBadgeTint: Color {
        switch summary.sourceLabel?.lowercased() {
        case "officiel":
            return DS.Color.statusMajor.opacity(0.18)
        case "communauté":
            return DS.Color.community.opacity(0.18)
        default:
            return DS.Color.statusMinor.opacity(0.22)
        }
    }

    private func crowdingRiskBadgeTitle(_ risk: TransportCrowdingRiskDTO) -> String {
        switch risk.level {
        case "high":
            return "Affluence forte"
        case "moderate":
            return "Affluence renforcée"
        default:
            return "Affluence possible"
        }
    }

    private func crowdingRiskBadgeTint(_ risk: TransportCrowdingRiskDTO) -> Color {
        switch risk.level {
        case "high":
            return DS.Color.statusCritical.opacity(0.18)
        case "moderate":
            return DS.Color.statusMinor.opacity(0.25)
        default:
            return DS.Color.statusOK.opacity(0.18)
        }
    }

    private func copySummary() {
        UIPasteboard.general.string = copyableSummary
        didCopy = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didCopy = false
        }
    }

    private var copyableSummary: String {
        var lines: [String] = []
        lines.append(lineLabel.map { "Résumé ligne \($0)" } ?? "Résumé perturbations")
        lines.append(summary.title)
        lines.append(summary.longText)

        if !summary.affectedLines.isEmpty {
            lines.append("Lignes touchées: \(summary.affectedLines.joined(separator: ", "))")
        }

        if !summary.affectedStops.isEmpty {
            lines.append("Zones clés: \(summary.affectedStops.joined(separator: ", "))")
        }

        if !summary.bullets.isEmpty {
            lines.append("Lecture rapide:")
            lines.append(contentsOf: summary.bullets.map { "• \($0)" })
        }

        if let sourceLabel = summary.sourceLabel {
            lines.append("Source: \(sourceLabel)")
        }

        return lines.joined(separator: "\n")
    }

    @ViewBuilder
    private func summarySection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(DS.Font.eyebrow)
                .tracking(1.4)
                .foregroundStyle(DS.Color.inkMute)

            content()
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.border, lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(DS.Shadow.raised)
    }
}

private struct ReportsMetaBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(DS.Font.monoSmall.weight(.bold))
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tint)
            .overlay(Capsule().stroke(DS.Color.ink.opacity(0.08), lineWidth: 1))
            .clipShape(Capsule())
    }
}

private struct SourceBreakdownRow: View {
    let label: String
    let value: Int
    let tint: Color

    var body: some View {
        HStack(spacing: 10) {
            Circle()
                .fill(tint)
                .frame(width: 9, height: 9)

            Text(label)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkSoft)

            Spacer()

            Text("\(value)")
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
        }
    }
}

// MARK: - Editorial status HUD components

private struct StatusCell: View {
    let label: String
    let value: String
    var sublabel: String? = nil
    var valueColor: Color = DS.Color.ink
    var pulse: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 4) {
                if pulse {
                    ReportsPulsingDot(color: valueColor, size: 4)
                }
                Text(label.uppercased())
                    .font(DS.Font.monoSmall.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
            }
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(value)
                    .font(.system(size: 15, weight: .bold, design: .monospaced))
                    .foregroundStyle(valueColor)
                if let sublabel {
                    Text(sublabel)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }
}

struct ReportsPulsingDot: View {
    let color: Color
    var size: CGFloat = 8
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.6))
                .frame(width: size, height: size)
                .scaleEffect(animate ? 2.2 : 1)
                .opacity(animate ? 0 : 0.7)
            Circle()
                .fill(color)
                .frame(width: size, height: size)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

// MARK: - Editorial dossier card

struct EditorialDossierCard: View {
    let item: NetworkIssueCarouselItem
    let index: Int
    let total: Int
    var stops: [String] = []
    var disruptedIndices: Set<Int> = []
    var disruptedStopName: String? = nil

    private var primaryLine: String { item.lines.first ?? "?" }

    private var lineKind: String {
        let trimmed = primaryLine.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        if trimmed.hasPrefix("T") { return "Tram" }
        if trimmed.hasPrefix("B") { return "Bus" }
        let cleaned = trimmed.allSatisfy(\.isNumber) ? trimmed : trimmed.filter(\.isNumber)
        guard let n = Int(cleaned) else { return "Ligne" }
        // STIB / MIVB Brussels classification
        let metros: Set<Int> = [1, 2, 5, 6]
        let trams: Set<Int> = [3, 4, 7, 8, 9, 10, 18, 19, 25, 32, 35, 39, 51, 55, 62, 81, 82, 92, 93, 97]
        if metros.contains(n) { return "Métro" }
        if trams.contains(n) { return "Tram" }
        return "Bus"
    }

    private var lineColor: Color {
        item.lines.isEmpty ? item.tint : TransitLinePalette.fill(for: primaryLine)
    }

    private var lineForeground: Color {
        item.lines.isEmpty ? .white : TransitLinePalette.foreground(for: primaryLine)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            DS.Color.paper

            // Stripe couleur ligne
            Rectangle()
                .fill(lineColor)
                .frame(width: 6)
                .frame(maxHeight: .infinity)

            // Étiquette dossier (top right)
            Text("DOSSIER · \(String(format: "%02d", index))/\(String(format: "%02d", total))")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .tracking(1.6)
                .foregroundStyle(DS.Color.paper)
                .padding(.horizontal, 8)
                .padding(.vertical, 3)
                .background(DS.Color.ink)
                .padding(.top, 10)
                .padding(.trailing, 12)
                .frame(maxWidth: .infinity, alignment: .trailing)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    HStack(spacing: 4) {
                        Image(systemName: "dot.radiowaves.left.and.right")
                            .font(.system(size: 8, weight: .heavy))
                        Text("LIVE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(DS.Color.statusMajor)
                    .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))

                    Text("\(lineKind.uppercased()) · STIB-MIVB")
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(DS.Color.inkMute)

                    Spacer()
                }
                .padding(.top, 14)

                HStack(alignment: .top, spacing: 10) {
                    Text(primaryLine)
                        .font(.system(size: 17, weight: .heavy, design: .monospaced))
                        .foregroundStyle(lineForeground)
                        .frame(width: 44, height: 44)
                        .background(lineColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(DS.Color.ink, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("PERTURBATION OFFICIELLE")
                            .font(.system(size: 9, weight: .bold))
                            .tracking(1.4)
                            .foregroundStyle(DS.Color.statusMajor)

                        Text(item.keyword)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(2)

                        if !item.detail.isEmpty {
                            Text(item.detail)
                                .font(.system(size: 11))
                                .foregroundStyle(DS.Color.inkSoft)
                                .lineLimit(2)
                                .padding(.top, 2)
                        }
                    }
                }

                EditorialLineVisualizer(
                    line: primaryLine,
                    color: lineColor,
                    stops: stops,
                    disruptedIndices: disruptedIndices,
                    disruptedStopName: disruptedStopName
                )
                .frame(height: 70)
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: DS.Color.ink.opacity(0.18), radius: 12, x: 0, y: 8)
    }
}

// `TransitOperator` + its row View now live in
// `View/Components/TransitOperatorRow.swift` so both Infos trafic and
// Horaires can share the same masthead.
