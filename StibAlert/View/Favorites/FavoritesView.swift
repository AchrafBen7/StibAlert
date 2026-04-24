import SwiftUI

struct FavoritesView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var stibi: StibiCenter
    @State private var selectedFilter: FavoriteTransportFilter = .all
    @State private var query = ""
    @State private var selectedItem: FavoriteTransitItem?
    @State private var remoteItems: [FavoriteTransitItem] = []
    @State private var isLoadingRemote = false

    private var filteredItems: [FavoriteTransitItem] {
        let source = remoteItems.isEmpty ? FavoritesMockData.items : remoteItems
        let base = selectedFilter == .all
            ? source
            : source.filter { $0.filter == selectedFilter }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.code.localizedCaseInsensitiveContains(trimmed)
            || $0.problemLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ZStack {
            AppTheme.Palette.screen.ignoresSafeArea()

            if let selectedItem {
                FavoriteStopDetailView(
                    item: selectedItem,
                    onBack: { self.selectedItem = nil },
                    onClose: { self.selectedItem = nil }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        topBar
                            .padding(.horizontal, 21)
                            .padding(.top, 12)

                        filtersRow
                            .padding(.horizontal, 21)
                            .padding(.top, 24)

                        LazyVStack(spacing: 18) {
                            ForEach(filteredItems) { item in
                                Button {
                                    selectedItem = item
                                } label: {
                                    FavoriteTransitCard(item: item)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 21)
                        .padding(.top, 18)
                        .padding(.bottom, 28)
                    }
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            stibi.setCurrentScreen("favorites")
            await loadFavoris()
            await loadStibiContext()
        }
    }

    private var topBar: some View {
        HStack(spacing: 19) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                    nav.showSideMenu = true
                }
            } label: {
                Circle()
                    .fill(Color.white)
                    .frame(width: 42, height: 40)
                    .overlay(
                        Image(systemName: "line.3.horizontal")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color.black.opacity(0.8))
                    )
            }
            .buttonStyle(.plain)

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(.black)

                TextField("", text: $query, prompt: Text("Zoek hier naar een topic").foregroundStyle(Color.black.opacity(0.55)))
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundStyle(.black)
                    .textInputAutocapitalization(.words)
                    .autocorrectionDisabled()
            }
            .padding(.horizontal, 14)
            .frame(height: 40)
            .background(Color.white)
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Color.black, lineWidth: 1)
            )
        }
    }

    private var filtersRow: some View {
        HStack(spacing: 16) {
            ForEach(FavoriteTransportFilter.allCases) { filter in
                Button {
                    withAnimation(.easeInOut(duration: 0.18)) {
                        selectedFilter = filter
                    }
                } label: {
                    Text(filter.label)
                        .font(.custom("Montserrat-Regular", size: 15))
                        .foregroundStyle(selectedFilter == filter ? .black : .white)
                        .frame(width: filter == .metro ? 78 : 76, height: 35)
                        .background(selectedFilter == filter ? Color.white : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(Color.white, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func loadFavoris() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingRemote else { return }
        guard let user = session.currentUser else { return }

        isLoadingRemote = true
        defer { isLoadingRemote = false }

        do {
            let remoteUser = try await UtilisateurService.me()
            session.applyCurrentUserUpdate(remoteUser)
            remoteItems = mapFavoriteItems(from: remoteUser.favorisDetails ?? [], fallbackStops: user.favorisDetails ?? [])
        } catch {
            print("Favorites load failed: \(error.localizedDescription)")
        }
    }

    private func loadStibiContext() async {
        guard AppConfig.isBackendEnabled else { return }
        do {
            let context = try await AssistantService.context()
            stibi.pushContextInsight(for: "favorites", context: context)
        } catch {
            print("Favorites Stibi context failed: \(error.localizedDescription)")
        }
    }

    private func mapFavoriteItems(from stops: [FavoriDetailDTO], fallbackStops: [FavoriDetailDTO]) -> [FavoriteTransitItem] {
        let source = stops.isEmpty ? fallbackStops : stops
        guard !source.isEmpty else { return [] }

        return source.enumerated().map { index, stop in
            let primaryLine = stop.primaryLine ?? stop.lignesDesservies?.first ?? "\(index + 1)"
            let filter = FavoriteTransportFilter.from(lines: stop.lignesDesservies ?? [])
            let severity = FavoriteSeverity.from(status: stop.status)
            let problemLabel = stop.status ?? "Normal"

            return FavoriteTransitItem(
                stopBackendId: stop.id,
                stopId: stop.id,
                code: primaryLine,
                codeColor: filter.badgeColor,
                codeTextColor: filter.badgeTextColor,
                title: stop.nom,
                crowding: stop.crowding ?? "Faible",
                problemLabel: problemLabel,
                reportCount: stop.signalementCount ?? 0,
                nextPassage: stop.nextPassageMinutes.map { "\($0) min" } ?? "--",
                filter: filter,
                severity: severity,
                detailLines: (stop.lignesDesservies ?? [primaryLine]).prefix(4).map {
                    FavoriteLineChip(code: $0, color: filter.badgeColor, textColor: filter.badgeTextColor)
                },
                lastUpdatedAt: stop.lastUpdatedAt,
                lastProblemType: stop.lastProblemType,
                lastConfidence: stop.lastConfidence
            )
        }
    }
}

private struct FavoriteStopDetailView: View {
    let item: FavoriteTransitItem
    let onBack: () -> Void
    let onClose: () -> Void

    @State private var transportStop: TransportStopDTO?
    @State private var isLoadingTransportStop = false

    private var liveStatuses: [FavoriteLiveStatus] {
        if let transportStop {
            let fallbackLine = item.detailLines.first ?? FavoriteLineChip(code: item.code, color: item.codeColor, textColor: item.codeTextColor)
            let label = TransportViewAdapters.localizedSeverityLabel(
                severity: transportStop.severity,
                fallback: transportStop.label?.fr
            )

            let departures = transportStop.nextDepartures.prefix(2)
            if departures.isEmpty {
                return [
                    .init(
                        lineCode: fallbackLine.code,
                        lineColor: fallbackLine.color,
                        lineTextColor: fallbackLine.textColor,
                        title: label,
                        subtitle: "Aucun passage fiable immédiat. Je continue de surveiller cet arrêt.",
                        nextPassage: "--",
                        score: Int((transportStop.confidence * 100).rounded()),
                        barColor: statusBarColor(for: transportStop.severity),
                        borderColor: statusBorderColor(for: transportStop.severity)
                    )
                ]
            }

            return departures.enumerated().map { index, departure in
                let chip = item.detailLines.first(where: { $0.code == departure.line }) ?? fallbackLine
                return FavoriteLiveStatus(
                    lineCode: departure.line,
                    lineColor: chip.color,
                    lineTextColor: chip.textColor,
                    title: index == 0 ? label : "Passage suivant",
                    subtitle: departure.destination.map { "Direction \($0)" } ?? "Passage surveillé en temps réel",
                    nextPassage: "\(departure.minutes) min",
                    score: Int((transportStop.confidence * 100).rounded()),
                    barColor: statusBarColor(for: transportStop.severity),
                    borderColor: statusBorderColor(for: transportStop.severity)
                )
            }
        }

        return FavoriteStopDetailMockData.liveStatuses
    }

    private var incidents: [FavoriteIncident] {
        if let transportStop, !transportStop.activeIncidents.isEmpty {
            return transportStop.activeIncidents.map { incident in
                let lineCode = incident.line ?? item.code
                let chip = item.detailLines.first(where: { $0.code == lineCode }) ?? FavoriteLineChip(code: lineCode, color: item.codeColor, textColor: item.codeTextColor)
                return FavoriteIncident(
                    backendId: incident.id,
                    lineCode: lineCode,
                    lineColor: chip.color,
                    lineTextColor: chip.textColor,
                    title: incident.type ?? TransportViewAdapters.localizedSeverityLabel(severity: incident.severity, fallback: nil),
                    body: incident.description ?? "Aucun détail terrain disponible.",
                    background: incidentBackground(for: incident.severity),
                    dotColor: incidentDotColor(for: incident.severity),
                    confidenceText: incident.community.map(communitySummary(from:)) ?? confidenceLabel(for: incident.confidence)
                )
            }
        }

        return FavoriteStopDetailMockData.incidents
    }

    private var hasRemoteDetail: Bool {
        transportStop != nil
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                header
                    .padding(.horizontal, 21)
                    .padding(.top, 18)

                servedLines
                    .padding(.top, 18)

                planBCard
                    .padding(.horizontal, 15)
                    .padding(.top, 36)

                if let transportStop {
                    FavoriteStopDecisionCard(stop: transportStop)
                        .padding(.horizontal, 15)
                        .padding(.top, 18)
                }

                sectionHeader("Etat en temps réel", trailing: nil)
                    .padding(.horizontal, 21)
                    .padding(.top, 26)

                VStack(spacing: 14) {
                    ForEach(liveStatuses) { status in
                        LiveStatusCard(status: status)
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                sectionHeader("Situation actuelle", trailing: "Mise à jour : Il y a 6 min")
                    .padding(.horizontal, 21)
                    .padding(.top, 30)

                VStack(spacing: 14) {
                    ForEach(incidents) { incident in
                        if hasRemoteDetail, let backendId = incident.backendId {
                            FavoriteTransportIncidentCard(
                                incident: incident,
                                onConfirm: { await runCommunityAction(for: backendId, action: .confirm) },
                                onStillBlocked: { await runCommunityAction(for: backendId, action: .stillBlocked) },
                                onResolved: { await runCommunityAction(for: backendId, action: .resolved) }
                            )
                        } else {
                            IncidentCard(incident: incident)
                        }
                    }
                }
                .padding(.horizontal, 15)
                .padding(.top, 12)

                Button {} label: {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .medium))
                        Text("Voir tout les signalements (5)")
                            .font(.custom("Montserrat-Regular", size: 12))
                    }
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 49)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.horizontal, 15)
                .padding(.top, 18)
                .padding(.bottom, 20)
            }
        }
        .background(Color(hex: "#1B1B1B"))
        .task(id: item.stopBackendId) {
            await loadTransportStop()
        }
    }

    private var header: some View {
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 15, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text(item.title)
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var servedLines: some View {
        HStack(spacing: 9) {
            ForEach(item.detailLines) { line in
                Text(line.code)
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(line.textColor)
                    .frame(width: 32, height: 32)
                    .background(line.color)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var planBCard: some View {
        Button {} label: {
            HStack {
                Spacer()
                Text("Besoin d’un plan B ?")
                    .font(.custom("DelaGothicOne-Regular", size: 12))
                    .foregroundStyle(Color(hex: "#322944"))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.black.opacity(0.78))
            }
            .frame(height: 63)
            .padding(.horizontal, 18)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        }
        .buttonStyle(.plain)
    }

    private func loadTransportStop() async {
        guard AppConfig.isBackendEnabled else { return }
        guard let stopBackendId = item.stopBackendId else { return }
        guard !isLoadingTransportStop else { return }

        isLoadingTransportStop = true
        defer { isLoadingTransportStop = false }

        do {
            transportStop = try await TransportService.stop(id: stopBackendId)
        } catch {
            print("Favorite transport stop load failed: \(error.localizedDescription)")
        }
    }

    private func runCommunityAction(for signalementId: String, action: FavoriteCommunityAction) async {
        do {
            switch action {
            case .confirm:
                _ = try await SignalementService.confirmer(signalementId: signalementId)
            case .stillBlocked:
                _ = try await SignalementService.toujoursBloque(signalementId: signalementId)
            case .resolved:
                _ = try await SignalementService.resoudre(signalementId: signalementId)
            }
            await loadTransportStop()
        } catch {
            print("Favorite community action failed: \(error.localizedDescription)")
        }
    }

    private func statusBarColor(for severity: String) -> Color {
        switch severity {
        case "critical":
            return Color(hex: "#FF7178")
        case "major":
            return Color(hex: "#FF922A")
        case "minor":
            return Color(hex: "#7CB2FF")
        default:
            return Color(hex: "#10C994")
        }
    }

    private func statusBorderColor(for severity: String) -> Color {
        switch severity {
        case "critical":
            return Color(hex: "#FFD1D4")
        case "major":
            return Color(hex: "#FFC98D")
        case "minor":
            return Color(hex: "#C7DBFF")
        default:
            return Color(hex: "#B7F2DE")
        }
    }

    private func incidentBackground(for severity: String?) -> Color {
        switch severity {
        case "critical":
            return Color(hex: "#FFB3B7")
        case "major":
            return Color(hex: "#FFD29D")
        case "minor":
            return Color(hex: "#CFE0FF")
        default:
            return Color(hex: "#CFF8E7")
        }
    }

    private func incidentDotColor(for severity: String?) -> Color {
        switch severity {
        case "critical":
            return Color(hex: "#FF7178")
        case "major":
            return Color(hex: "#FF922A")
        case "minor":
            return Color(hex: "#7CB2FF")
        default:
            return Color(hex: "#49D7A5")
        }
    }

    private func confidenceLabel(for confidence: Double?) -> String? {
        guard let confidence else { return nil }
        return "\(Int((confidence * 100).rounded()))% de confiance"
    }

    private func communitySummary(from community: SignalementCommunityDTO) -> String {
        if let confirmations = community.confirmations, confirmations > 0 {
            return "\(confirmations) confirmation(s) terrain"
        }
        if let resolved = community.resolved, resolved > 0 {
            return "\(resolved) retour(s) vers la résolution"
        }
        return confidenceLabel(for: community.confidence) ?? "Lecture communautaire active"
    }

    private func sectionHeader(_ title: String, trailing: String?) -> some View {
        HStack {
            HStack(spacing: 6) {
                Text(title)
                    .font(.custom("Montserrat-SemiBold", size: 14))
                    .foregroundStyle(.white)

                if title == "Etat en temps réel" {
                    Image(systemName: "dot.radiowaves.left.and.right")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.white)
                } else {
                    Image(systemName: "questionmark.circle.fill")
                        .font(.system(size: 12))
                        .foregroundStyle(.white)
                }
            }

            Spacer()

            if let trailing {
                HStack(spacing: 6) {
                    Text(trailing)
                        .font(.custom("DelaGothicOne-Regular", size: 12))
                        .foregroundStyle(.white)
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(.white)
                }
            }
        }
    }
}

private struct FavoriteTransitCard: View {
    let item: FavoriteTransitItem

    private var problemBackground: Color {
        switch item.severity {
        case .normal:
            return Color(hex: "#CFF8E7")
        case .warning:
            return Color(hex: "#FFD29D")
        case .blocked:
            return Color(hex: "#FFC1C1")
        }
    }

    private var problemStroke: Color {
        switch item.severity {
        case .normal:
            return Color(hex: "#5ED9AF")
        case .warning:
            return Color(hex: "#F59A3B")
        case .blocked:
            return Color(hex: "#FF8686")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(item.code)
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(item.codeTextColor)
                    .frame(width: 32, height: 32)
                    .background(item.codeColor)
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(item.title)
                        .font(.custom("Montserrat-SemiBold", size: 15))
                        .foregroundStyle(.black)

                    HStack(spacing: 6) {
                        Circle()
                            .fill(item.cockpitAccent)
                            .frame(width: 8, height: 8)
                        Text(item.cockpitHeadline)
                            .font(.custom("Montserrat-SemiBold", size: 12))
                            .foregroundStyle(.black)
                            .lineLimit(1)
                    }

                    HStack(spacing: 4) {
                        Image(systemName: "clock.arrow.circlepath")
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(.black.opacity(0.7))

                        Text(item.lastUpdatedLabel)
                            .font(.custom("Montserrat-Regular", size: 11))
                            .foregroundStyle(.black.opacity(0.7))
                    }
                }

                Spacer(minLength: 8)

                HStack(spacing: 16) {
                    Image(systemName: "bell")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(.black)

                    Image(systemName: "heart.fill")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundStyle(Color(hex: "#7CB2FF"))
                }
                .padding(.top, 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(180))

                Text("Affluence: \(item.crowding)")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black.opacity(0.82))
            }
            .padding(.top, 16)

            HStack(alignment: .bottom) {
                HStack(spacing: 10) {
                    Text(item.problemLabel)
                        .font(item.severity == .normal ? .custom("Montserrat-Regular", size: 12) : .custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 14)
                        .frame(height: 35)
                        .background(problemBackground)
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(problemStroke, lineWidth: 1)
                        )

                    HStack(spacing: 5) {
                        Circle()
                            .fill(.black)
                            .frame(width: 12, height: 12)
                            .overlay(
                                Text("i")
                                    .font(.system(size: 8, weight: .bold))
                                    .foregroundStyle(.white)
                            )

                        Text("\(item.reportCount)")
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(.black)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 6) {
                    Text("Prochain passage")
                        .font(.custom("DelaGothicOne-Regular", size: 12))
                        .foregroundStyle(.black.opacity(0.92))

                    Text(item.nextPassage)
                        .font(.custom("Montserrat-SemiBold", size: 16))
                        .foregroundStyle(.black)
                }
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 20)
        .padding(.top, 13)
        .padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(Color(hex: "#83B3FF"), lineWidth: 1)
        )
    }
}

private struct LiveStatusCard: View {
    let status: FavoriteLiveStatus

    private var scoreColor: Color {
        status.score >= 80 ? Color(hex: "#10B981") : Color(hex: "#FF922A")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(status.lineCode)
                    .font(.custom("Montserrat-SemiBold", size: 20))
                    .foregroundStyle(status.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(status.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundStyle(.black)

                    Text(status.subtitle)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Prochain passage")
                        .font(.custom("DelaGothicOne-Regular", size: 12))
                        .foregroundStyle(.black)

                    Text(status.nextPassage)
                        .font(.custom("Montserrat-SemiBold", size: 20))
                        .foregroundStyle(.black)
                }
            }

            HStack {
                Label("Fiabilité du Service", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.black)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Score")
                        .font(.custom("DelaGothicOne-Regular", size: 12))
                        .foregroundStyle(.black)
                    Text("\(status.score)%")
                        .font(.custom("Montserrat-SemiBold", size: 14))
                        .foregroundStyle(scoreColor)
                }
            }
            .padding(.top, 26)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color(hex: "#E6EAF0"))
                    .frame(height: 13)

                Capsule()
                    .fill(status.barColor)
                    .frame(width: max(16, CGFloat(status.score) * 3.05), height: 13)
            }
            .padding(.top, 8)

            HStack {
                Text("0%")
                Spacer()
                Text("50%")
                Spacer()
                Text("100%")
            }
            .font(.custom("Montserrat-Regular", size: 12))
            .foregroundStyle(Color(hex: "#969BA6"))
            .padding(.top, 4)
        }
        .padding(.horizontal, 14)
        .padding(.top, 17)
        .padding(.bottom, 12)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(status.borderColor, lineWidth: 1)
        )
    }
}

private struct IncidentCard: View {
    let incident: FavoriteIncident

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                Text(incident.lineCode)
                    .font(.custom("Montserrat-SemiBold", size: 20))
                    .foregroundStyle(incident.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(incident.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 4) {
                    Text(incident.title)
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundStyle(.black)

                    Text(incident.body)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(incident.dotColor)
                    .frame(width: 12, height: 12)
            }

            HStack {
                Text("Confirmez cette situation ?")
                    .font(.custom("Montserrat-Regular", size: 10))
                    .foregroundStyle(.black.opacity(0.9))

                Spacer()

                Button {} label: {
                    Image(systemName: "paperplane.fill")
                        .font(.system(size: 16, weight: .medium))
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 18)
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(incident.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }
}

private struct FavoriteStopDecisionCard: View {
    let stop: TransportStopDTO

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Décision Stibi")
                    .font(.custom("Montserrat-SemiBold", size: 16))
                    .foregroundStyle(.white)

                Spacer()

                Text(TransportViewAdapters.localizedSeverityLabel(severity: stop.severity, fallback: stop.label?.fr))
                    .font(.custom("DelaGothicOne-Regular", size: 12))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(Color(hex: "#D9E8FF"))
                    .clipShape(Capsule())
            }

            if let alternative = stop.recommendedAlternatives.first {
                Text(alternative.explanationDetails?.summary ?? alternative.explanation)
                    .font(.custom("Montserrat-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)

                if let firstHighlight = alternative.explanationDetails?.highlights.first {
                    Text(firstHighlight)
                        .font(.custom("DelaGothicOne-Regular", size: 11))
                        .foregroundStyle(Color(hex: "#9ED0FF"))
                }
            } else if let incident = stop.activeIncidents.first?.description {
                Text(incident)
                    .font(.custom("Montserrat-Regular", size: 13))
                    .foregroundStyle(.white.opacity(0.9))
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(hex: "#101725"))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
    }
}

private struct FavoriteTransportIncidentCard: View {
    let incident: FavoriteIncident
    let onConfirm: () async -> Void
    let onStillBlocked: () async -> Void
    let onResolved: () async -> Void

    @State private var isSubmitting = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 10) {
                Text(incident.lineCode)
                    .font(.custom("Montserrat-SemiBold", size: 20))
                    .foregroundStyle(incident.lineTextColor)
                    .frame(width: 42, height: 41)
                    .background(incident.lineColor)
                    .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                VStack(alignment: .leading, spacing: 5) {
                    Text(incident.title)
                        .font(.custom("Montserrat-SemiBold", size: 18))
                        .foregroundStyle(.black)

                    Text(incident.body)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(.black)
                        .fixedSize(horizontal: false, vertical: true)

                    if let confidenceText = incident.confidenceText {
                        Text(confidenceText)
                            .font(.custom("DelaGothicOne-Regular", size: 11))
                            .foregroundStyle(.black.opacity(0.78))
                    }
                }

                Spacer(minLength: 8)

                Circle()
                    .fill(incident.dotColor)
                    .frame(width: 12, height: 12)
            }

            HStack(spacing: 8) {
                communityButton("Je confirme", action: onConfirm)
                communityButton("Toujours bloqué", action: onStillBlocked)
                communityButton("Résolu", action: onResolved)
            }
        }
        .padding(.horizontal, 14)
        .padding(.top, 20)
        .padding(.bottom, 12)
        .background(incident.background)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
    }

    private func communityButton(_ title: String, action: @escaping () async -> Void) -> some View {
        Button {
            guard !isSubmitting else { return }
            isSubmitting = true
            Task {
                await action()
                await MainActor.run {
                    isSubmitting = false
                }
            }
        } label: {
            Text(title)
                .font(.custom("Montserrat-SemiBold", size: 11))
                .foregroundStyle(.white)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(Color.black.opacity(0.82))
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting)
    }
}

private enum FavoriteCommunityAction {
    case confirm
    case stillBlocked
    case resolved
}

private enum FavoriteTransportFilter: CaseIterable, Identifiable {
    case all
    case tram
    case bus
    case metro

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return "Tous"
        case .tram: return "Tram"
        case .bus: return "Bus"
        case .metro: return "Metro"
        }
    }

    static func from(lines: [String]) -> FavoriteTransportFilter {
        let types = lines
        if types.contains(where: { ["1", "2", "5", "6"].contains($0) }) { return .metro }
        if let line = types.first, Int(line) ?? 100 >= 90 { return .bus }
        if !types.isEmpty { return .tram }
        return .all
    }

    var badgeColor: Color {
        switch self {
        case .all: return Color(hex: "#A67CB0")
        case .tram: return Color(hex: "#F29DC3")
        case .bus: return Color(hex: "#ED7807")
        case .metro: return Color(hex: "#8F4199")
        }
    }

    var badgeTextColor: Color {
        switch self {
        case .tram: return .black
        default: return .white
        }
    }
}

private enum FavoriteSeverity {
    case normal
    case warning
    case blocked

    static func from(status: String?) -> FavoriteSeverity {
        switch status {
        case "Bloqué":
            return .blocked
        case "Perturbé":
            return .warning
        default:
            return .normal
        }
    }
}

private struct FavoriteTransitItem: Identifiable {
    let id = UUID()
    let stopBackendId: String?
    let stopId: String?
    let code: String
    let codeColor: Color
    let codeTextColor: Color
    let title: String
    let crowding: String
    let problemLabel: String
    let reportCount: Int
    let nextPassage: String
    let filter: FavoriteTransportFilter
    let severity: FavoriteSeverity
    let detailLines: [FavoriteLineChip]
    var lastUpdatedAt: Date? = nil
    var lastProblemType: String? = nil
    var lastConfidence: String? = nil

    var cockpitHeadline: String {
        switch severity {
        case .normal:
            return reportCount == 0 ? "Traffic fluide" : "1 signalement léger"
        case .warning:
            if let type = lastProblemType {
                return "\(type) en cours"
            }
            return "\(reportCount) signalements actifs"
        case .blocked:
            if let type = lastProblemType {
                return "\(type) — service perturbé"
            }
            return "\(reportCount) signalements critiques"
        }
    }

    var cockpitAccent: Color {
        switch severity {
        case .normal: return Color(hex: "#10B981")
        case .warning: return Color(hex: "#F59A3B")
        case .blocked: return Color(hex: "#E23B3B")
        }
    }

    var lastUpdatedLabel: String {
        guard let date = lastUpdatedAt else { return "Mis à jour à l'instant" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "Mis à jour à l'instant" }
        let minutes = seconds / 60
        if minutes < 60 { return "Mis à jour il y a \(minutes) min" }
        let hours = minutes / 60
        return "Mis à jour il y a \(hours) h"
    }
}

private struct FavoriteLineChip: Identifiable {
    let id = UUID()
    let code: String
    let color: Color
    let textColor: Color
}

private struct FavoriteLiveStatus: Identifiable {
    let id = UUID()
    let lineCode: String
    let lineColor: Color
    let lineTextColor: Color
    let title: String
    let subtitle: String
    let nextPassage: String
    let score: Int
    let barColor: Color
    let borderColor: Color
}

private struct FavoriteIncident: Identifiable {
    let id = UUID()
    let backendId: String?
    let lineCode: String
    let lineColor: Color
    let lineTextColor: Color
    let title: String
    let body: String
    let background: Color
    let dotColor: Color
    let confidenceText: String?
}

private enum FavoritesMockData {
    static let items: [FavoriteTransitItem] = [
        .init(stopBackendId: nil, stopId: nil, code: "46", codeColor: Color(hex: "#E43C2E"), codeTextColor: .white, title: "De Wand", crowding: "Haute", problemLabel: "Perturbé", reportCount: 12, nextPassage: "15 min", filter: .bus, severity: .warning, detailLines: [.init(code: "46", color: Color(hex: "#F29DC3"), textColor: .black), .init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "10", color: Color(hex: "#8F4199"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "62", codeColor: Color(hex: "#F29DC3"), codeTextColor: .black, title: "Leopold III", crowding: "Faible", problemLabel: "Normal", reportCount: 1, nextPassage: "5 min", filter: .tram, severity: .normal, detailLines: [.init(code: "46", color: Color(hex: "#F29DC3"), textColor: .black), .init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "10", color: Color(hex: "#8F4199"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "38", codeColor: Color(hex: "#A67CB0"), codeTextColor: .white, title: "Suzan Daniel", crowding: "Moyenne", problemLabel: "Bloqué", reportCount: 16, nextPassage: "/", filter: .tram, severity: .blocked, detailLines: [.init(code: "38", color: Color(hex: "#A67CB0"), textColor: .white), .init(code: "51", color: Color(hex: "#91BEE5"), textColor: .black)]),
        .init(stopBackendId: nil, stopId: nil, code: "48", codeColor: Color(hex: "#ED7807"), codeTextColor: .white, title: "Heembeek", crowding: "Faible", problemLabel: "Normal", reportCount: 1, nextPassage: "5 min", filter: .bus, severity: .normal, detailLines: [.init(code: "48", color: Color(hex: "#ED7807"), textColor: .white), .init(code: "56", color: Color(hex: "#0066A3"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "1", codeColor: Color(hex: "#8F4199"), codeTextColor: .white, title: "Gare de l’ouest", crowding: "Moyenne", problemLabel: "Perturbé", reportCount: 3, nextPassage: "2 min", filter: .metro, severity: .warning, detailLines: [.init(code: "1", color: Color(hex: "#8F4199"), textColor: .white), .init(code: "5", color: Color(hex: "#F9A611"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "7", codeColor: Color(hex: "#EFE048"), codeTextColor: .black, title: "Vanderkindere", crowding: "Haute", problemLabel: "Bloqué", reportCount: 9, nextPassage: "8 min", filter: .tram, severity: .blocked, detailLines: [.init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "92", color: Color(hex: "#4C8B33"), textColor: .white)])
    ]
}

private enum FavoriteStopDetailMockData {
    static let liveStatuses: [FavoriteLiveStatus] = [
        .init(lineCode: "46", lineColor: Color(hex: "#F29DC3"), lineTextColor: .black, title: "Traffic Normal", subtitle: "Tout fonctionne\nparfaitement", nextPassage: "3 min", score: 94, barColor: Color(hex: "#10C994"), borderColor: Color(hex: "#B7F2DE")),
        .init(lineCode: "7", lineColor: Color(hex: "#EFE048"), lineTextColor: .black, title: "Traffic Perturbé", subtitle: "Perturbations\nmineures", nextPassage: "12min", score: 64, barColor: Color(hex: "#FF922A"), borderColor: Color(hex: "#FFC98D"))
    ]

    static let incidents: [FavoriteIncident] = [
        .init(backendId: nil, lineCode: "10", lineColor: Color(hex: "#8F4199"), lineTextColor: .white, title: "Traffic Normal", body: "Aucun problème détecté\nrécemment sur cette ligne.\nLe service semble\nfonctionner normalement.", background: Color(hex: "#CFF8E7"), dotColor: Color(hex: "#49D7A5"), confidenceText: nil),
        .init(backendId: nil, lineCode: "7", lineColor: Color(hex: "#EFE048"), lineTextColor: .black, title: "Retard", body: "Un incident a été signalé à l'arrêt\nDelacroix : une personne présente\nsur la voie a provoqué un arrêt\ntemporaire de la circulation. Les\nautorités sont intervenues. Des\nretards de 10 à 15 minutes sont à\nprévoir sur la ligne 46.", background: Color(hex: "#FFD29D"), dotColor: Color(hex: "#FF922A"), confidenceText: nil),
        .init(backendId: nil, lineCode: "46", lineColor: Color(hex: "#F29DC3"), lineTextColor: .black, title: "Accident", body: "Un incident a été signalé à l'arrêt\nDelacroix : une personne présente\nsur la voie a provoqué un arrêt\ntemporaire de la circulation. Les\nautorités sont intervenues. Des\nretards de 10 à 15 minutes sont à\nprévoir sur la ligne 46.", background: Color(hex: "#FFB3B7"), dotColor: Color(hex: "#FF7178"), confidenceText: nil)
    ]
}
