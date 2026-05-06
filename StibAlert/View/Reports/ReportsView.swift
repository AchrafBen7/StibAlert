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

private struct EditorialNowItem: Identifiable {
    let id: String
    let line: String
    let reason: String
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
    @EnvironmentObject private var stibi: StibiCenter
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var selectedScope: ContentScope = .reports
    @State private var selectedSegment: ReportSegment = .all
    @State private var reports: [SignalementDTO] = []
    @State private var events: [TransportEventImpactDTO] = []
    @State private var isLoading = false
    @State private var hasLoaded = false
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

    private var availableLineFilters: [String] {
        let reportLines = reports.map(\.ligne)
        let eventLines = events.flatMap(\.impactedLines)
        let lines = Set(reportLines + eventLines).sorted {
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

        let officialTransportItems = officialTransportFeedItems

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
            .sorted { lhs, rhs in
                switch (lhs.event?.startsAt, rhs.event?.startsAt, lhs.report?.dateSignalement, rhs.report?.dateSignalement) {
                case let (l?, r?, _, _):
                    return l > r
                case let (_, _, l?, r?):
                    return l > r
                default:
                    return lhs.title < rhs.title
                }
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

    var body: some View {
        ZStack {
            DS.Color.paper
                .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                LazyVStack(alignment: .leading, spacing: 0, pinnedViews: [.sectionHeaders]) {
                    editorialHeader
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.md)

                    if let summary = currentSummary {
                        summaryPreview(summary)
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
            stibi.setCurrentScreen("reports")
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
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    PageHeader(
                        title: "Reports",
                        eyebrow: "Bruxelles · temps réel",
                        large: true
                    )
                    Text("Perturbations, signalements et événements, en direct.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkSoft)
                }

                Spacer()
            }

            contentScopeSwitch
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
        VStack(alignment: .leading, spacing: 0) {
            if selectedScope == .reports {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 6) {
                        ForEach([ReportSegment.all, .official, .community], id: \.self) { segment in
                            Chip(
                                label: segment.label,
                                active: selectedSegment == segment,
                                icon: {
                                    if let name = segment.iconSystemName {
                                        Image(systemName: name)
                                    }
                                }
                            ) {
                                selectedSegment = segment
                            }
                        }
                    }
                    .padding(.horizontal, DS.Spacing.xl)
                }
                .padding(.top, DS.Spacing.md)
                .padding(.bottom, 6)
            }

            Text(scopeHelperText)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkSoft)
                .padding(.horizontal, DS.Spacing.xl)
                .padding(.bottom, DS.Spacing.sm)
        }
        .background(DS.Color.paper)
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
                ForEach(feedItems) { item in
                    Button {
                        if let report = item.report {
                            selectedReport = report
                        } else if let event = item.event {
                            selectedEvent = event
                        }
                    } label: {
                        EditorialFeedCard(item: item)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, DS.Spacing.xl)
            .padding(.top, 4)
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

    private func summaryPreview(_ summary: TransportPerturbationSummaryDTO) -> some View {
        Button {
            isShowingSummary = true
        } label: {
            HStack(alignment: .top, spacing: 12) {
                EditorialPingDot(color: summaryDotColor(for: summary))

                VStack(alignment: .leading, spacing: 4) {
                    Text(summary.title)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)

                    Text(summary.shortText)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkSoft)
                        .lineLimit(2)

                    HStack(spacing: 6) {
                        ReportsMetaBadge(
                            title: sourcePreviewTitle(for: summary),
                            tint: sourcePreviewTint(for: summary)
                        )

                        if let line = summary.affectedLines.first {
                            ReportsMetaBadge(
                                title: "Ligne \(line)",
                                tint: DS.Color.secondary.opacity(0.18)
                            )
                        }
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .shadow(DS.Shadow.raised)
        }
        .buttonStyle(.plain)
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

private struct EditorialFeedCard: View {
    let item: EditorialFeedItem

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
                if let up = item.upvotes {
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

    @StateObject private var speech = StibiSpeechSynthesizer()
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
                                    toggleSpeech()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: speech.isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                                            .font(.system(size: 12, weight: .semibold))
                                        Text(speech.isSpeaking ? "Stop" : "Lire")
                                            .font(DS.Font.monoSmall.weight(.bold))
                                    }
                                    .foregroundStyle(DS.Color.ink)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(DS.Color.secondary)
                                    .clipShape(Capsule())
                                    .overlay(Capsule().stroke(DS.Color.border, lineWidth: 1))
                                }
                                .buttonStyle(.plain)

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
        .onDisappear {
            speech.stop()
        }
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

    private func toggleSpeech() {
        if speech.isSpeaking {
            speech.stop()
            return
        }
        speech.speak(spokenSummary)
    }

    private func copySummary() {
        UIPasteboard.general.string = copyableSummary
        didCopy = true

        DispatchQueue.main.asyncAfter(deadline: .now() + 1.6) {
            didCopy = false
        }
    }

    private var spokenSummary: String {
        var parts: [String] = []
        parts.append(lineLabel.map { "Résumé de la ligne \($0)." } ?? "Résumé des perturbations.")
        parts.append(summary.longText)

        if !summary.bullets.isEmpty {
            parts.append(summary.bullets.joined(separator: " "))
        }

        return parts.joined(separator: " ")
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
