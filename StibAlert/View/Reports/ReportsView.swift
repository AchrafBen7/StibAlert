import SwiftUI
import UIKit

private enum ReportSegment: String, CaseIterable, Identifiable {
    case all, official, community, events
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Tout"
        case .official: return "Officiel"
        case .community: return "Communauté"
        case .events: return "Événements"
        }
    }
    var iconSystemName: String? {
        switch self {
        case .all: return nil
        case .official: return "shield.fill"
        case .community: return "person.2.fill"
        case .events: return "ticket.fill"
        }
    }
}

private enum EditorialFeedItemType {
    case official, community, mixed, event
}

private enum ReportTransportMode: String, CaseIterable, Identifiable {
    case all, metro, tram, bus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tous modes"
        case .metro: return "Métro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        }
    }

    var iconSystemName: String? {
        switch self {
        case .all: return nil
        case .metro: return "m.circle.fill"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        }
    }
}

private enum ReportSortMode: String, CaseIterable, Identifiable {
    case recent, urgent, personal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Plus récents"
        case .urgent: return "Plus urgents"
        case .personal: return "Mes lignes"
        }
    }
}

private struct EditorialNowItem: Identifiable {
    let id: String
    let line: String
    let reason: String
}

private struct NetworkIssueCarouselItem: Identifiable {
    let id: String
    let keyword: String
    let detail: String
    let lines: [String]
    let location: String?
    let sourceLabel: String
    let tint: Color
}

private struct EditorialFeedItem: Identifiable {
    let id: String
    let type: EditorialFeedItemType
    let title: String
    let body: String?
    let timeLabel: String
    let lines: [String]
    let location: String?
    let upvotes: Int?
    let url: URL?
    let attendance: Int?
    let venueCapacity: Int?
    let report: SignalementDTO?
    let event: TransportEventImpactDTO?
}

private struct EditorialLineGroup: Identifiable {
    let id: String
    let line: String
    let items: [EditorialFeedItem]
}

struct ReportsView: View {
    private enum ContentScope: String, CaseIterable, Identifiable {
        case reports
        case events

        var id: String { rawValue }

        var title: String {
            switch self {
            case .reports: return "Reports"
            case .events: return "Événements"
            }
        }
    }

    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedScope: ContentScope = .reports
    @State private var selectedSegment: ReportSegment = .all
    @State private var selectedModeFilter: ReportTransportMode = .all
    @State private var selectedSortMode: ReportSortMode = .recent
    @State private var reports: [SignalementDTO] = []
    @State private var events: [TransportEventImpactDTO] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
    @State private var lastUpdatedAt: Date? = nil
    @State private var loadError: String? = nil
    @State private var query = ""
    @State private var selectedLineFilter = "Tout"
    @State private var selectedReport: SignalementDTO? = nil
    @State private var selectedEvent: TransportEventImpactDTO? = nil
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

    private let networkCarouselTimer = Timer.publish(every: 4.5, on: .main, in: .common).autoconnect()

    private var favoriteLines: Set<String> {
        Set(session.currentUser?.favoriteLines ?? [])
    }

    private var availableLineFilters: [String] {
        let reportLines = reports.map(\.ligne)
        let eventLines = events.flatMap(\.impactedLines)
        let officialLines = (transportOverview?.activeIncidents ?? []).compactMap(\.line)
        let summaryLines = transportOverview?.perturbationSummary?.affectedLines ?? []
        let lines = Set(reportLines + eventLines + officialLines + summaryLines).sorted {
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
                || report.typeProbleme.localizedCaseInsensitiveContains(trimmed)
                || report.description.localizedCaseInsensitiveContains(trimmed)
                || stopName.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var filteredEvents: [TransportEventImpactDTO] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)

        return events.filter { event in
            let matchesLine = selectedLineFilter == "Tout" || event.impactedLines.contains(selectedLineFilter)
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

    private var feedItems: [EditorialFeedItem] {
        let reportItems = reports.compactMap { report -> EditorialFeedItem? in
            guard selectedLineFilter == "Tout" || report.ligne == selectedLineFilter else { return nil }
            return EditorialFeedItem(
                id: "report-\(report.id)",
                type: feedType(for: report),
                title: "Ligne \(report.ligne) — \(report.typeProbleme)",
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

        let officialTransportItems = shouldHideOfficialFeedDuplicates ? [] : officialTransportFeedItems

        let eventItems = events.compactMap { event -> EditorialFeedItem? in
            guard selectedLineFilter == "Tout" || event.impactedLines.contains(selectedLineFilter) else { return nil }
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

        let scopedItems: [EditorialFeedItem]
        switch selectedScope {
        case .reports:
            scopedItems = (reportItems + officialTransportItems).filter { item in
                switch selectedSegment {
                case .all: return true
                case .official: return item.type == .official || item.type == .mixed
                case .community: return item.type == .community || item.type == .mixed
                case .events: return false
                }
            }
        case .events:
            scopedItems = eventItems
        }

        return scopedItems
            .filter { item in
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
            .sorted(by: sortFeedItems)
    }

    private var shouldHideOfficialFeedDuplicates: Bool {
        selectedScope == .reports
            && selectedSegment == .all
            && selectedLineFilter == "Tout"
            && currentSummary != nil
    }

    private var shouldGroupFeedByLine: Bool {
        selectedScope == .reports && selectedLineFilter == "Tout"
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

    private var segmentCounts: [ReportSegment: Int] {
        [
            .all: feedItems.count,
            .official: feedItems.filter { $0.type == .official || $0.type == .mixed }.count,
            .community: feedItems.filter { $0.type == .community || $0.type == .mixed }.count,
            .events: feedItems.filter { $0.type == .event }.count
        ]
    }

    private var visibleLineFilters: [String] {
        Array(availableLineFilters.filter { $0 == "Tout" || matchesSelectedMode(lines: [$0]) }.prefix(40))
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

                    if let summary = currentSummary {
                        summaryCarousel(summary)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.top, DS.Spacing.lg)
                    }

                    if let loadError {
                        errorBanner(loadError)
                            .padding(.horizontal, DS.Spacing.xl)
                            .padding(.top, DS.Spacing.lg)
                    }

                    editorialSearchSection
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.lg)

                    Section(header: editorialStickySegments) {
                        editorialFeedSection
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
            applyPendingScopeIfPossible()
            await loadData()
            applyPendingReportFocusIfPossible()
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
                    title: primaryLine.map { "Ligne \($0) — \(incident.type ?? "Information STIB")" } ?? (incident.type ?? "Information STIB"),
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

        if !directItems.isEmpty {
            return directItems
        }

        guard let summary = currentSummary,
              (summary.sourceBreakdown?.official ?? 0) > 0 || (summary.sourceLabel?.lowercased() == "officiel")
        else {
            return []
        }

        let bullets = summary.bullets.isEmpty ? [summary.shortText] : summary.bullets
        return bullets.prefix(4).enumerated().map { index, bullet in
            EditorialFeedItem(
                id: "official-summary-\(index)",
                type: .official,
                title: summary.affectedLines.first.map { "Ligne \($0) — Information STIB" } ?? "Information STIB",
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
    }

    private var editorialHeader: some View {
        editorialMasthead
    }

    private var editorialMasthead: some View {
        let now = lastUpdatedAt ?? Date()
        let editionNum = Calendar.current.ordinality(of: .day, in: .year, for: now) ?? 1
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "fr_BE")
        dateFormatter.dateFormat = "EEEE d MMMM yyyy"
        let timeFormatter = DateFormatter()
        timeFormatter.locale = Locale(identifier: "fr_BE")
        timeFormatter.dateFormat = "HH:mm"

        return VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("N° \(String(format: "%03d", editionNum)) · ÉDITION CONTINUE")
                    .font(DS.Font.monoSmall.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                HStack(spacing: 6) {
                    Image(systemName: "bell.fill")
                        .font(.system(size: 9, weight: .bold))
                    Text("ALERTES")
                        .font(DS.Font.monoSmall.weight(.semibold))
                        .tracking(1.6)
                    Circle()
                        .fill(DS.Color.primary)
                        .frame(width: 5, height: 5)
                        .offset(x: -4, y: -6)
                }
                .foregroundStyle(DS.Color.ink)
            }

            Rectangle()
                .fill(DS.Color.ink)
                .frame(height: 3)
                .padding(.top, 6)

            HStack(alignment: .firstTextBaseline) {
                Text("Reports")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(timeFormatter.string(from: now))
                        .font(DS.Font.monoSmall.weight(.semibold))
                        .tracking(1.4)
                        .foregroundStyle(DS.Color.ink)
                    Text("Bruxelles · CET")
                        .font(DS.Font.monoSmall)
                        .tracking(1.4)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.top, 8)

            Text("\(dateFormatter.string(from: now).uppercased()) · STIB-MIVB · COMMUNAUTÉ · ÉVÉNEMENTS")
                .font(DS.Font.monoSmall)
                .tracking(1.5)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 4)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.15))
                .frame(height: 1)
                .padding(.top, 8)

            contentScopeSwitch
                .padding(.top, 12)
        }
    }

    private var statusHUD: some View {
        let perturbed = nowItems.count
        let total = max(60, perturbed + 50) // STIB ≈ 4 métros + ~20 trams + ~50 bus actifs
        let ok = max(0, total - perturbed)
        let severity: (label: String, color: Color) = {
            switch perturbed {
            case 0:    return ("NOMINAL", DS.Color.statusOK)
            case 1...2: return ("MINEUR", DS.Color.statusMinor)
            case 3...5: return ("MODÉRÉ", DS.Color.statusMajor)
            default:    return ("MAJEUR", DS.Color.statusCritical)
            }
        }()

        return VStack(spacing: 8) {
            HStack(spacing: 0) {
                StatusCell(
                    label: "État",
                    value: severity.label,
                    valueColor: severity.color,
                    pulse: true
                )
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.15))
                    .frame(width: 1)
                StatusCell(
                    label: "Lignes OK",
                    value: "\(ok)",
                    sublabel: "/ \(total)"
                )
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.15))
                    .frame(width: 1)
                StatusCell(
                    label: "Perturbées",
                    value: "\(perturbed)",
                    valueColor: perturbed > 0 ? DS.Color.statusMajor : DS.Color.ink
                )
            }
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

            GeometryReader { geo in
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(DS.Color.statusOK)
                        .frame(width: total > 0 ? CGFloat(ok) / CGFloat(total) * geo.size.width : 0)
                    Rectangle()
                        .fill(DS.Color.statusMajor)
                }
                .overlay(
                    Rectangle()
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
                )
            }
            .frame(height: 6)
        }
    }

    private var contentScopeSwitch: some View {
        HStack(spacing: 8) {
            ForEach(ContentScope.allCases) { scope in
                Button {
                    selectedScope = scope
                    selectedSegment = scope == .events ? .events : .all
                } label: {
                    Text(scope == .reports ? "Réseau & signalements" : "Événements")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(selectedScope == scope ? DS.Color.paper : DS.Color.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(selectedScope == scope ? DS.Color.ink : DS.Color.paper)
                        .overlay(
                            Capsule()
                                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
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

    private var editorialStickySegments: some View {
        ReportsFilterDock(
            showsReportFilters: selectedScope == .reports,
            selectedSegment: selectedSegment,
            selectedMode: selectedModeFilter,
            selectedLine: selectedLineFilter,
            selectedSort: selectedSortMode,
            lineFilters: visibleLineFilters,
            helperText: scopeHelperText,
            updatedText: lastUpdatedAt.map { "Mis à jour \(relativeTimeLabel(from: $0))" },
            onSelectSegment: { selectedSegment = $0 },
            onSelectMode: { selectedModeFilter = $0 },
            onSelectLine: { selectedLineFilter = $0 },
            onSelectSort: { selectedSortMode = $0 }
        )
    }

    private var scopeHelperText: String {
        switch selectedScope {
        case .reports:
            switch selectedSegment {
            case .all:
                return "Vue mixte des infos STIB officielles et des signalements de terrain."
            case .official:
                return "Informations publiées côté STIB ou confirmées par des sources officielles."
            case .community:
                return "Signalements partagés par les usagers sur le terrain."
            case .events:
                return "Événements bruxellois pouvant charger le réseau."
            }
        case .events:
            return "Événements et lieux qui peuvent augmenter l’affluence autour de certaines lignes."
        }
    }

    @ViewBuilder
    private var editorialFeedSection: some View {
        if isLoading && !hasLoaded {
            ProgressView()
                .tint(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 56)
        } else if feedItems.isEmpty {
            Text("Rien à signaler dans cette catégorie.")
                .font(DS.Font.body)
                .italic()
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 64)
        } else {
            LazyVStack(spacing: 10) {
                if shouldGroupFeedByLine {
                    ForEach(groupedFeedItems) { group in
                        EditorialLineGroupCard(
                            group: group,
                            isExpanded: expandedFeedLineIds.contains(group.id),
                            isFavoriteLine: favoriteLines.contains(group.line),
                            onToggle: {
                                withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                                    if expandedFeedLineIds.contains(group.id) {
                                        expandedFeedLineIds.remove(group.id)
                                    } else {
                                        expandedFeedLineIds.insert(group.id)
                                    }
                                }
                            },
                            nestedContent: {
                                VStack(spacing: 8) {
                                    ForEach(group.items) { item in
                                        feedCard(for: item)
                                    }
                                }
                            }
                        )
                    }
                } else {
                    ForEach(feedItems) { item in
                        feedCard(for: item)
                    }
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, 4)
        }
    }

    private func feedCard(for item: EditorialFeedItem) -> some View {
        EditorialFeedCard(
            item: item,
            isFavoriteLine: item.lines.contains(where: { favoriteLines.contains($0) }),
            isVoting: item.report.map { votingReportIds.contains($0.id) } ?? false,
            hasUpvoted: item.report.map { locallyUpvotedReportIds.contains($0.id) } ?? false,
            isNotificationLoading: item.lines.contains(where: { notificationLineInFlight.contains($0) }),
            isNotificationEnabled: item.lines.contains(where: { favoriteLines.contains($0) }),
            onUpvote: { report in
                Task { await upvoteReport(report) }
            },
            onNotifyLine: { line in
                Task { await enableLineNotifications(for: line) }
            }
        )
        .contentShape(Rectangle())
        .onTapGesture {
            if let report = item.report {
                selectedReport = report
            } else if let event = item.event {
                selectedEvent = event
            }
        }
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
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 14, weight: .heavy))
                Text("Signaler")
                    .font(DS.Font.bodyBold)
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

    @MainActor
    private func applyPendingScopeIfPossible() {
        guard let rawValue = nav.pendingReportsScopeRawValue else { return }
        if let scope = ContentScope(rawValue: rawValue) {
            selectedScope = scope
        }
        selectedSegment = rawValue == "events" ? .events : .all
        nav.pendingReportsScopeRawValue = nil
    }

    @MainActor
    private func loadData(force: Bool = false) async {
        await loadReports(force: force)
        await loadEvents(force: force)
        await loadSummary(force: force)
        lastUpdatedAt = Date()
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
            print("ReportsView load failed: \(error.localizedDescription)")
        }
    }

    @MainActor
    private func loadSummary(force: Bool = false) async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingSummary else { return }
        guard selectedScope == .reports else { return }
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
            print("ReportsView summary failed: \(error.localizedDescription)")
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
            print("ReportsView events failed: \(error.localizedDescription)")
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
        guard selectedModeFilter != .all else { return true }
        return lines.contains { transportMode(for: $0) == selectedModeFilter }
    }

    private func transportMode(for line: String) -> ReportTransportMode {
        let normalized = line.uppercased().trimmingCharacters(in: .whitespacesAndNewlines)
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

        return VStack(alignment: .leading, spacing: 12) {
            HStack {
                HStack(spacing: 6) {
                    PulsingDot(color: DS.Color.statusMajor)
                    Text("DOSSIER EN COURS")
                        .font(.system(size: 11, weight: .bold))
                        .tracking(1.8)
                        .foregroundStyle(DS.Color.ink)
                }

                Spacer()

                Text("\(items.count) ouvert\(items.count > 1 ? "s" : "")")
                    .font(DS.Font.monoSmall.weight(.semibold))
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
            }

            TabView(selection: $activeNetworkCarouselIndex) {
                ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                    Button {
                        isShowingSummary = true
                    } label: {
                        EditorialDossierCard(
                            item: item,
                            index: index + 1,
                            total: items.count
                        )
                    }
                    .buttonStyle(.plain)
                    .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .frame(height: 320)
            .onReceive(networkCarouselTimer) { _ in
                guard !reduceMotion, items.count > 1 else { return }
                withAnimation(.spring(response: 0.55, dampingFraction: 0.88)) {
                    activeNetworkCarouselIndex = (activeNetworkCarouselIndex + 1) % items.count
                }
            }
            .onChange(of: items.count) { _, count in
                if activeNetworkCarouselIndex >= count {
                    activeNetworkCarouselIndex = 0
                }
            }

            if items.count > 1 {
                HStack(spacing: 4) {
                    ForEach(items.indices, id: \.self) { index in
                        Button {
                            withAnimation(.spring(response: 0.42, dampingFraction: 0.9)) {
                                activeNetworkCarouselIndex = index
                            }
                        } label: {
                            Rectangle()
                                .fill(index == activeNetworkCarouselIndex ? DS.Color.ink : DS.Color.ink.opacity(0.25))
                                .frame(width: index == activeNetworkCarouselIndex ? 28 : 8, height: 3)
                                .animation(.easeInOut(duration: 0.2), value: activeNetworkCarouselIndex)
                        }
                        .buttonStyle(.plain)
                    }
                }
                .frame(maxWidth: .infinity)
            }
        }
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
                let line = incident.line?.trimmingCharacters(in: .whitespacesAndNewlines)
                let lines = line.map { [$0] } ?? Array(summary.affectedLines.prefix(4))
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

        return items
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

private struct ReportsFilterDock: View {
    let showsReportFilters: Bool
    let selectedSegment: ReportSegment
    let selectedMode: ReportTransportMode
    let selectedLine: String
    let selectedSort: ReportSortMode
    let lineFilters: [String]
    let helperText: String
    let updatedText: String?
    let onSelectSegment: (ReportSegment) -> Void
    let onSelectMode: (ReportTransportMode) -> Void
    let onSelectLine: (String) -> Void
    let onSelectSort: (ReportSortMode) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsReportFilters {
                HStack(spacing: 8) {
                    compactSegmentControl
                    Spacer(minLength: 8)
                    filterMenuButton(
                        icon: "arrow.up.arrow.down",
                        title: selectedSort.label
                    ) {
                        ForEach(ReportSortMode.allCases) { mode in
                            Button(mode.label) { onSelectSort(mode) }
                        }
                    }
                }

                HStack(spacing: 8) {
                    filterMenuButton(
                        icon: selectedMode.iconSystemName ?? "square.grid.2x2",
                        title: selectedMode.label
                    ) {
                        ForEach(ReportTransportMode.allCases) { mode in
                            Button(mode.label) { onSelectMode(mode) }
                        }
                    }

                    filterMenuButton(
                        icon: selectedLine == "Tout" ? "line.3.horizontal.decrease.circle" : "tram.fill",
                        title: selectedLine == "Tout" ? "Toutes lignes" : "Ligne \(selectedLine)"
                    ) {
                        ForEach(lineFilters, id: \.self) { line in
                            Button(line == "Tout" ? "Toutes lignes" : "Ligne \(line)") {
                                onSelectLine(line)
                            }
                        }
                    }

                    if selectedLine != "Tout" {
                        LineBadge(line: selectedLine, size: .sm)
                    }

                    Spacer(minLength: 0)
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 10) {
                Text(helperText)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)
                    .lineLimit(2)

                Spacer(minLength: 8)

                if let updatedText {
                    Text(updatedText)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
            }
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, 10)
        .padding(.bottom, 12)
        .background(
            DS.Color.paper.opacity(0.84)
                .background(.ultraThinMaterial)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.08))
                        .frame(height: 1)
                }
        )
    }

    private var compactSegmentControl: some View {
        HStack(spacing: 4) {
            ForEach([ReportSegment.all, .official, .community], id: \.self) { segment in
                Button {
                    onSelectSegment(segment)
                } label: {
                    HStack(spacing: 5) {
                        if let icon = segment.iconSystemName {
                            Image(systemName: icon)
                                .font(.system(size: 10, weight: .bold))
                        }
                        Text(segment.label)
                            .font(DS.Font.monoSmall.weight(.bold))
                            .tracking(0.8)
                    }
                    .foregroundStyle(selectedSegment == segment ? DS.Color.paper : DS.Color.ink)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(selectedSegment == segment ? DS.Color.ink : Color.clear)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(4)
        .background(DS.Color.paper.opacity(0.78))
        .overlay(
            Capsule()
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .clipShape(Capsule())
        .shadow(color: DS.Color.ink.opacity(0.06), radius: 14, x: 0, y: 8)
    }

    private func filterMenuButton<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: @escaping () -> Content
    ) -> some View {
        Menu(content: content) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .bold))
                Text(title)
                    .font(DS.Font.bodySmall.weight(.semibold))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(DS.Color.paper.opacity(0.86))
            .overlay(
                Capsule()
                    .stroke(DS.Color.ink.opacity(0.13), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}

private struct NetworkIssueCarouselCard: View {
    let item: NetworkIssueCarouselItem
    let itemCount: Int
    let activeIndex: Int

    private var severityLabel: String {
        let value = item.keyword.lowercased()
        switch value {
        case _ where value.contains("interrompu") || value.contains("accident"):
            return "Impact fort"
        case _ where value.contains("travaux") || value.contains("dévi"):
            return "À anticiper"
        default:
            return "À surveiller"
        }
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image("reports-metro-stib")
                .resizable()
                .scaledToFill()
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .clipped()

            LinearGradient(
                colors: [
                    .black.opacity(0.64),
                    .black.opacity(0.22),
                    .black.opacity(0.76)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            LinearGradient(
                colors: [
                    item.tint.opacity(0.58),
                    .black.opacity(0.22),
                    .clear
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .center, spacing: 9) {
                    Circle()
                        .fill(item.tint)
                        .frame(width: 10, height: 10)
                        .shadow(color: item.tint.opacity(0.7), radius: 9)

                    Text("AUTOUR DE TOI")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.88))

                    Spacer()

                    Text("STIB-MIVB")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2.0)
                        .foregroundStyle(.white.opacity(0.9))
                }

                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        ReportsGlassBadge(title: item.sourceLabel, icon: "checkmark.seal.fill")
                        ReportsGlassBadge(title: severityLabel, icon: "exclamationmark.triangle.fill")
                    }

                    HStack(alignment: .lastTextBaseline, spacing: 10) {
                        Text(item.keyword)
                            .font(DS.Font.displayH1)
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.72)

                        Text("\(activeIndex + 1)/\(max(itemCount, 1))")
                            .font(DS.Font.monoSmall.weight(.bold))
                            .foregroundStyle(.white.opacity(0.68))
                    }

                    Text(item.detail)
                        .font(DS.Font.bodySmall.weight(.semibold))
                        .foregroundStyle(.white.opacity(0.86))
                        .lineLimit(3)
                        .multilineTextAlignment(.leading)
                }

                Spacer(minLength: 0)

                HStack(alignment: .bottom, spacing: 8) {
                    if !item.lines.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(Array(item.lines.prefix(4)), id: \.self) { line in
                                LineBadge(line: line, size: .lg)
                            }
                            if item.lines.count > 4 {
                                Text("+\(item.lines.count - 4)")
                                    .font(DS.Font.monoSmall.weight(.bold))
                                    .foregroundStyle(.white.opacity(0.78))
                            }
                        }
                    }

                    if let location = item.location, !location.isEmpty {
                        HStack(spacing: 5) {
                            Image(systemName: "mappin.and.ellipse")
                                .font(.system(size: 10, weight: .bold))
                            Text(location)
                                .lineLimit(1)
                        }
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundStyle(.white.opacity(0.82))
                    }

                    Spacer(minLength: 8)

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 34, height: 34)
                        .background(.white.opacity(0.16))
                        .clipShape(Circle())
                }
            }
            .padding(18)
        }
        .frame(maxWidth: .infinity, minHeight: 212, maxHeight: 212)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(.white.opacity(0.46), lineWidth: 1)
                .padding(1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(color: item.tint.opacity(0.22), radius: 20, x: 0, y: 12)
        .accessibilityLabel("\(item.keyword). \(item.detail)")
    }
}

private struct ReportsGlassBadge: View {
    let title: String
    let icon: String

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .bold))
            Text(title)
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(0.9)
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 9)
        .frame(height: 26)
        .background(.white.opacity(0.16))
        .overlay(
            Capsule()
                .stroke(.white.opacity(0.22), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct EditorialLineGroupCard<NestedContent: View>: View {
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

private struct EditorialFeedCard: View {
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
                ProgressView()
                    .frame(maxWidth: .infinity)
                    .padding(16)
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
                    PulsingDot(color: valueColor, size: 4)
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

private struct PulsingDot: View {
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

private struct EditorialDossierCard: View {
    let item: NetworkIssueCarouselItem
    let index: Int
    let total: Int

    private var primaryLine: String { item.lines.first ?? "?" }

    private var lineKind: String {
        let trimmed = primaryLine.trimmingCharacters(in: .whitespacesAndNewlines).uppercased()
        let cleaned = trimmed.hasPrefix("T") || trimmed.hasPrefix("B")
            ? String(trimmed.dropFirst())
            : trimmed
        if let n = Int(cleaned) {
            if (1...6).contains(n) { return "Métro" }
            if (7...99).contains(n) { return "Tram" }
            return "Bus"
        }
        return "Ligne"
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

            VStack(alignment: .leading, spacing: 10) {
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
                .padding(.top, 28)

                HStack(alignment: .top, spacing: 10) {
                    Text(primaryLine)
                        .font(.system(size: 18, weight: .heavy, design: .monospaced))
                        .foregroundStyle(lineForeground)
                        .frame(width: 48, height: 48)
                        .background(lineColor)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .stroke(DS.Color.ink, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("⚠ PERTURBATION OFFICIELLE")
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

                EditorialLineVisualizer(line: primaryLine, color: lineColor)
                    .frame(height: 150)
            }
            .padding(.leading, 18)
            .padding(.trailing, 12)
            .padding(.bottom, 12)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .shadow(color: DS.Color.ink.opacity(0.18), radius: 12, x: 0, y: 8)
    }
}

// MARK: - Editorial line visualizer (stylized schematic)

private struct EditorialLineVisualizer: View {
    let line: String
    let color: Color

    var body: some View {
        GeometryReader { geo in
            let pts = computePath(in: geo.size)
            let disruptedIdx = max(1, pts.count / 2)
            ZStack {
                DS.Color.paper2.opacity(0.4)

                Path { p in
                    guard let first = pts.first else { return }
                    p.move(to: first)
                    for pt in pts.dropFirst() { p.addLine(to: pt) }
                }
                .stroke(color, style: StrokeStyle(lineWidth: 4, lineCap: .round, lineJoin: .round))
                .shadow(color: color.opacity(0.6), radius: 6)

                ForEach(Array(pts.enumerated()), id: \.offset) { i, pt in
                    let isDisrupted = i == disruptedIdx
                    let isTerminus = i == 0 || i == pts.count - 1
                    Rectangle()
                        .fill(isDisrupted ? DS.Color.statusMajor : (isTerminus ? DS.Color.ink : DS.Color.paper))
                        .frame(width: isTerminus ? 11 : 9, height: isTerminus ? 11 : 9)
                        .rotationEffect(.degrees(45))
                        .overlay(
                            Rectangle()
                                .stroke(DS.Color.ink, lineWidth: 1)
                                .rotationEffect(.degrees(45))
                                .frame(width: isTerminus ? 11 : 9, height: isTerminus ? 11 : 9)
                        )
                        .position(pt)
                }

                if disruptedIdx < pts.count {
                    EditorialPulsingHalo(color: DS.Color.statusMajor)
                        .position(pts[disruptedIdx])
                }

                VStack {
                    HStack {
                        Text("◤ LIVE")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(DS.Color.inkMute)
                        Spacer()
                        Text("L\(line) ◥")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(color)
                    }
                    Spacer()
                    HStack {
                        Text("◣ \(pts.count) JALONS")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(DS.Color.inkMute)
                        Spacer()
                        Text("ZONE PERTURBÉE ◢")
                            .font(.system(size: 8, weight: .semibold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }
                }
                .padding(6)
            }
        }
        .overlay(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.1), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }

    private func computePath(in size: CGSize) -> [CGPoint] {
        let n = 7
        var seed: UInt32 = 2166136261
        for c in line.unicodeScalars { seed ^= c.value; seed = seed &* 16777619 }
        var rng = EditorialPRNG(seed: seed)

        let padX: CGFloat = 16, padTop: CGFloat = 22, padBot: CGFloat = 30
        let usableW = size.width - padX * 2
        let usableH = size.height - padTop - padBot
        var points: [CGPoint] = []
        for i in 0..<n {
            let t = CGFloat(i) / CGFloat(n - 1)
            let x = padX + t * usableW
            let y = padTop + usableH * 0.5 + (rng.next() - 0.5) * usableH * 0.6
            points.append(CGPoint(x: x, y: y))
        }
        return points
    }
}

private struct EditorialPulsingHalo: View {
    let color: Color
    @State private var animate = false

    var body: some View {
        ZStack {
            Circle()
                .stroke(color, lineWidth: 1.5)
                .frame(width: 24, height: 24)
                .scaleEffect(animate ? 2.4 : 0.5)
                .opacity(animate ? 0 : 1)
            Circle()
                .fill(color.opacity(0.4))
                .frame(width: 16, height: 16)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) {
                animate = true
            }
        }
    }
}

private struct EditorialPRNG {
    var state: UInt32
    init(seed: UInt32) { self.state = seed == 0 ? 1 : seed }
    mutating func next() -> CGFloat {
        state = state &+ 0x6D2B79F5
        var r = (state ^ (state >> 15)) &* (1 | state)
        r = (r &+ ((r ^ (r >> 7)) &* (61 | r))) ^ r
        return CGFloat((r ^ (r >> 14)) >> 0) / CGFloat(UInt32.max)
    }
}
