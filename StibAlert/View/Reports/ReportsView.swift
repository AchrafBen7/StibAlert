import SwiftUI
import UIKit

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

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    AppTheme.Palette.screen,
                    AppTheme.Palette.screenElevated,
                    AppTheme.Palette.screen
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.Palette.glowInfo.opacity(0.16))
                .frame(width: 240, height: 240)
                .blur(radius: 38)
                .offset(x: 140, y: -260)

            Circle()
                .fill(AppTheme.Palette.glowBrand.opacity(0.1))
                .frame(width: 220, height: 220)
                .blur(radius: 42)
                .offset(x: -120, y: -120)

            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 12)

                lineFilters
                    .padding(.top, 18)

                scopeSwitcher
                    .padding(.horizontal, 21)
                    .padding(.top, 14)

                if let summary = currentSummary {
                    summaryPreview(summary)
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                }

                if let loadError {
                    errorBanner(loadError)
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                }

                if isLoading && !hasLoaded {
                    Spacer()
                    ProgressView()
                        .tint(.white.opacity(0.7))
                        .frame(maxWidth: .infinity)
                    Spacer()
                } else if selectedScope == .reports && hasLoaded && reports.isEmpty {
                    emptyState(
                        icon: "tray.fill",
                        title: "Aucun signalement récent",
                        message: "Les derniers reports STIB apparaîtront ici dès qu'ils sont publiés."
                    )
                } else if selectedScope == .events && hasLoaded && events.isEmpty {
                    emptyState(
                        icon: "calendar",
                        title: "Aucun événement exploitable",
                        message: "Les événements suivis à Bruxelles apparaîtront ici dès qu'ils sont chargés."
                    )
                } else if hasLoaded && selectedScope == .reports && filteredReports.isEmpty {
                    emptyState(
                        icon: "magnifyingglass",
                        title: "Aucun résultat",
                        message: "Essaie une autre ligne ou recherche un autre arrêt."
                    )
                } else if hasLoaded && selectedScope == .events && filteredEvents.isEmpty {
                    emptyState(
                        icon: "calendar.badge.exclamationmark",
                        title: "Aucun événement pour ce filtre",
                        message: "Essaie une autre ligne, un autre arrêt ou une autre recherche."
                    )
                } else {
                    HStack {
                        Text(resultCountLabel)
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textSecondary)

                        Spacer()

                        Text(scopeMetaLabel)
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.textMuted)
                    }
                    .padding(.horizontal, 21)
                    .padding(.top, 18)

                    ScrollView(showsIndicators: false) {
                        LazyVStack(spacing: 12) {
                            if selectedScope == .reports {
                                ForEach(filteredReports) { report in
                                    Button {
                                        withAnimation(AppMotion.spring(reduceMotion: reduceMotion, response: 0.32, dampingFraction: 0.86)) {
                                            selectedReport = report
                                        }
                                    } label: {
                                        ReportFeedCard(
                                            report: report,
                                            stopName: arretName(for: report)
                                        )
                                    }
                                    .buttonStyle(.plain)
                                }
                            } else {
                                ForEach(filteredEvents) { event in
                                    Button {
                                        selectedEvent = event
                                    } label: {
                                        EventImpactCard(event: event)
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 14)
                        .padding(.bottom, 120)
                    }
                }
            }
        }
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
            EventImpactDetailSheet(event: event)
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

    private var currentSummary: TransportPerturbationSummaryDTO? {
        if selectedLineFilter == "Tout" {
            return transportOverview?.perturbationSummary
        }
        return selectedLineSummary
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 19) {
                Button {
                    withAnimation(AppMotion.spring(reduceMotion: reduceMotion)) {
                        nav.showSideMenu = true
                    }
                } label: {
                    Circle()
                        .fill(AppTheme.Palette.surfaceElevated)
                        .frame(width: 42, height: 40)
                        .overlay(
                            Image(systemName: "line.3.horizontal")
                                .font(.system(size: 20, weight: .regular))
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                        )
                }
                .buttonStyle(.plain)

                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(AppTheme.Palette.textPrimary)

                    TextField(
                        "",
                        text: $query,
                        prompt: Text("Rechercher une ligne, un arrêt ou un problème")
                            .foregroundStyle(AppTheme.Palette.textMuted)
                    )
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
                }
                .padding(.horizontal, 14)
                .frame(height: 40)
                .background(AppTheme.Palette.surfaceElevated)
                .clipShape(Capsule())
                .overlay(
                    Capsule()
                        .stroke(AppTheme.Palette.borderStrong, lineWidth: 1)
                )
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("Desk communautaire")
                    .font(AppTheme.Fonts.captionStrong)
                    .textCase(.uppercase)
                    .tracking(0.9)
                    .foregroundStyle(AppTheme.Palette.brand.opacity(0.9))

                HStack(alignment: .center) {
                Text(selectedScope == .events ? "Événements réseau" : "Signalements")
                    .font(AppTheme.Fonts.clash(28))
                    .foregroundStyle(AppTheme.Palette.textPrimary)

                    Spacer()

                    Button {
                        guard currentSummary != nil else { return }
                        isShowingSummary = true
                    } label: {
                        HStack(spacing: 8) {
                            if isLoadingSummary {
                                ProgressView()
                                    .tint(.black.opacity(0.78))
                                    .scaleEffect(0.8)
                            } else {
                                Image(systemName: "text.alignleft")
                                    .font(.system(size: 12, weight: .semibold))
                            }

                            Text("Résumé")
                                .font(AppTheme.Fonts.captionStrong)
                        }
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(AppTheme.Palette.brand)
                        .clipShape(Capsule())
                        .opacity(currentSummary == nil && !isLoadingSummary ? 0.55 : 1)
                    }
                    .buttonStyle(.plain)
                    .disabled(currentSummary == nil && !isLoadingSummary)
                }

                Text(selectedScope == .events
                     ? "Les événements suivis à Bruxelles, avec lignes et arrêts potentiellement affectés."
                     : "Les derniers reports communautaires, filtrables par ligne et recherchables par arrêt.")
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textSecondary)

                Text(selectedScope == .events
                     ? "Affluence probable, zones sensibles et accès direct vers les lignes ou arrêts touchés."
                     : "Lecture réseau, signaux terrain, événements et synthèse rapide dans une seule vue.")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textMuted)
            }
        }
    }

    private var scopeSwitcher: some View {
        HStack(spacing: 10) {
            ForEach(ContentScope.allCases) { scope in
                Button {
                    withAnimation(AppMotion.quick(reduceMotion: reduceMotion)) {
                        selectedScope = scope
                    }
                } label: {
                    Text(scope.title)
                        .font(AppTheme.Fonts.bodyStrong)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .padding(.horizontal, 14)
                        .frame(height: 36)
                        .background(selectedScope == scope ? AppTheme.Palette.surfaceElevated : Color.clear)
                        .clipShape(Capsule())
                        .overlay(
                            Capsule()
                                .stroke(selectedScope == scope ? AppTheme.Palette.borderStrong : AppTheme.Palette.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Spacer()
        }
    }

    private var resultCountLabel: String {
        if selectedScope == .events {
            return "\(filteredEvents.count) événement\(filteredEvents.count == 1 ? "" : "s")"
        }
        return "\(filteredReports.count) signalement\(filteredReports.count == 1 ? "" : "s")"
    }

    private var scopeMetaLabel: String {
        let focus = selectedLineFilter == "Tout" ? "Vue réseau" : "Focus ligne \(selectedLineFilter)"
        return selectedScope == .events ? "\(focus) • affluence" : focus
    }

    private var lineFilters: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(availableLineFilters, id: \.self) { line in
                    Button {
                        withAnimation(AppMotion.quick(reduceMotion: reduceMotion)) {
                            selectedLineFilter = line
                        }
                    } label: {
                        Text(line == "Tout" ? "Tout" : "Ligne \(line)")
                            .font(AppTheme.Fonts.bodyStrong)
                            .foregroundStyle(selectedLineFilter == line ? AppTheme.Palette.textPrimary : AppTheme.Palette.textPrimary)
                            .padding(.horizontal, 14)
                            .frame(height: 36)
                            .background(selectedLineFilter == line ? AppTheme.Palette.surfaceElevated : Color.clear)
                            .clipShape(Capsule())
                            .overlay(
                                Capsule()
                                    .stroke(selectedLineFilter == line ? AppTheme.Palette.borderStrong : AppTheme.Palette.border, lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 21)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.exclamationmark")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(AppTheme.Palette.alert)
            Text(message)
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.Palette.textSecondary)
            Spacer()
            Button {
                Task { await loadReports(force: true) }
            } label: {
                Text("Réessayer")
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.info)
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [AppTheme.Palette.surfaceElevated.opacity(0.96), AppTheme.Palette.surface.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
    }

    @MainActor
    private func applyPendingScopeIfPossible() {
        guard let rawValue = nav.pendingReportsScopeRawValue else { return }
        if let scope = ContentScope(rawValue: rawValue) {
            selectedScope = scope
        }
        nav.pendingReportsScopeRawValue = nil
    }

    private func emptyState(icon: String, title: String, message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            Image(systemName: icon)
                .font(.system(size: 34, weight: .light))
                .foregroundStyle(AppTheme.Palette.textMuted)
            Text(title)
                .font(AppTheme.Fonts.clash(22))
                .foregroundStyle(AppTheme.Palette.textPrimary)
            Text(message)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 38)
            Spacer()
        }
        .frame(maxWidth: .infinity)
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
            let response = try await SignalementService.liste(page: 1, limit: 100)
            reports = response.signalements.sorted {
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
                selectedLineSummary = nil
            } else {
                let line = try await TransportService.line(id: selectedLineFilter)
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

    private func summaryPreview(_ summary: TransportPerturbationSummaryDTO) -> some View {
        Button {
            isShowingSummary = true
        } label: {
            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Lecture rapide")
                            .font(AppTheme.Fonts.captionStrong)
                            .textCase(.uppercase)
                            .foregroundStyle(AppTheme.Palette.textPrimary.opacity(0.56))

                        Text(summary.title)
                            .font(AppTheme.Fonts.clash(18))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                    }

                    Spacer()

                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textMuted)
                }

                Text(summary.shortText)
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textSecondary)
                    .lineLimit(3)

                HStack(spacing: 8) {
                    SummaryPreviewBadge(
                        text: sourcePreviewTitle(for: summary),
                        tint: sourcePreviewTint(for: summary)
                    )

                    if let line = summary.affectedLines.first {
                        SummaryPreviewBadge(
                            text: "Ligne \(line)",
                            tint: Color.black.opacity(0.08)
                        )
                    }

                    if let crowding = summary.crowdingRisk, crowding.level != "none" {
                        SummaryPreviewBadge(
                            text: crowdingBadgeTitle(for: crowding),
                            tint: crowdingBadgeTint(for: crowding)
                        )
                    }

                    Spacer()

                    Text("Ouvrir")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textMuted)
                }
            }
            .padding(18)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                LinearGradient(
                    colors: [AppTheme.Palette.brand, AppTheme.Palette.brand.opacity(0.9)],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )
            )
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.35), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.16), radius: 24, x: 0, y: 14)
        }
        .buttonStyle(.plain)
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
            return Color(hex: "#B5CFF8")
        case "communauté":
            return Color(hex: "#BFE7D0")
        default:
            return Color.white.opacity(0.72)
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
            return Color(hex: "#FFB3A6")
        case "moderate":
            return Color(hex: "#F4D6A0")
        default:
            return Color(hex: "#C8E3B0")
        }
    }
}

private struct EventImpactCard: View {
    let event: TransportEventImpactDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(event.title)
                        .font(AppTheme.Fonts.title3)
                        .foregroundStyle(AppTheme.Palette.textPrimary)
                        .multilineTextAlignment(.leading)

                    Text(event.venue ?? event.zoneLabel ?? "Bruxelles")
                        .font(AppTheme.Fonts.body)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                }

                Spacer()

                phaseBadge
            }

            if let notes = event.notesFr, !notes.isEmpty {
                Text(notes)
                    .font(AppTheme.Fonts.body)
                    .foregroundStyle(AppTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                if let impact = event.impactLevel {
                    miniBadge(text: impactLabel(impact), tint: impactTint(impact))
                }
                if let attendance = event.expectedAttendance {
                    miniBadge(text: "\(attendance.formatted()) pers.", tint: AppTheme.Palette.surfaceElevated)
                }
                if event.soldOut == true {
                    miniBadge(text: "Complet", tint: Color(hex: "#FFB89A"))
                }
            }

            if !event.impactedLines.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Lignes potentiellement affectées")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textMuted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 88), spacing: 8)], spacing: 8) {
                        ForEach(event.impactedLines, id: \.self) { line in
                            Text("Ligne \(line)")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(height: 30)
                                .background(AppTheme.Palette.surfaceElevated)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            if !event.impactedStops.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Arrêts / zones à surveiller")
                        .font(AppTheme.Fonts.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textMuted)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 8)], spacing: 8) {
                        ForEach(Array(event.impactedStops.prefix(4)), id: \.self) { stop in
                            Text(stop)
                                .font(AppTheme.Fonts.captionStrong)
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                .padding(.horizontal, 10)
                                .frame(height: 28)
                                .background(AppTheme.Palette.surface)
                                .clipShape(Capsule())
                        }
                    }
                }
            }

            HStack {
                Spacer()
                Text("Voir le détail")
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textMuted)
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textMuted)
            }
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [AppTheme.Palette.surfaceElevated.opacity(0.96), AppTheme.Palette.surface.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
    }

    private var phaseBadge: some View {
        Text(event.phaseLabel ?? "À venir")
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(phaseTint)
            .clipShape(Capsule())
    }

    private var phaseTint: Color {
        switch event.phase {
        case "live":
            return Color(hex: "#FFB89A")
        case "upcoming":
            return Color(hex: "#F4D6A0")
        default:
            return AppTheme.Palette.surfaceElevated
        }
    }

    private func miniBadge(text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tint)
            .clipShape(Capsule())
    }

    private func impactLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "high":
            return "Affluence forte"
        case "moderate":
            return "Affluence probable"
        default:
            return "Affluence légère"
        }
    }

    private func impactTint(_ value: String) -> Color {
        switch value.lowercased() {
        case "high":
            return Color(hex: "#FF9A7A")
        case "moderate":
            return Color(hex: "#F1C46C")
        default:
            return Color(hex: "#B8E28A")
        }
    }
}

private struct EventImpactDetailSheet: View {
    let event: TransportEventImpactDTO

    @EnvironmentObject private var nav: AppNavigation
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [AppTheme.Palette.screen, AppTheme.Palette.screenElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(event.title)
                            .font(AppTheme.Fonts.clash(28))
                            .foregroundStyle(AppTheme.Palette.textPrimary)

                        Text(event.venue ?? event.zoneLabel ?? "Bruxelles")
                            .font(AppTheme.Fonts.body)
                            .foregroundStyle(AppTheme.Palette.textSecondary)

                        HStack(spacing: 8) {
                            detailBadge(event.phaseLabel ?? "À venir", tint: phaseTint)
                            if let impact = event.impactLevel {
                                detailBadge(impactLabel(impact), tint: impactTint(impact))
                            }
                            if event.soldOut == true {
                                detailBadge("Complet", tint: Color(hex: "#FFB89A"))
                            }
                        }
                    }

                    detailSection(title: "Résumé") {
                        VStack(alignment: .leading, spacing: 10) {
                            if let notes = event.notesFr, !notes.isEmpty {
                                Text(notes)
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(AppTheme.Palette.textSecondary)
                            }
                            if let startsAt = event.startsAt {
                                Text(scheduleLabel(from: startsAt, to: event.endsAt))
                                    .font(AppTheme.Fonts.captionStrong)
                                    .foregroundStyle(AppTheme.Palette.textMuted)
                            }
                            if let address = event.address, !address.isEmpty {
                                Text(address)
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(AppTheme.Palette.textSecondary)
                            }
                        }
                    }

                    if !event.impactedLines.isEmpty {
                        detailSection(title: "Lignes concernées") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 10)], spacing: 10) {
                                ForEach(event.impactedLines, id: \.self) { line in
                                    Button {
                                        nav.pendingLineFocus = line
                                        nav.currentPage = .signalements
                                        dismiss()
                                    } label: {
                                        HStack(spacing: 6) {
                                            Text("Ligne \(line)")
                                                .font(AppTheme.Fonts.captionStrong)
                                            Image(systemName: "arrow.right")
                                                .font(.system(size: 10, weight: .bold))
                                        }
                                        .foregroundStyle(AppTheme.Palette.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .frame(maxWidth: .infinity)
                                        .background(AppTheme.Palette.surfaceElevated)
                                        .clipShape(Capsule())
                                    }
                                    .buttonStyle(.plain)
                                }
                            }
                        }
                    }

                    if let impactedStops = event.impactedStopDetails, !impactedStops.isEmpty {
                        detailSection(title: "Arrêts / zones concernés") {
                            VStack(alignment: .leading, spacing: 10) {
                                ForEach(impactedStops) { stop in
                                    Button {
                                        openStop(stop)
                                    } label: {
                                        HStack(spacing: 10) {
                                            VStack(alignment: .leading, spacing: 4) {
                                                Text(stop.name)
                                                    .font(AppTheme.Fonts.bodyStrong)
                                                    .foregroundStyle(AppTheme.Palette.textPrimary)
                                                Text(stop.id == nil ? "Zone repérée, détail STIB indisponible" : "Ouvrir le détail arrêt")
                                                    .font(AppTheme.Fonts.caption)
                                                    .foregroundStyle(AppTheme.Palette.textMuted)
                                            }
                                            Spacer()
                                            if stop.id != nil {
                                                Image(systemName: "arrow.up.right")
                                                    .font(.system(size: 12, weight: .semibold))
                                                    .foregroundStyle(AppTheme.Palette.textMuted)
                                            }
                                        }
                                        .padding(14)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .background(AppTheme.Palette.surfaceElevated)
                                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                                    }
                                    .buttonStyle(.plain)
                                    .disabled(stop.id == nil)
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
    }

    private func openStop(_ stop: TransportEventImpactedStopDTO) {
        guard let stopId = stop.id else { return }
        nav.pendingMapStopFocusBackendId = stopId
        nav.currentPage = .home
        dismiss()
    }

    private func detailSection<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(AppTheme.Fonts.clash(16))
                .foregroundStyle(AppTheme.Palette.textPrimary)

            content()
        }
        .padding(18)
        .background(
            LinearGradient(
                colors: [AppTheme.Palette.surfaceElevated.opacity(0.96), AppTheme.Palette.surface.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
    }

    private func detailBadge(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 30)
            .background(tint)
            .clipShape(Capsule())
    }

    private var phaseTint: Color {
        switch event.phase {
        case "live":
            return Color(hex: "#FFB89A")
        case "upcoming":
            return Color(hex: "#F4D6A0")
        default:
            return AppTheme.Palette.surfaceElevated
        }
    }

    private func impactLabel(_ value: String) -> String {
        switch value.lowercased() {
        case "high":
            return "Affluence forte"
        case "moderate":
            return "Affluence probable"
        default:
            return "Affluence légère"
        }
    }

    private func impactTint(_ value: String) -> Color {
        switch value.lowercased() {
        case "high":
            return Color(hex: "#FF9A7A")
        case "moderate":
            return Color(hex: "#F1C46C")
        default:
            return Color(hex: "#B8E28A")
        }
    }

    private func scheduleLabel(from start: Date, to end: Date?) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_BE")
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        if let end {
            return "\(formatter.string(from: start)) → \(formatter.string(from: end))"
        }
        return formatter.string(from: start)
    }
}

private struct EventStopDetailOverlay: View {
    let stopDetail: TransportStopDTO
    let isLoading: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.55)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack {
                Spacer()

                VStack(alignment: .leading, spacing: 14) {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(stopDetail.stop.name)
                                .font(AppTheme.Fonts.clash(18))
                                .foregroundStyle(AppTheme.Palette.textPrimary)

                            Text(TransportViewAdapters.localizedSeverityLabel(severity: stopDetail.severity, fallback: stopDetail.label?.fr))
                                .font(AppTheme.Fonts.captionStrong)
                                .foregroundStyle(Color(hex: "#B5CFF8"))
                        }

                        Spacer()

                        Button(action: onDismiss) {
                            Image(systemName: "xmark")
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                .frame(width: 30, height: 30)
                                .background(AppTheme.Palette.surfaceElevated)
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }

                    if isLoading {
                        ProgressView()
                            .tint(AppTheme.Palette.textPrimary)
                    }

                    if !stopDetail.nextDepartures.isEmpty {
                        Text(stopDetail.nextDepartures.prefix(3).map { "\($0.line) \($0.minutes) min" }.joined(separator: " • "))
                            .font(AppTheme.Fonts.captionStrong)
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                    }

                    if !stopDetail.activeIncidents.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Confirmations terrain")
                                .font(AppTheme.Fonts.clash(15))
                                .foregroundStyle(AppTheme.Palette.textPrimary)

                            ForEach(stopDetail.activeIncidents.prefix(3)) { incident in
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(incident.type ?? "Signalement")
                                        .font(AppTheme.Fonts.bodyStrong)
                                        .foregroundStyle(AppTheme.Palette.textPrimary)
                                    if let description = incident.description, !description.isEmpty {
                                        Text(description)
                                            .font(AppTheme.Fonts.body)
                                            .foregroundStyle(AppTheme.Palette.textSecondary)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                }
                                .padding(12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(AppTheme.Palette.surfaceElevated)
                                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                            }
                        }
                    }
                }
                .padding(18)
                .background(AppTheme.Palette.screenElevated)
                .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 26, style: .continuous)
                        .stroke(AppTheme.Palette.border, lineWidth: 1)
                )
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 18)
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
            LinearGradient(
                colors: [AppTheme.Palette.screen, AppTheme.Palette.screenElevated],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            Circle()
                .fill(AppTheme.Palette.glowInfo.opacity(0.12))
                .frame(width: 230, height: 230)
                .blur(radius: 34)
                .offset(x: 120, y: -220)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(lineLabel.map { "Résumé ligne \($0)" } ?? "Résumé perturbations")
                            .font(AppTheme.Fonts.clash(28))
                            .foregroundStyle(AppTheme.Palette.textPrimary)

                        HStack(alignment: .center, spacing: 10) {
                            HStack(spacing: 8) {
                                SummaryBadge(
                                    title: sourceBadgeTitle,
                                    tint: sourceBadgeTint
                                )

                                if let source = summary.source, !source.isEmpty {
                                    SummaryBadge(
                                        title: source.uppercased(),
                                        tint: Color.white.opacity(0.22)
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
                                            .font(AppTheme.Fonts.captionStrong)
                                    }
                                    .foregroundStyle(AppTheme.Palette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(AppTheme.Palette.info)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)

                                Button {
                                    copySummary()
                                } label: {
                                    HStack(spacing: 6) {
                                        Image(systemName: didCopy ? "checkmark" : "doc.on.doc")
                                            .font(.system(size: 11, weight: .semibold))
                                        Text(didCopy ? "Copié" : "Copier")
                                            .font(AppTheme.Fonts.captionStrong)
                                    }
                                    .foregroundStyle(AppTheme.Palette.textPrimary)
                                    .padding(.horizontal, 10)
                                    .frame(height: 30)
                                    .background(AppTheme.Palette.surfaceElevated)
                                    .clipShape(Capsule())
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 12) {
                        Text(summary.title)
                            .font(AppTheme.Fonts.title2)
                            .foregroundStyle(AppTheme.Palette.brand)

                        Text(summary.longText)
                            .font(AppTheme.Fonts.body)
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(20)
                    .background(
                        LinearGradient(
                            colors: [AppTheme.Palette.surfaceElevated.opacity(0.96), AppTheme.Palette.surface.opacity(0.98)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(AppTheme.Palette.border, lineWidth: 1)
                    )

                    if !summary.affectedLines.isEmpty {
                        summarySection(title: "Lignes les plus touchées") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                                ForEach(summary.affectedLines, id: \.self) { line in
                                    Text("Ligne \(line)")
                                        .font(.custom("Montserrat-SemiBold", size: 12))
                                        .foregroundStyle(AppTheme.Palette.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 32)
                                        .background(AppTheme.Palette.surfaceElevated)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if !summary.affectedStops.isEmpty {
                        summarySection(title: "Zones / arrêts clés") {
                            VStack(alignment: .leading, spacing: 8) {
                                ForEach(summary.affectedStops, id: \.self) { stop in
                                    Text(stop)
                                        .font(AppTheme.Fonts.body)
                                        .foregroundStyle(AppTheme.Palette.textSecondary)
                                }
                            }
                        }
                    }

                    if let incidentTypes = summary.incidentTypes, !incidentTypes.isEmpty {
                        summarySection(title: "Types dominants") {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 10)], spacing: 10) {
                                ForEach(incidentTypes, id: \.self) { type in
                                    Text(type)
                                        .font(AppTheme.Fonts.captionStrong)
                                        .foregroundStyle(AppTheme.Palette.textPrimary)
                                        .padding(.horizontal, 12)
                                        .frame(height: 34)
                                        .frame(maxWidth: .infinity)
                                        .background(AppTheme.Palette.surface)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }

                    if let sourceBreakdown = summary.sourceBreakdown {
                        summarySection(title: "Origine des signaux") {
                            VStack(alignment: .leading, spacing: 10) {
                                SourceBreakdownRow(label: "Officiel STIB", value: sourceBreakdown.official ?? 0, tint: Color(hex: "#89B7FF"))
                                SourceBreakdownRow(label: "Communauté", value: sourceBreakdown.community ?? 0, tint: Color(hex: "#57E3B6"))
                                if (sourceBreakdown.mixed ?? 0) > 0 {
                                    SourceBreakdownRow(label: "Sources mixtes", value: sourceBreakdown.mixed ?? 0, tint: Color(hex: "#F2E6C9"))
                                }
                            }
                        }
                    }

                    if let crowdingRisk = summary.crowdingRisk, crowdingRisk.level != "none" {
                        summarySection(title: "Affluence probable") {
                            VStack(alignment: .leading, spacing: 12) {
                                HStack(spacing: 8) {
                                    SummaryBadge(
                                        title: crowdingRiskBadgeTitle(crowdingRisk),
                                        tint: crowdingRiskBadgeTint(crowdingRisk)
                                    )

                                    if let zoneLabel = crowdingRisk.zoneLabel, !zoneLabel.isEmpty {
                                        SummaryBadge(
                                            title: zoneLabel,
                                            tint: AppTheme.Palette.surfaceElevated
                                        )
                                    }
                                }

                                Text(crowdingRisk.longText)
                                    .font(AppTheme.Fonts.body)
                                    .foregroundStyle(AppTheme.Palette.textSecondary)
                                    .fixedSize(horizontal: false, vertical: true)

                                if !crowdingRisk.eventNames.isEmpty {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text("Événements suivis")
                                            .font(AppTheme.Fonts.captionStrong)
                                            .foregroundStyle(AppTheme.Palette.textMuted)
                                        ForEach(crowdingRisk.eventNames, id: \.self) { event in
                                            Text(event)
                                                .font(AppTheme.Fonts.body)
                                                .foregroundStyle(AppTheme.Palette.textSecondary)
                                        }
                                    }
                                }

                                if !crowdingRisk.impactedLines.isEmpty {
                                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                                        ForEach(crowdingRisk.impactedLines.prefix(6), id: \.self) { line in
                                            Text("Ligne \(line)")
                                                .font(.custom("Montserrat-SemiBold", size: 12))
                                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                                .padding(.horizontal, 12)
                                                .frame(height: 32)
                                                .background(AppTheme.Palette.surfaceElevated)
                                                .clipShape(Capsule())
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
                                            .fill(AppTheme.Palette.info)
                                            .frame(width: 7, height: 7)
                                            .padding(.top, 6)
                                        Text(bullet)
                                            .font(AppTheme.Fonts.body)
                                            .foregroundStyle(AppTheme.Palette.textSecondary)
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
            return Color(hex: "#89B7FF")
        case "communauté":
            return Color(hex: "#57E3B6")
        default:
            return Color(hex: "#F2E6C9")
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
            return Color(hex: "#FF9A7A")
        case "moderate":
            return Color(hex: "#F1C46C")
        default:
            return Color(hex: "#B8E28A")
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
                .font(AppTheme.Fonts.captionStrong)
                .textCase(.uppercase)
                .foregroundStyle(AppTheme.Palette.textMuted)

            content()
        }
    }
}

private struct SummaryBadge: View {
    let title: String
    let tint: Color

    var body: some View {
        Text(title)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tint)
            .clipShape(Capsule())
    }
}

private struct SummaryPreviewBadge: View {
    let text: String
    let tint: Color

    var body: some View {
        Text(text)
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textPrimary)
            .padding(.horizontal, 10)
            .frame(height: 28)
            .background(tint)
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
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textSecondary)

            Spacer()

            Text("\(value)")
                .font(AppTheme.Fonts.bodyStrong)
                .foregroundStyle(AppTheme.Palette.textPrimary)
        }
    }
}

private struct ReportFeedCard: View {
    let report: SignalementDTO
    let stopName: String?

    private var lineColor: Color {
        switch report.typeProbleme.lowercased() {
        case "accident":
            return Color(hex: "#EF4444")
        case "panne":
            return Color(hex: "#F97316")
        case "retard":
            return Color(hex: "#3B82F6")
        default:
            return Color(hex: "#8B5CF6")
        }
    }

    private var statusText: String {
        if report.status == "resolved" {
            return "Résolu"
        }
        return report.typeProbleme
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(
                            LinearGradient(
                                colors: [lineColor, lineColor.opacity(0.8)],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )

                    Text(report.ligne)
                        .font(.custom("DelaGothicOne-Regular", size: 16))
                        .foregroundStyle(lineColor.isDark ? .white : .black)
                }
                .frame(width: 50, height: 52)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .center, spacing: 8) {
                        Text(stopName ?? "Arrêt STIB")
                            .font(AppTheme.Fonts.bodyStrong)
                            .foregroundStyle(AppTheme.Palette.textPrimary)

                        Text(statusText)
                            .font(AppTheme.Fonts.captionStrong)
                            .foregroundStyle(lineColor)
                            .padding(.horizontal, 8)
                            .frame(height: 22)
                            .background(lineColor.opacity(0.14))
                            .clipShape(Capsule())
                    }

                    Text(report.description)
                        .font(AppTheme.Fonts.body)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                        .lineLimit(3)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textMuted)
            }

            HStack(spacing: 10) {
                Label(report.freshnessLabel, systemImage: "clock")
                    .labelStyle(.titleAndIcon)

                if let confidence = report.confirmationsSummaryLabel {
                    Label(confidence, systemImage: "checkmark.seal")
                        .labelStyle(.titleAndIcon)
                }
            }
            .font(AppTheme.Fonts.captionStrong)
            .foregroundStyle(AppTheme.Palette.textMuted)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [AppTheme.Palette.surfaceElevated.opacity(0.96), AppTheme.Palette.surface.opacity(0.98)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(AppTheme.Palette.border, lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.14), radius: 20, x: 0, y: 10)
    }
}
