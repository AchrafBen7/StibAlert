import SwiftUI

/// Full detail page for an SNCB gare — the train-side equivalent of
/// `LigneDetailPage`. Two primary tabs:
///   • Horaires    — the complete theoretical timetable (grouped by hour, with
///                   a Semaine / Samedi / Dimanche selector), from the bundled
///                   static GTFS dataset (zero Mobility API calls).
///   • Infos trafic — gare-scoped community signalements + (soon) official SNCB
///                   perturbations, with the same En cours / Officiel /
///                   TwartX sub-tabs as the STIB line page.
///
/// Opened on the schedule tab from Horaires, and on the traffic tab from the
/// Infos trafic gare drill-down. Works both as a NavigationStack push and a
/// fullScreenCover (it draws its own back button + hides the nav bar).
struct GareDetailPage: View {
    enum DetailTab: Hashable { case schedule, traffic }
    enum TrafficSubtab: Hashable { case live, official, social }

    let station: SNCBStation
    var onReport: (SNCBStation) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    @State private var selectedTab: DetailTab
    @State private var selectedTrafficSubtab: TrafficSubtab = .live
    @State private var selectedDay: SNCBDayType = .weekday
    @State private var schedule: SNCBSchedule?
    @State private var isLoadingSchedule = true
    @State private var signalements: [SignalementDTO] = []
    @State private var isLoadingReports = true
    @State private var isRefreshing = false
    @State private var didInitDay = false
    @State private var selectedDeparture: SNCBDeparture?
    @StateObject private var favorites = SNCBDepartureFavorites()
    @Namespace private var tabUnderlineNamespace

    init(station: SNCBStation, initialTab: DetailTab = .schedule, onReport: @escaping (SNCBStation) -> Void = { _ in }) {
        self.station = station
        self.onReport = onReport
        _selectedTab = State(initialValue: initialTab)
    }

    var body: some View {
        ZStack(alignment: .top) {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                    content
                        .padding(.horizontal, DS.Spacing.xl)
                        .padding(.top, DS.Spacing.lg)
                        .padding(.bottom, 120)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollBounceBehavior(.basedOnSize, axes: .vertical)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
        .modifier(PaperGrainBackground())
        .preferredColorScheme(.light)
        .toolbar(.hidden, for: .navigationBar)
        .task { await load() }
        .sheet(item: $selectedDeparture) { dep in
            SncbDepartureSheet(
                stationName: station.displayName,
                stationId: station.id,
                day: selectedDay,
                departure: dep,
                favorites: favorites
            )
        }
    }

    // MARK: - Header

    private var header: some View {
        HStack {
            Button(action: { dismiss() }) {
                HStack(spacing: DS.Spacing.sm) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 16, weight: .semibold))
                    Text("Retour")
                        .font(DS.Font.bodyBold)
                }
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, DS.Spacing.lg)
                .frame(height: 40)
                .background(DS.Color.paper)
                .overlay(Capsule().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1))
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)

            Spacer()

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                Task { await refresh() }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .background(DS.Color.paper)
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1))
                    .clipShape(Circle())
                    .rotationEffect(.degrees(isRefreshing ? 360 : 0))
                    .animation(isRefreshing ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: isRefreshing)
            }
            .buttonStyle(.plain)
            .disabled(isRefreshing)
            .accessibilityLabel("Rafraîchir")
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.md)
    }

    // MARK: - Content

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            identifierBlock
            primaryTabSwitcher

            switch selectedTab {
            case .schedule: scheduleTabContent
            case .traffic:  trafficTabContent
            }
        }
    }

    private var identifierBlock: some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            Image("operator-sncb")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 38, height: 38)
                .frame(width: 54, height: 54)
                .background(DS.Color.paper2.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).stroke(DS.Color.ink.opacity(0.10), lineWidth: 1))

            VStack(alignment: .leading, spacing: 4) {
                Text(station.displayProvince.uppercased() + " · GARE SNCB")
                    .font(DS.Font.eyebrow)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Text(station.displayName)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    // MARK: - Primary tabs

    private var primaryTabSwitcher: some View {
        HStack(spacing: 0) {
            primaryTabLabel(.schedule, label: "Horaires")
            primaryTabLabel(.traffic, label: "Infos trafic", showsStatusIcon: true)
        }
        .frame(height: 44)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.ink.opacity(0.10)).frame(height: 1)
        }
    }

    private func primaryTabLabel(_ tab: DetailTab, label: String, showsStatusIcon: Bool = false) -> some View {
        let isSelected = selectedTab == tab
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) { selectedTab = tab }
        } label: {
            HStack(spacing: 6) {
                Text(label)
                    .font(.system(size: 16, weight: isSelected ? .bold : .medium))
                if showsStatusIcon {
                    Image(systemName: hasActiveTrafficIssue ? "exclamationmark.triangle.fill" : "checkmark.seal.fill")
                        .font(.system(size: 12, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(hasActiveTrafficIssue ? DS.Color.statusMajor : DS.Color.statusOK))
                }
            }
            .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.inkMute)
            .frame(maxWidth: .infinity)
            .frame(height: 44)
            .overlay(alignment: .bottom) {
                if isSelected {
                    Rectangle()
                        .fill(DS.Color.ink)
                        .frame(height: 2)
                        .matchedGeometryEffect(id: "gareTabUnderline", in: tabUnderlineNamespace)
                }
            }
        }
        .buttonStyle(.plain)
    }

    // MARK: - Schedule tab

    @ViewBuilder
    private var scheduleTabContent: some View {
        daySelector

        if isLoadingSchedule {
            ProgressView()
                .tint(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 48)
        } else if visibleList.isEmpty {
            emptyStateCard(
                icon: "calendar.badge.exclamationmark",
                title: isViewingToday ? "Plus de départ aujourd'hui" : "Aucun départ ce jour",
                detail: isViewingToday
                    ? "Il n'y a plus de train au départ de cette gare aujourd'hui. Choisissez un autre jour ci-dessus."
                    : "Pas de train au départ de cette gare pour \(selectedDay.label.lowercased())."
            )
        } else {
            if !favoriteDepartures.isEmpty {
                favoritesSection
            }
            timetable
            Text("Horaires théoriques · temps réel bientôt")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private var favoritesSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "star.fill")
                    .font(.system(size: 11, weight: .black))
                    .foregroundStyle(DS.Color.primary)
                Text("MES DÉPARTS")
                    .font(DS.Font.eyebrow)
                    .tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
            }
            VStack(spacing: 0) {
                ForEach(favoriteDepartures) { scheduleRow($0) }
            }
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    private var daySelector: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                ForEach(SNCBDayType.allCases) { day in
                    dayChip(day)
                }
            }
            .padding(4)
            .background(DS.Color.paper2.opacity(0.55))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            Text(isViewingToday ? "Aujourd’hui · \(visibleList.count) prochains départs" : "\(visibleList.count) départs")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
        }
    }

    private func dayChip(_ day: SNCBDayType) -> some View {
        let isSelected = selectedDay == day
        let isToday = schedule?.todayType == day
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) { selectedDay = day }
        } label: {
            HStack(spacing: 5) {
                if isToday {
                    Circle()
                        .fill(isSelected ? DS.Color.paper : DS.Color.statusOK)
                        .frame(width: 6, height: 6)
                }
                Text(day.label)
                    .font(DS.Font.bodyBold)
            }
            .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 36)
            .background(isSelected ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.ink.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private var timetable: some View {
        LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
            ForEach(hourGroups, id: \.hour) { group in
                Section {
                    ForEach(Array(group.items.enumerated()), id: \.offset) { _, dep in
                        scheduleRow(dep)
                    }
                } header: {
                    hourHeader(group.hour)
                }
            }
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func hourHeader(_ hour: Int) -> some View {
        HStack {
            Text(String(format: "%02dh", hour % 24))
                .font(.system(size: 12, weight: .black, design: .monospaced))
                .tracking(1)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(DS.Color.paper2)
    }

    private func scheduleRow(_ dep: SNCBDeparture) -> some View {
        let isNext = nextKey == key(for: dep)
        let isFav = favorites.contains(SNCBDepartureFavorites.key(stationId: station.id, day: selectedDay, departure: dep))
        return Button { selectedDeparture = dep } label: {
            HStack(spacing: 12) {
                Text(dep.time)
                    .font(DS.Font.monoLarge)
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 52, alignment: .leading)

                if !dep.line.isEmpty {
                    Text(dep.line)
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 6)
                        .frame(height: 20)
                        .background(Color(hex: "#0055A4"))
                        .clipShape(Capsule())
                }

                Text(dep.destination)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if isFav {
                    Image(systemName: "star.fill")
                        .font(.system(size: 11, weight: .black))
                        .foregroundStyle(DS.Color.primary)
                }
                if isNext {
                    Text("PROCHAIN")
                        .font(.system(size: 9, weight: .black, design: .monospaced))
                        .tracking(0.8)
                        .foregroundStyle(DS.Color.statusOK)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(isNext ? DS.Color.statusOK.opacity(0.08) : DS.Color.paper)
            .overlay(alignment: .bottom) {
                Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    // MARK: - Infos trafic tab

    @ViewBuilder
    private var trafficTabContent: some View {
        trafficStatusBanner
        trafficSubtabSwitcher

        switch selectedTrafficSubtab {
        case .live:     communityList
        case .official: officialPlaceholder
        case .social:   socialPlaceholder
        }

        reportButton
    }

    private var trafficStatusBanner: some View {
        let isOK = !hasActiveTrafficIssue
        return HStack(spacing: 14) {
            Image(systemName: isOK ? "checkmark.seal.fill" : "exclamationmark.triangle.fill")
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(.white)
                .frame(width: 52, height: 52)
                .background(Circle().fill(isOK ? DS.Color.statusOK : DS.Color.statusMajor))
                .shadow(color: (isOK ? DS.Color.statusOK : DS.Color.statusMajor).opacity(0.35), radius: 8, y: 3)
            VStack(alignment: .leading, spacing: 2) {
                Text(isOK ? "Trafic normal" : "Perturbations en cours")
                    .font(.system(size: 17, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(isOK
                     ? "Aucun signalement actif sur cette gare."
                     : "\(signalements.count) info\(signalements.count > 1 ? "s" : "") · communauté")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private var trafficSubtabSwitcher: some View {
        HStack(spacing: 4) {
            subtabChip(.live, label: "En cours", count: signalements.count)
            subtabChip(.official, label: "Officiel", count: 0)
            subtabChip(.social, label: "Twitter / X", count: 0)
        }
        .padding(4)
        .background(DS.Color.paper2.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    private func subtabChip(_ tab: TrafficSubtab, label: String, count: Int) -> some View {
        let isSelected = selectedTrafficSubtab == tab
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) { selectedTrafficSubtab = tab }
        } label: {
            HStack(spacing: 4) {
                Text(label).font(DS.Font.bodyBold)
                if count > 0 {
                    Text("\(count)")
                        .font(.system(size: 10, weight: .black, design: .rounded))
                        .padding(.horizontal, 5)
                        .frame(height: 16)
                        .background(Capsule().fill(isSelected ? DS.Color.paper.opacity(0.22) : DS.Color.statusMajor.opacity(0.18)))
                        .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.statusMajor)
                }
            }
            .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 8)
            .frame(maxWidth: .infinity)
            .frame(height: 34)
            .background(isSelected ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                    .stroke(DS.Color.ink.opacity(isSelected ? 0 : 0.08), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var communityList: some View {
        if isLoadingReports && signalements.isEmpty {
            ProgressView().tint(DS.Color.ink).frame(maxWidth: .infinity).padding(.vertical, 24)
        } else if signalements.isEmpty {
            emptyStateCard(
                icon: "person.2.fill",
                title: "Pas de signalement communauté",
                detail: "Aucun usager n'a signalé d'incident actif sur cette gare."
            )
        } else {
            VStack(spacing: 8) {
                ForEach(signalements) { communityRow($0) }
            }
        }
    }

    private var officialPlaceholder: some View {
        emptyStateCard(
            icon: "checkmark.seal.fill",
            title: "Pas d'info officielle SNCB",
            detail: "Les perturbations officielles SNCB (retards, suppressions, travaux) arrivent bientôt."
        )
    }

    private var socialPlaceholder: some View {
        emptyStateCard(
            icon: "bubble.left.and.text.bubble.right.fill",
            title: "Twitter / X — bientôt",
            detail: "Recherche en temps réel des mentions SNCB / NMBS sur les réseaux. Intégration en cours."
        )
    }

    private func communityRow(_ signalement: SignalementDTO) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: SignalVisuals.icon(forType: signalement.typeProbleme))
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.community)
                .frame(width: 28, height: 28)
                .background(DS.Color.community.opacity(0.14))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(signalement.displayTypeProbleme)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                if !signalement.description.isEmpty {
                    Text(signalement.description)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(3)
                }
                Text(signalement.freshnessLabel)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer(minLength: 0)
            if let confirmations = signalement.community?.confirmations, confirmations > 0 {
                Text("\(confirmations)×")
                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.community)
            }
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }

    private var reportButton: some View {
        Button {
            onReport(station)
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "plus").font(.system(size: 16, weight: .black))
                Text("Signaler cette gare").font(DS.Font.bodyBold)
            }
            .foregroundStyle(DS.Color.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(DS.Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .padding(.top, 4)
    }

    private func emptyStateCard(icon: String, title: String, detail: String) -> some View {
        VStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 22))
                .foregroundStyle(DS.Color.inkMute)
            Text(title)
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
            Text(detail)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 22)
        .frame(maxWidth: .infinity)
        .background(DS.Color.paper2.opacity(0.4))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: - Derived data

    private var hasActiveTrafficIssue: Bool { !signalements.isEmpty }

    private var isViewingToday: Bool { schedule?.todayType == selectedDay }

    /// The departures actually shown: for today we drop everything before the
    /// current Brussels time (the user doesn't care about this morning's 5am
    /// trains) so the list opens on the next departure; other day-types show
    /// the full day.
    private var visibleList: [SNCBDeparture] {
        let list = schedule?.departures(for: selectedDay) ?? []
        guard isViewingToday else { return list }
        let now = brusselsNowMinutes
        return list.filter { $0.minutes >= now }
    }

    private var favoriteDepartures: [SNCBDeparture] {
        visibleList.filter {
            favorites.contains(SNCBDepartureFavorites.key(stationId: station.id, day: selectedDay, departure: $0))
        }
    }

    private var hourGroups: [(hour: Int, items: [SNCBDeparture])] {
        let grouped = Dictionary(grouping: visibleList) { $0.minutes / 60 }
        return grouped.keys.sorted().map { hour in
            (hour: hour, items: grouped[hour]!.sorted { $0.minutes < $1.minutes })
        }
    }

    private var nextDeparture: SNCBDeparture? {
        guard isViewingToday else { return nil }
        return visibleList.first
    }

    private var nextKey: String? { nextDeparture.map(key(for:)) }

    private func key(for dep: SNCBDeparture) -> String { "\(dep.minutes)-\(dep.destination)-\(dep.line)" }

    private var brusselsNowMinutes: Int {
        var cal = Calendar(identifier: .gregorian)
        if let tz = TimeZone(identifier: "Europe/Brussels") { cal.timeZone = tz }
        let c = cal.dateComponents([.hour, .minute], from: Date())
        return (c.hour ?? 0) * 60 + (c.minute ?? 0)
    }

    private func matchesStation(_ s: SignalementDTO) -> Bool {
        guard case .populated(let arret) = s.arretId else { return false }
        if let sid = arret.stopId, sid == station.id { return true }
        return arret.nom.normalizedStopKey == station.displayName.normalizedStopKey
    }

    // MARK: - Loading

    @MainActor
    private func load() async {
        async let schedTask = SNCBStationService.fullSchedule(stationId: station.id)
        async let repsTask = SignalementService.liste()

        let sched = await schedTask
        if let sched, !didInitDay {
            selectedDay = sched.todayType
            didInitDay = true
        }
        schedule = sched
        isLoadingSchedule = false

        applyReports((try? await repsTask) ?? [])
        isLoadingReports = false
    }

    @MainActor
    private func refresh() async {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        async let schedTask = SNCBStationService.fullSchedule(stationId: station.id)
        async let repsTask = SignalementService.liste()
        if let sched = await schedTask { schedule = sched }
        applyReports((try? await repsTask) ?? [])
    }

    @MainActor
    private func applyReports(_ all: [SignalementDTO]) {
        signalements = all
            .filter { $0.status != "resolved" && $0.ligne.uppercased() == "SNCB" && matchesStation($0) }
            .sorted { ($0.dateSignalement ?? .distantPast) > ($1.dateSignalement ?? .distantPast) }
    }
}
