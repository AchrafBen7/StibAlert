import SwiftUI
import CoreLocation

struct FavoritesView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @State private var selectedFilter: FavoriteTransportFilter = .all
    @State private var query = ""
    @State private var selectedOperator: TransitOperator = .stib
    @State private var selectedGareForDetail: SNCBStation?
    @ObservedObject private var gareFavorites = SNCBGareFavorites.shared
    @ObservedObject private var operatorFavorites = OperatorStopFavorites.shared
    @State private var selectedItem: FavoriteTransitItem?
    @State private var remoteItems: [FavoriteTransitItem] = []
    @State private var isLoadingRemote = false
    @State private var hasLoadedFavorites = false
    @State private var showAddSheet = false
    @State private var stibLineMetadata: [String: FavoriteFollowedLineMetadata] = [:]

    private var displayItems: [FavoriteTransitItem] {
        AppConfig.isBackendEnabled ? remoteItems : (remoteItems.isEmpty ? FavoritesMockData.items : remoteItems)
    }

    private var filteredItems: [FavoriteTransitItem] {
        let base = selectedFilter == .all
            ? displayItems
            : displayItems.filter { $0.modes.contains(selectedFilter) }

        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.code.localizedCaseInsensitiveContains(trimmed)
            || $0.problemLabel.localizedCaseInsensitiveContains(trimmed)
        }
    }

    private var followedLines: [String] {
        let remote = session.currentUser?.favoriteLines ?? []
        if !remote.isEmpty {
            return remote.sorted(by: sortLine)
        }

        let derived = Set(displayItems.flatMap { item in
            item.detailLines.map(\.code)
        })
        return Array(derived).sorted(by: sortLine)
    }

    private var followedLineDisplays: [FavoriteFollowedLineDisplay] {
        followedLines.map { rawLine in
            let parsed = parseFavoriteLine(rawLine)
            let metadata = stibLineMetadata[rawLine.uppercased()]
                ?? stibLineMetadata[parsed.code.uppercased()]

            let operatorType = parsed.operatorType ?? .stib
            // FIX — couleur d'une ligne suivie = TOUJOURS la palette STIB
            // officielle pour les lignes STIB (même source que les arrêts
            // épinglés). La couleur backend (metadata.color) primait et pouvait
            // diverger : la ligne 10 sortait en ROUGE ici alors qu'elle est
            // violette partout ailleurs. metadata sert encore au nom/direction.
            let fill = operatorType == .stib ? TransitLinePalette.fill(for: parsed.code) : (metadata?.color ?? operatorType.brandColor)
            let foreground = operatorType == .stib ? TransitLinePalette.foreground(for: parsed.code) : (metadata?.textColor ?? operatorType.brandTextColor)
            let subtitle = metadata?.directionLabel ?? parsed.operatorType?.shortName
            let isDisrupted = disruptedLines.contains(parsed.code) || disruptedLines.contains(rawLine)

            return FavoriteFollowedLineDisplay(
                rawLine: rawLine,
                code: parsed.code,
                subtitle: subtitle,
                color: fill,
                textColor: foreground,
                isDisrupted: isDisrupted
            )
        }
    }

    private var disruptedLines: Set<String> {
        Set(displayItems.flatMap { item -> [String] in
            guard item.severity != .normal else { return [] }
            return item.detailLines.map(\.code)
        })
    }

    var body: some View {
        if session.isGuest {
            GuestTabPlaceholder(
                reason: .favorites,
                onSignIn: {
                    nav.authInitialRoute = .signIn
                    nav.showAuthFlow = true
                },
                onSignUp: {
                    nav.authInitialRoute = .signUp
                    nav.showAuthFlow = true
                }
            )
        } else {
            ZStack {
                DS.Color.paper.ignoresSafeArea()

                if let selectedItem {
                    FavoriteStopDetailView(
                        item: selectedItem,
                        onBack: { self.selectedItem = nil },
                        onClose: { self.selectedItem = nil }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))
                } else {
                    ScrollView(showsIndicators: false) {
                        VStack(spacing: 0) {
                            header
                            TransitOperatorRow(
                                activeOperator: selectedOperator,
                                enabledOperators: [.stib, .sncb, .delijn, .tec],
                                onSelect: { selectedOperator = $0 }
                            )
                            .padding(.horizontal, 20)
                            .padding(.top, 14)

                            if selectedOperator == .sncb {
                                sncbFavoritesContent
                            } else if selectedOperator == .delijn || selectedOperator == .tec {
                                operatorFavoritesContent(selectedOperator)
                            } else {
                                stibFavoritesContent
                            }
                        }
                    }
                    .fullScreenCover(item: $selectedGareForDetail) { gare in
                        GareDetailPage(station: gare, initialTab: .schedule, onReport: { _ in
                            selectedGareForDetail = nil
                            nav.showReportSheet = true
                        })
                        .environmentObject(session)
                        .environmentObject(nav)
                    }
                }
            }
            .modifier(PaperGrainBackground())
            .toolbar(.hidden, for: .navigationBar)
            .task(id: session.currentUser?.id) {
                await loadFavoris()
            }
            .task(id: followedLines.joined(separator: "|")) {
                await loadFollowedLineMetadata()
            }
            .onChange(of: session.currentUser?.favorisDetails?.map(\.id) ?? []) { _, _ in
                syncRemoteItemsFromSession()
            }
            .onChange(of: session.currentUser?.favoris ?? []) { _, _ in
                syncRemoteItemsFromSession()
            }
            .sheet(isPresented: $showAddSheet, onDismiss: {
                Task { await loadFavoris() }
            }) {
                // The + adds a favourite for the *currently selected* operator.
                switch selectedOperator {
                case .sncb:
                    AddSncbFavoriteSheet(onClose: { showAddSheet = false })
                case .delijn, .tec:
                    AddOperatorFavoriteSheet(op: selectedOperator, onClose: { showAddSheet = false })
                default:
                    AddFavoriteSheet(
                        existingIds: Set(remoteItems.compactMap(\.stopBackendId)),
                        onClose: { showAddSheet = false }
                    )
                    .environmentObject(session)
                }
            }
        } // end else (guest check)
    }

    @ViewBuilder
    private var stibFavoritesContent: some View {
        searchRow
            .padding(.horizontal, 20)
            .padding(.top, 16)

        filtersRow
            .padding(.horizontal, 20)
            .padding(.top, 16)

        if (isLoadingRemote || !hasLoadedFavorites) && displayItems.isEmpty {
            SkeletonList(count: 4, style: .card)
                .padding(.horizontal, 20)
                .padding(.top, 20)
        } else if AppConfig.isBackendEnabled && displayItems.isEmpty {
            favoritesEmptyState
        } else if filteredItems.isEmpty {
            searchEmptyState
        } else {
            VStack(alignment: .leading, spacing: 28) {
                pinnedStopsSection
                followedLinesSection
                smartBriefsSection
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
    }

    private var favoriteGares: [SNCBStation] {
        gareFavorites.stations.sorted {
            $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending
        }
    }

    @ViewBuilder
    private var sncbFavoritesContent: some View {
        if favoriteGares.isEmpty {
            sncbFavoritesEmptyState
        } else {
            VStack(alignment: .leading, spacing: 12) {
                FavoriteSectionHeading(text: "GARES ÉPINGLÉES", systemImage: "star.fill")
                VStack(spacing: 0) {
                    ForEach(favoriteGares) { sncbGareRow($0) }
                }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .padding(.horizontal, 20)
            .padding(.top, 20)
            .padding(.bottom, 96)
        }
    }

    private func sncbGareRow(_ station: SNCBStation) -> some View {
        Button { selectedGareForDetail = station } label: {
            HStack(spacing: 12) {
                Image("operator-sncb")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .background(DS.Color.paper2.opacity(0.65))
                    .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
                VStack(alignment: .leading, spacing: 2) {
                    Text(station.displayName)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Text("\(station.displayProvince) · Gare SNCB")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(DS.Color.paper)
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.10)).frame(height: 1), alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var sncbFavoritesEmptyState: some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 50)
            Image(systemName: "star")
                .font(.system(size: 26))
                .foregroundStyle(DS.Color.inkMute)
            Text("Aucune gare en favori")
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
            Text("Ouvrez une gare (Horaires ou Infos trafic) et appuyez sur ★ pour l'épingler ici.")
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 24)
        .padding(.top, 20)
        .padding(.bottom, 96)
    }

    @ViewBuilder
    private func operatorFavoritesContent(_ op: TransitOperator) -> some View {
        let favs = operatorFavorites.stops(for: op)
        if favs.isEmpty {
            VStack(spacing: 10) {
                Spacer().frame(height: 50)
                Image(systemName: "star").font(.system(size: 26)).foregroundStyle(DS.Color.inkMute)
                Text("Aucun arrêt \(op.mapLabel) en favori").font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink)
                Text("Appuyez sur + pour épingler un arrêt \(op.mapLabel) proche.")
                    .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute).multilineTextAlignment(.center)
                Spacer()
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 24).padding(.top, 20).padding(.bottom, 96)
        } else {
            VStack(alignment: .leading, spacing: 12) {
                FavoriteSectionHeading(text: "ARRÊTS ÉPINGLÉS", systemImage: "star.fill")
                VStack(spacing: 0) {
                    ForEach(favs) { operatorFavoriteRow($0) }
                }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            }
            .padding(.horizontal, 20).padding(.top, 20).padding(.bottom, 96)
        }
    }

    private func operatorFavoriteRow(_ fav: FavoriteOperatorStop) -> some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().fill(fav.operatorType.brandColor).frame(width: 40, height: 40)
                Image(systemName: "bus.fill").font(.system(size: 14, weight: .black)).foregroundStyle(fav.operatorType.brandTextColor)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(fav.name).font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink).lineLimit(1)
                Text("Arrêt \(fav.operatorType.mapLabel)").font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
            }
            Spacer()
            Button {
                operatorFavorites.remove(fav)
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            } label: {
                Image(systemName: "star.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.primary)
                    .frame(width: 36, height: 36)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Retirer des favoris")
        }
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background(DS.Color.paper)
        .overlay(Rectangle().fill(DS.Color.ink.opacity(0.10)).frame(height: 1), alignment: .bottom)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            // Compact title — kept consistent with Infos trafic / Horaires
            // headers. Dropped the eyebrow + Dela Gothic displayH1 to free
            // vertical space on a content-dense page.
            Text("Favoris")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 12)
            Button {
                showAddSheet = true
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(PressableScaleStyle())
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    private var searchRow: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)

            TextField("Rechercher une ligne ou un arrêt", text: $query)
                .font(.system(size: 13.5))
                .foregroundStyle(DS.Color.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
        }
        .padding(.horizontal, 14)
        .frame(height: 44)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var filtersRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(FavoriteTransportFilter.allCases) { filter in
                    Chip(label: filter.label, active: selectedFilter == filter, icon: {
                        Image(systemName: filter.iconName)
                    }) {
                        withAnimation(.easeInOut(duration: 0.18)) {
                            selectedFilter = filter
                        }
                    }
                }
            }
        }
    }

    private func loadFavoris() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoadingRemote else { return }
        guard let user = session.currentUser else {
            remoteItems = []
            hasLoadedFavorites = true
            return
        }

        syncRemoteItemsFromSession()
        isLoadingRemote = true
        defer {
            isLoadingRemote = false
            hasLoadedFavorites = true
        }

        do {
            let remoteUser = try await UtilisateurService.me()
            session.applyCurrentUserUpdate(remoteUser)
            let fallbackStops = user.favorisDetails ?? []
            let favoriteDetails = await resolvedFavoriteDetails(
                remoteUser: remoteUser,
                fallbackStops: fallbackStops,
                fallbackIds: user.favoris ?? []
            )
            remoteItems = mapFavoriteItems(from: favoriteDetails, fallbackStops: fallbackStops)
        } catch {
            print("Favorites load failed: \(error.localizedDescription)")
            syncRemoteItemsFromSession()
        }
    }

    private func syncRemoteItemsFromSession() {
        guard let user = session.currentUser else {
            remoteItems = []
            return
        }
        // C5 — Avant : from: et fallbackStops: étaient le MÊME tableau, le
        // fallback ne pouvait jamais aider. Maintenant : si favorisDetails
        // est vide (cas réel quand le sync n'est pas encore arrivé) on garde
        // les items déjà mappés en local plutôt que de passer à un tableau
        // vide qui faisait disparaître les favoris pendant le re-fetch.
        let fresh = user.favorisDetails ?? []
        let existing = remoteItems
        if fresh.isEmpty && !existing.isEmpty {
            // Pas de payload neuf, on garde l'état UI courant — évite le
            // flash "tu n'as pas de favoris" pendant 100-200 ms.
            return
        }
        remoteItems = mapFavoriteItems(from: fresh, fallbackStops: fresh)
    }

    private func resolvedFavoriteDetails(
        remoteUser: UtilisateurDTO,
        fallbackStops: [FavoriDetailDTO],
        fallbackIds: [String]
    ) async -> [FavoriDetailDTO] {
        if let details = remoteUser.favorisDetails, !details.isEmpty {
            return details
        }

        let ids = remoteUser.favoris?.isEmpty == false ? (remoteUser.favoris ?? []) : fallbackIds
        guard !ids.isEmpty else { return fallbackStops }

        return await hydrateFavoriteDetails(ids: ids, fallbackStops: fallbackStops)
    }

    private func hydrateFavoriteDetails(
        ids: [String],
        fallbackStops: [FavoriDetailDTO]
    ) async -> [FavoriDetailDTO] {
        let fallbackById = Dictionary(uniqueKeysWithValues: fallbackStops.map { ($0.id, $0) })
        var hydrated: [FavoriDetailDTO] = []

        for id in ids {
            if let fallback = fallbackById[id] {
                hydrated.append(fallback)
                continue
            }

            if let stopDetail = try? await TransportService.stop(id: id) {
                hydrated.append(favoriteDetail(from: stopDetail))
            }
        }

        return hydrated
    }

    private func favoriteDetail(from stopDetail: TransportStopDTO) -> FavoriDetailDTO {
        let stop = stopDetail.stop
        let primaryLine = stop.lines.first ?? stopDetail.nextDepartures.first?.line
        let status = stopDetail.label?.fr ?? stopDetail.severity
        let nextPassage = stopDetail.nextDepartures.map(\.minutes).min()

        return FavoriDetailDTO(
            id: stop.id,
            nom: stop.name,
            latitude: stop.latitude,
            longitude: stop.longitude,
            lignesDesservies: stop.lines.isEmpty ? nil : stop.lines,
            status: status,
            crowding: nil,
            signalementCount: stopDetail.activeIncidents.count,
            primaryLine: primaryLine,
            lastProblemType: stopDetail.activeIncidents.first?.type,
            lastConfidence: stopDetail.realtimeStatus,
            nextPassageMinutes: nextPassage,
            lastUpdatedAt: Date()
        )
    }

    private func removeFavori(_ item: FavoriteTransitItem) async {
        guard let userId = session.currentUser?.id, let stopId = item.stopBackendId else { return }
        // C4 — Optimistic remove avec snapshot avant pour revert rapide en
        // cas d'erreur. Avant : optimistic remove → en cas d'erreur on faisait
        // un loadFavoris() (full re-fetch). Maintenant on conserve l'item et
        // sa position pour le restaurer instantanément si l'API rate, sans
        // round-trip réseau supplémentaire. Si loadFavoris() ratait aussi,
        // l'item restait définitivement absent de l'UI alors qu'il existait
        // en backend.
        let snapshot = remoteItems
        remoteItems.removeAll { $0.stopBackendId == stopId }
        do {
            _ = try await UtilisateurService.toggleFavori(userId: userId, arretId: stopId)
            await session.refreshCurrentUser()
        } catch {
            // Restore l'état exact d'avant le tap pour rester en sync visuel
            // avec le backend qui n'a pas changé. Puis re-tente un sync
            // léger en background pour rattraper.
            remoteItems = snapshot
            Task { await loadFavoris() }
        }
    }

    private var favoritesEmptyState: some View {
        EmptyStateView(
            iconSystemName: "star.slash",
            title: "Pas encore de favoris",
            body: "Ajoute tes arrêts depuis la carte pour les retrouver ici.",
            cta: .init(label: "Ajouter un arrêt") { showAddSheet = true }
        )
        .padding(.horizontal, 20)
        .padding(.top, 40)
    }

    private var searchEmptyState: some View {
        EmptyStateView(
            iconSystemName: "magnifyingglass",
            title: "Aucun résultat",
            body: "Rien ne correspond à « \(query) ». Essaie un autre nom d'arrêt ou de ligne."
        )
        .padding(.top, 40)
    }

    private var pinnedStopsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FavoriteSectionHeading(text: "Arrêts épinglés", systemImage: "star.fill")

            VStack(spacing: 12) {
                ForEach(filteredItems) { item in
                    Button {
                        selectedItem = item
                    } label: {
                        favoriteStopCard(item)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func favoriteStopCard(_ item: FavoriteTransitItem) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text(item.title)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .tracking(-0.2)
                Text(item.code)
                    .font(.system(size: 10, weight: .regular, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Button {
                    Task { await removeFavori(item) }
                } label: {
                    Image(systemName: "star.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Color.primary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 8)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(height: 1)
                .padding(.horizontal, 16)

            VStack(spacing: 10) {
                HStack(alignment: .top, spacing: 10) {
                    HStack(spacing: 4) {
                        ForEach(item.detailLines.prefix(4)) { line in
                            LineBadge(line: line.code, size: .sm)
                        }
                    }
                    Spacer()
                    severityMeta(for: item)
                }

                HStack(spacing: 8) {
                    Text(item.cockpitHeadline)
                        .font(.system(size: 12.5, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Spacer()
                    Text(item.nextPassage)
                        .font(DS.Font.monoLarge.weight(.bold))
                        .foregroundStyle(DS.Color.ink)
                }

                HStack(spacing: 8) {
                    Text(item.activityLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Color.inkMute)
                    Spacer()
                    Text(item.lastUpdatedLabel)
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func severityMeta(for item: FavoriteTransitItem) -> some View {
        HStack(spacing: 6) {
            Circle()
                .fill(item.cockpitAccent)
                .frame(width: 8, height: 8)
            Text(item.problemLabel.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1)
                .foregroundStyle(DS.Color.inkMute)
        }
    }

    private var followedLinesSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                FavoriteSectionHeading(text: "Lignes suivies")
                Spacer()
                Text("\(followedLines.count) lignes")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
            }

            let columns = [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ]

            LazyVGrid(columns: columns, spacing: 8) {
                ForEach(followedLineDisplays) { line in
                    Button {
                        nav.pendingLineFocus = line.code
                        nav.currentPage = .reports
                    } label: {
                        FavoriteFollowedLineCard(line: line)
                    }
                    .buttonStyle(PressableScaleStyle())
                }
            }
        }
    }

    private var smartBriefsSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            FavoriteSectionHeading(text: "Alertes intelligentes")

            VStack(spacing: 8) {
                Button {
                    nav.currentPage = .profile
                } label: {
                    favoriteInfoRow(
                        icon: "bell.fill",
                        title: "Notifications favorites",
                        subtitle: (session.currentUser?.notifications ?? false) ? "Activées" : "Désactivées",
                        active: session.currentUser?.notifications ?? false
                    )
                }
                .buttonStyle(.plain)

                Button {
                    nav.currentPage = .profile
                } label: {
                    favoriteInfoRow(
                        icon: "newspaper.fill",
                        title: "Digest hebdomadaire",
                        subtitle: (session.currentUser?.weeklyDigestEnabled ?? false) ? "Chaque semaine" : "Non activé",
                        active: session.currentUser?.weeklyDigestEnabled ?? false
                    )
                }
                .buttonStyle(.plain)

                if let routine = session.currentUser?.routine {
                    Button {
                        nav.currentPage = .profile
                    } label: {
                        favoriteRoutineRow(routine)
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func favoriteInfoRow(icon: String, title: String, subtitle: String, active: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.ink)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(subtitle)
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer()
            FavoriteEditorialSwitch(isOn: active)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func favoriteRoutineRow(_ routine: CommuteRoutineDTO) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 4)
                    .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1)
                    .background(RoundedRectangle(cornerRadius: 4).fill(DS.Color.paper2))
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.ink)
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(routine.homeLabel)
                    Image(systemName: "arrow.right")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                    Text(routine.workLabel)
                }
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Color.ink)

                Text("Départ \(routine.departureTime) · trajet quotidien")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    @MainActor
    private func loadFollowedLineMetadata() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !followedLines.isEmpty else {
            stibLineMetadata = [:]
            return
        }

        do {
            async let catalogTask: [LigneCatalogDTO] = LigneService.toutesLesLignes()
            async let statesTask: [LigneEtatDTO] = LigneService.etatLignes()
            let (catalog, states) = try await (catalogTask, statesTask)
            stibLineMetadata = buildFollowedLineMetadata(catalog: catalog, states: states)
        } catch {
            ErrorReporting.capture(error, tag: "favorites.followedLines.metadata")
        }
    }

    private func buildFollowedLineMetadata(
        catalog: [LigneCatalogDTO],
        states: [LigneEtatDTO]
    ) -> [String: FavoriteFollowedLineMetadata] {
        var output: [String: FavoriteFollowedLineMetadata] = [:]

        for line in catalog {
            let code = baseLineId(line.lineid)
            let metadata = FavoriteFollowedLineMetadata(
                code: code,
                directionLabel: readableDirectionLabel(
                    primary: line.nomComplet,
                    secondary: line.nomCompletRetour,
                    destination: nil
                ),
                color: color(from: line.couleur, fallbackLine: code),
                textColor: TransitLinePalette.foreground(for: code)
            )

            output[line.lineid.uppercased()] = metadata
            if output[code.uppercased()] == nil {
                output[code.uppercased()] = metadata
            }
            if let direction = line.direction?.trimmingCharacters(in: .whitespacesAndNewlines), !direction.isEmpty {
                output["\(code):\(direction)".uppercased()] = metadata
            }
        }

        for state in states {
            let code = baseLineId(state.lineid)
            let existing = output[state.lineid.uppercased()] ?? output[code.uppercased()]
            let metadata = FavoriteFollowedLineMetadata(
                code: code,
                directionLabel: readableDirectionLabel(
                    primary: state.nom,
                    secondary: state.nomRetour,
                    destination: state.destination?.fr
                ) ?? existing?.directionLabel,
                color: color(from: state.couleur, fallbackLine: code),
                textColor: TransitLinePalette.foreground(for: code)
            )

            output[state.lineid.uppercased()] = metadata
            if output[code.uppercased()] == nil {
                output[code.uppercased()] = metadata
            }
            if let direction = state.direction?.trimmingCharacters(in: .whitespacesAndNewlines), !direction.isEmpty {
                output["\(code):\(direction)".uppercased()] = metadata
            }
        }

        return output
    }

    private func readableDirectionLabel(primary: String?, secondary: String?, destination: String?) -> String? {
        let values = [destination, primary, secondary]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .filter { value in
                let lowered = value.lowercased()
                return lowered != "city" && lowered != "suburb"
            }

        if let destination, let primary, !destination.isEmpty, !primary.isEmpty, destination != primary {
            return "\(primary) → \(destination)"
        }

        return values.first
    }

    private func color(from hex: String?, fallbackLine: String) -> Color {
        guard let hex = hex?.trimmingCharacters(in: .whitespacesAndNewlines), !hex.isEmpty else {
            return TransitLinePalette.fill(for: fallbackLine)
        }
        return Color(hex: hex)
    }

    private func parseFavoriteLine(_ rawLine: String) -> (operatorType: TransitOperator?, code: String) {
        let parts = rawLine.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2 else {
            return (nil, rawLine)
        }

        switch parts[0].uppercased() {
        case "DELIJN":
            return (.delijn, parts[1])
        case "TEC":
            return (.tec, parts[1])
        case "SNCB":
            return (.sncb, parts[1])
        default:
            return (nil, parts[0])
        }
    }

    private func baseLineId(_ rawLine: String) -> String {
        parseFavoriteLine(rawLine).code
    }

    private func sortLine(_ lhs: String, _ rhs: String) -> Bool {
        let left = baseLineId(lhs)
        let right = baseLineId(rhs)
        if let a = Int(left), let b = Int(right) {
            return a < b
        }
        return left.localizedStandardCompare(right) == .orderedAscending
    }

    private func mapFavoriteItems(from stops: [FavoriDetailDTO], fallbackStops: [FavoriDetailDTO]) -> [FavoriteTransitItem] {
        let source = stops.isEmpty ? fallbackStops : stops
        guard !source.isEmpty else { return [] }

        return source.enumerated().map { index, stop in
            let primaryLine = stop.primaryLine ?? stop.lignesDesservies?.first ?? "\(index + 1)"
            let modes = FavoriteTransportFilter.modes(for: stop.lignesDesservies ?? [])
            let severity = FavoriteSeverity.from(status: stop.status)
            let problemLabel: String = {
                switch severity {
                case .normal:
                    return "Aucun actif"
                case .warning, .blocked:
                    return stop.status ?? "À vérifier"
                }
            }()

            return FavoriteTransitItem(
                stopBackendId: stop.id,
                stopId: stop.id,
                code: primaryLine,
                codeColor: TransitLinePalette.fill(for: primaryLine),
                codeTextColor: TransitLinePalette.foreground(for: primaryLine),
                title: stop.nom,
                crowding: stop.crowding ?? "Faible",
                problemLabel: problemLabel,
                reportCount: stop.signalementCount ?? 0,
                nextPassage: stop.nextPassageMinutes.map { "\($0) min" } ?? "--",
                modes: modes,
                severity: severity,
                detailLines: (stop.lignesDesservies ?? [primaryLine]).prefix(4).map {
                    FavoriteLineChip(
                        code: $0,
                        color: TransitLinePalette.fill(for: $0),
                        textColor: TransitLinePalette.foreground(for: $0)
                    )
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

    @EnvironmentObject private var nav: AppNavigation
    @State private var transportStop: TransportStopDTO?
    @State private var isLoadingTransportStop = false
    @State private var hasLoadedStop = false
    @State private var stopLoadError: String? = nil

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

        return []
    }

    private var incidents: [FavoriteIncident] {
        guard let transportStop, !transportStop.activeIncidents.isEmpty else { return [] }
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
                confidenceText: incident.community.map(communitySummary(from:)) ?? confidenceLabel(for: incident.confidence),
                severity: incident.severity
            )
        }
    }

    private var hasRemoteDetail: Bool {
        transportStop != nil
    }

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 12)

                    summaryCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    planBCard
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    if let transportStop {
                        FavoriteStopDecisionCard(stop: transportStop)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    if let stopLoadError {
                        errorBanner(stopLoadError)
                            .padding(.horizontal, 20)
                            .padding(.top, 16)
                    }

                    detailSectionHeader("État en temps réel", icon: "dot.radiowaves.left.and.right")
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    if isLoadingTransportStop {
                        ProgressView()
                            .tint(DS.Color.inkMute)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 24)
                    } else if liveStatuses.isEmpty {
                        detailEmptyState("Aucune donnée disponible pour cet arrêt.")
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(liveStatuses) { status in
                                LiveStatusCard(status: status)
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    detailSectionHeader("Situation actuelle", icon: "exclamationmark.triangle.fill")
                        .padding(.horizontal, 20)
                        .padding(.top, 24)

                    if isLoadingTransportStop {
                        EmptyView()
                    } else if incidents.isEmpty {
                        detailEmptyState("Aucun incident signalé sur cet arrêt.")
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    } else {
                        VStack(spacing: 12) {
                            ForEach(incidents) { incident in
                                if let backendId = incident.backendId {
                                    FavoriteTransportIncidentCard(
                                        incident: incident,
                                        onConfirm: { await runCommunityAction(for: backendId, action: .confirm) },
                                        onStillBlocked: { await runCommunityAction(for: backendId, action: .stillBlocked) },
                                        onResolved: { await runCommunityAction(for: backendId, action: .resolved) }
                                    )
                                }
                            }
                        }
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                    }

                    Button {
                        onClose()
                        withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                            nav.currentPage = .reports
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "arrow.up.right")
                                .font(.system(size: 12, weight: .semibold))
                            Text("Voir tous les signalements")
                                .font(.system(size: 13, weight: .semibold))
                        }
                        .foregroundStyle(DS.Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DS.Color.ink, lineWidth: 1.5)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(PressableScaleStyle())
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                    .padding(.bottom, 32)
                }
            }
        }
        .modifier(PaperGrainBackground())
        .task(id: item.stopBackendId) {
            await loadTransportStop()
        }
        // Full-page detail → hide the bottom tab bar while it's on screen.
        .onAppear { nav.hidesTabBar = true }
        .onDisappear { nav.hidesTabBar = false }
    }

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 6) {
                Text("Arrêt favori")
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.3)
                    .foregroundStyle(DS.Color.inkMute)
                Text(item.title)
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                    )
            }
            .buttonStyle(.plain)
        }
    }

    private var summaryCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                HStack(spacing: 4) {
                    ForEach(item.detailLines) { line in
                        LineBadge(line: line.code, size: .sm)
                    }
                }
                Spacer()
                HStack(spacing: 6) {
                    Circle()
                        .fill(item.cockpitAccent)
                        .frame(width: 8, height: 8)
                    Text(item.problemLabel.uppercased())
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .tracking(1)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }

            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(height: 1)
                .padding(.vertical, 12)

            HStack(spacing: 12) {
                detailStat(label: "Prochain", value: item.nextPassage)
                Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(width: 1, height: 36)
                detailStat(label: "État", value: item.problemLabel)
                Rectangle().fill(DS.Color.ink.opacity(0.15)).frame(width: 1, height: 36)
                detailStat(label: "Signalements", value: "\(item.reportCount)")
            }

            Text(item.lastUpdatedLabel)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 12)
        }
        .padding(16)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var planBCard: some View {
        Button {
            onClose()
            withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                nav.currentPage = .home
            }
        } label: {
            HStack(spacing: 8) {
                Text("Besoin d’un plan B ?")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
            }
            .frame(height: 48)
            .padding(.horizontal, 16)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.Color.ink, lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressableScaleStyle())
    }

    private func loadTransportStop() async {
        guard AppConfig.isBackendEnabled else { hasLoadedStop = true; return }
        guard let stopBackendId = item.stopBackendId else { hasLoadedStop = true; return }
        guard !isLoadingTransportStop else { return }

        isLoadingTransportStop = true
        defer { isLoadingTransportStop = false; hasLoadedStop = true }

        do {
            transportStop = try await TransportService.stop(id: stopBackendId)
            stopLoadError = nil
        } catch {
            stopLoadError = "Impossible de charger les données en temps réel."
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

    private func detailStat(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label.uppercased())
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .tracking(1.1)
                .foregroundStyle(DS.Color.inkMute)
            Text(value)
                .font(.system(size: 13.5, weight: .bold))
                .foregroundStyle(DS.Color.ink)
        }
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12))
                .foregroundStyle(DS.Color.statusMajor)
            Text(message)
                .font(.system(size: 12))
                .foregroundStyle(DS.Color.ink)
            Spacer()
            Button("Réessayer") {
                stopLoadError = nil
                Task { await loadTransportStop() }
            }
            .font(.system(size: 12, weight: .semibold))
            .foregroundStyle(DS.Color.ink)
            .buttonStyle(.plain)
        }
        .padding(12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.statusMajor.opacity(0.35), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private func detailSectionHeader(_ title: String, icon: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(title.uppercased())
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(DS.Color.ink)
            }
            Rectangle()
                .fill(DS.Color.ink)
                .frame(height: 1.5)
        }
    }

    private func detailEmptyState(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5))
            .foregroundStyle(DS.Color.inkMute)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct FavoriteTransitCard: View {
    let item: FavoriteTransitItem
    let onRemove: () -> Void

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

                    Button(action: onRemove) {
                        Image(systemName: "heart.fill")
                            .font(.system(size: 20, weight: .regular))
                            .foregroundStyle(Color(hex: "#7CB2FF"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }

            HStack(spacing: 6) {
                Image(systemName: "chart.bar.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(.black)
                    .rotationEffect(.degrees(180))

                Text(item.activityLabel)
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
        status.score >= 80 ? DS.Color.statusOK : DS.Color.statusMinor
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                LineBadge(line: status.lineCode, size: .sm)

                VStack(alignment: .leading, spacing: 3) {
                    Text(status.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)

                    Text(status.subtitle)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 8)

                VStack(alignment: .trailing, spacing: 8) {
                    Text("Prochain passage")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.inkMute)
                        .tracking(1)

                    Text(status.nextPassage)
                        .font(.system(size: 18, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.ink)
                }
            }

            HStack {
                Label("Fiabilité du Service", systemImage: "chart.line.uptrend.xyaxis")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.ink)

                Spacer()

                VStack(alignment: .trailing, spacing: 1) {
                    Text("Score")
                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.inkMute)
                        .tracking(1)
                    Text("\(status.score)%")
                        .font(.system(size: 14, weight: .bold, design: .monospaced))
                        .foregroundStyle(scoreColor)
                }
            }
            .padding(.top, 26)

            ZStack(alignment: .leading) {
                Capsule()
                    .fill(DS.Color.paper2)
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
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(DS.Color.inkMute)
            .padding(.top, 4)
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(status.borderColor.opacity(0.7), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
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

            Text("Confirmez cette situation via l'onglet Signalements.")
                .font(.custom("Montserrat-Regular", size: 10))
                .foregroundStyle(.black.opacity(0.9))
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
                Text("Analyse réseau")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)

                Spacer()

                Text(TransportViewAdapters.localizedSeverityLabel(severity: stop.severity, fallback: stop.label?.fr))
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.ink)
                    .tracking(1)
                    .padding(.horizontal, 10)
                    .frame(height: 28)
                    .background(DS.Color.paper2)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }

            if let alternative = stop.recommendedAlternatives.first {
                Text(alternative.explanationDetails?.summary ?? alternative.explanation)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let firstHighlight = alternative.explanationDetails?.highlights.first {
                    Text(firstHighlight)
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.primary)
                }
            } else if let incident = stop.activeIncidents.first?.description {
                Text(incident)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
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
                LineBadge(line: incident.lineCode, size: .sm)

                VStack(alignment: .leading, spacing: 5) {
                    Text(incident.title)
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)

                    Text(incident.body)
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)

                    if let confidenceText = incident.confidenceText {
                        Text(confidenceText)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }

                Spacer(minLength: 8)

                // Severity-coloured warning icon (icon varies by problem type)
                // — replaces the flat coloured dot + tinted card so the card
                // follows the design system (neutral paper).
                Image(systemName: SignalVisuals.icon(forType: incident.title))
                    .font(.system(size: 13, weight: .black))
                    .foregroundStyle(severityColor)
                    .frame(width: 26, height: 26)
                    .background(Circle().fill(severityColor.opacity(0.14)))
            }

            HStack(spacing: 8) {
                communityButton("Je confirme", action: onConfirm)
                communityButton("Toujours bloqué", action: onStillBlocked)
                communityButton("Résolu", action: onResolved)
            }
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var severityColor: Color {
        switch incident.severity {
        case "critical": return DS.Color.statusCritical
        case "major":    return DS.Color.statusMajor
        case "minor":    return DS.Color.statusMinor
        default:         return DS.Color.statusOK
        }
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
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 10)
                .frame(height: 30)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.Color.ink.opacity(0.25), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(PressableScaleStyle())
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

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .metro: return "m.circle.fill"
        }
    }

    // STIB network as of 2024-2026.
    // Metro: 1, 2, 5, 6. Trams: see set below. Everything else numeric, or N-prefixed
    // night lines, is a bus.
    private static let metroLines: Set<String> = ["1", "2", "5", "6"]
    // STIB tram network 2024-2026. Source of truth: TransitLineMode.tramLines.
    // Cross-checked against line-shapes.json suffix (m/t/b).
    private static let tramLines: Set<String> = [
        "3", "4", "7", "8", "9", "10", "18", "19", "25", "35",
        "39", "44", "51", "55", "62", "81", "82", "92", "93", "97"
    ]

    static func mode(for line: String) -> FavoriteTransportFilter? {
        let normalized = line
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .uppercased()
            .replacingOccurrences(of: "LIGNE", with: "")
            .replacingOccurrences(of: "TRAM", with: "")
            .replacingOccurrences(of: "BUS", with: "")
            .replacingOccurrences(of: "METRO", with: "")
            .replacingOccurrences(of: "MÉTRO", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { return nil }
        if metroLines.contains(normalized) { return .metro }
        if tramLines.contains(normalized) { return .tram }
        if normalized.hasPrefix("N") { return .bus } // Noctis night buses
        if Int(normalized) != nil { return .bus }
        return nil
    }

    static func modes(for lines: [String]) -> Set<FavoriteTransportFilter> {
        Set(lines.compactMap(mode(for:)))
    }

    static func from(lines: [String]) -> FavoriteTransportFilter {
        modes(for: lines).sorted(by: { $0.priority < $1.priority }).first ?? .bus
    }

    fileprivate var priority: Int {
        switch self {
        case .metro: return 0
        case .tram: return 1
        case .bus: return 2
        case .all: return 3
        }
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
    let modes: Set<FavoriteTransportFilter>
    let severity: FavoriteSeverity
    let detailLines: [FavoriteLineChip]
    var lastUpdatedAt: Date? = nil
    var lastProblemType: String? = nil
    var lastConfidence: String? = nil

    /// Honest, real-data label: how many community reports are active on the
    /// stop. Replaces the old "Affluence/Drukte" line, which was just this
    /// count relabelled as crowding (a metric STIB doesn't actually publish).
    var activityLabel: String {
        reportCount == 0 ? "Aucun signalement actif" : "\(reportCount) signalement\(reportCount > 1 ? "s" : "") actif\(reportCount > 1 ? "s" : "")"
    }

    var cockpitHeadline: String {
        switch severity {
        case .normal:
            return reportCount == 0 ? "Aucun incident actif" : "1 signalement actif"
        case .warning:
            if let type = lastProblemType {
                return "\(type) en cours"
            }
            return "\(reportCount) signalements actifs"
        case .blocked:
            if let type = lastProblemType {
                return "\(type) · service perturbé"
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

private struct FavoriteFollowedLineMetadata {
    let code: String
    let directionLabel: String?
    let color: Color
    let textColor: Color
}

private struct FavoriteFollowedLineDisplay: Identifiable {
    var id: String { rawLine }
    let rawLine: String
    let code: String
    let subtitle: String?
    let color: Color
    let textColor: Color
    let isDisrupted: Bool
}

private struct FavoriteFollowedLineCard: View {
    let line: FavoriteFollowedLineDisplay

    var body: some View {
        HStack(spacing: 8) {
            LineBadge(line: line.code, size: .sm, fill: line.color, foreground: line.textColor)
            if let subtitle = line.subtitle, !subtitle.isEmpty {
                Text(subtitle)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
            }
            Spacer(minLength: 4)
            StatusDot(level: line.isDisrupted ? .major : .ok, size: 8)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var accessibilityLabel: String {
        if let subtitle = line.subtitle, !subtitle.isEmpty {
            return "Ligne \(line.code), \(subtitle)"
        }
        return "Ligne \(line.code)"
    }
}

private struct FavoriteSectionHeading: View {
    let text: String
    var systemImage: String? = nil

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }
            Text(text.uppercased())
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(1.4)
                .foregroundStyle(DS.Color.ink)
        }
    }
}

private struct FavoriteEditorialSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? DS.Color.ink : DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .frame(width: 40, height: 24)
            Circle()
                .fill(isOn ? DS.Color.paper : DS.Color.ink)
                .frame(width: 18, height: 18)
                .padding(.horizontal, 2)
        }
        .animation(.spring(response: 0.25, dampingFraction: 0.85), value: isOn)
    }
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
    let severity: String?
}

private struct AddFavoriteSheet: View {
    @EnvironmentObject private var session: AuthSession
    @StateObject private var locator = OneShotLocationManager()

    @State private var nearbyStops: [NearbyStop] = []
    @State private var isLoading = false
    @State private var addingId: String? = nil
    @State private var addedIds: Set<String> = []
    @State private var errorMessage: String? = nil
    @State private var searchQuery = ""

    let existingIds: Set<String>
    let onClose: () -> Void

    private var pendingIds: Set<String> { existingIds.union(addedIds) }
    private var filteredNearbyStops: [NearbyStop] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return nearbyStops }

        return nearbyStops.filter { stop in
            stop.name.localizedCaseInsensitiveContains(query)
            || stop.lines.contains { $0.number.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    HStack(alignment: .top, spacing: 12) {
                        // large=false uses displayH2 (22pt) instead of
                        // displayH1 (32pt) so "Ajouter un arrêt favori" no
                        // longer wraps to "Ajouter un / arrêt favori" with
                        // the orphan "un" on its own line.
                        PageHeader(title: "Ajouter un arrêt favori", eyebrow: "Réseau personnel", large: false)

                        Spacer(minLength: 12)

                        Button(action: onClose) {
                            Image(systemName: "xmark")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(DS.Color.ink)
                                .frame(width: 36, height: 36)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5)
                                )
                        }
                        .buttonStyle(PressableScaleStyle())
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 28) // keep the eyebrow clear of the sheet's safe area edge

                    VStack(alignment: .leading, spacing: 14) {
                        Text("Ajoute un arrêt proche pour suivre ses passages et recevoir des alertes ciblées.")
                            .font(.system(size: 13.5))
                            .foregroundStyle(DS.Color.inkSoft)

                        FavoritePickerSearchField(
                            placeholder: "Chercher un arrêt ou une ligne",
                            text: $searchQuery
                        )

                        if let errorMessage {
                            Text(errorMessage)
                                .font(.system(size: 12.5, weight: .semibold))
                                .foregroundStyle(DS.Color.statusMajor)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 12)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(DS.Color.paper)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 6)
                                        .stroke(DS.Color.statusMajor.opacity(0.35), lineWidth: 1.5)
                                )
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                        }

                        if isLoading {
                            ProgressView()
                                .tint(DS.Color.inkMute)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 48)
                        } else if nearbyStops.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mappin.slash")
                                    .font(.system(size: 34, weight: .light))
                                    .foregroundStyle(DS.Color.inkMute)
                                Text("Aucun arrêt trouvé à proximité")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Text("Active la localisation ou rapproche-toi d’un arrêt STIB.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 56)
                        } else if filteredNearbyStops.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "magnifyingglass")
                                    .font(.system(size: 30, weight: .light))
                                    .foregroundStyle(DS.Color.inkMute)
                                Text("Aucun arrêt trouvé")
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Text("Essaie le nom d’un arrêt ou un numéro de ligne.")
                                    .font(.system(size: 12))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 44)
                        } else {
                            VStack(spacing: 10) {
                                ForEach(filteredNearbyStops) { stop in
                                    addFavoriteRow(stop)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 32)
                }
            }
        }
        .modifier(PaperGrainBackground())
        .task { await load() }
    }

    private func addFavoriteRow(_ stop: NearbyStop) -> some View {
        let isFav = stop.backendId.map { pendingIds.contains($0) } ?? false
        let isAdding = stop.backendId == addingId

        return HStack(spacing: 14) {
            VStack(alignment: .leading, spacing: 6) {
                Text(stop.name)
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)

                if !stop.lines.isEmpty {
                    HStack(spacing: 6) {
                        ForEach(stop.lines.prefix(4)) { line in
                            LineBadge(line: line.number, size: .sm)
                        }
                    }
                }

                Text("\(stop.distanceMeters) m")
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }

            Spacer()

            Button {
                guard stop.backendId != nil, !isFav else { return }
                Task { await addFavori(stop) }
            } label: {
                Group {
                    if isAdding {
                        ProgressView()
                            .tint(DS.Color.ink)
                            .frame(width: 88, height: 36)
                    } else if isFav {
                        HStack(spacing: 6) {
                            Image(systemName: "checkmark")
                            Text("Ajouté")
                        }
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 88, height: 36)
                    } else {
                        Text("+ Ajouter")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 88, height: 36)
                    }
                }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(DS.Color.ink.opacity(0.22), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(PressableScaleStyle())
            .disabled(isFav || isAdding)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func load() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let loc = await locator.getCurrentLocation()
        do {
            let all = try await NearbyStopService.fetchNearby(lat: loc.latitude, lng: loc.longitude, radius: 1500)
            nearbyStops = all
        } catch {
            print("AddFavoriteSheet load failed: \(error.localizedDescription)")
        }
    }

    private func addFavori(_ stop: NearbyStop) async {
        guard let userId = session.currentUser?.id, let stopId = stop.backendId else { return }
        addingId = stopId
        errorMessage = nil
        defer { addingId = nil }
        do {
            let response = try await UtilisateurService.toggleFavori(userId: userId, arretId: stopId)
            addedIds.insert(stopId)
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
            }
        } catch {
            print("Add favori failed: \(error.localizedDescription)")
            errorMessage = error.localizedDescription
        }
    }
}

private enum FavoritesMockData {
    static let items: [FavoriteTransitItem] = [
        .init(stopBackendId: nil, stopId: nil, code: "46", codeColor: Color(hex: "#E43C2E"), codeTextColor: .white, title: "De Wand", crowding: "Haute", problemLabel: "Perturbé", reportCount: 12, nextPassage: "15 min", modes: [.bus, .tram], severity: .warning, detailLines: [.init(code: "46", color: Color(hex: "#F29DC3"), textColor: .black), .init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "10", color: Color(hex: "#8F4199"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "62", codeColor: Color(hex: "#F29DC3"), codeTextColor: .black, title: "Leopold III", crowding: "Faible", problemLabel: "Normal", reportCount: 1, nextPassage: "5 min", modes: [.tram, .bus], severity: .normal, detailLines: [.init(code: "46", color: Color(hex: "#F29DC3"), textColor: .black), .init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "10", color: Color(hex: "#8F4199"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "38", codeColor: Color(hex: "#A67CB0"), codeTextColor: .white, title: "Suzan Daniel", crowding: "Moyenne", problemLabel: "Bloqué", reportCount: 16, nextPassage: "/", modes: [.bus, .tram], severity: .blocked, detailLines: [.init(code: "38", color: Color(hex: "#A67CB0"), textColor: .white), .init(code: "51", color: Color(hex: "#91BEE5"), textColor: .black)]),
        .init(stopBackendId: nil, stopId: nil, code: "48", codeColor: Color(hex: "#ED7807"), codeTextColor: .white, title: "Heembeek", crowding: "Faible", problemLabel: "Normal", reportCount: 1, nextPassage: "5 min", modes: [.bus], severity: .normal, detailLines: [.init(code: "48", color: Color(hex: "#ED7807"), textColor: .white), .init(code: "56", color: Color(hex: "#0066A3"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "1", codeColor: Color(hex: "#8F4199"), codeTextColor: .white, title: "Gare de l’ouest", crowding: "Moyenne", problemLabel: "Perturbé", reportCount: 3, nextPassage: "2 min", modes: [.metro], severity: .warning, detailLines: [.init(code: "1", color: Color(hex: "#8F4199"), textColor: .white), .init(code: "5", color: Color(hex: "#F9A611"), textColor: .white)]),
        .init(stopBackendId: nil, stopId: nil, code: "7", codeColor: Color(hex: "#EFE048"), codeTextColor: .black, title: "Vanderkindere", crowding: "Haute", problemLabel: "Bloqué", reportCount: 9, nextPassage: "8 min", modes: [.tram], severity: .blocked, detailLines: [.init(code: "7", color: Color(hex: "#EFE048"), textColor: .black), .init(code: "92", color: Color(hex: "#4C8B33"), textColor: .white)])
    ]
}
