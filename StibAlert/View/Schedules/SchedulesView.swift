import CoreLocation
import SwiftUI

/// "Horaires" tab — IDF Mobilités-style lines directory. Search bar on top,
/// then every STIB line grouped by mode (Métro / Tram / Bus) in a grid of
/// colored line badges. Tap a badge to push the line's detail page.
struct SchedulesView: View {
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var nav: AppNavigation

    @State private var allLines: [LigneCatalogDTO] = []
    @State private var isLoading = false
    @State private var loadError: String? = nil
    @State private var searchQuery: String = ""
    @State private var selectedOperator: TransitOperator = .stib
    @State private var selectedGare: SNCBStation?
    @StateObject private var locationManager = HomeLocationManager()

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                header
                TransitOperatorRow(
                    activeOperator: selectedOperator,
                    enabledOperators: [.stib, .sncb, .delijn, .tec],
                    onSelect: { selectedOperator = $0 }
                )
                    .padding(.horizontal, 18)
                    .padding(.top, 12)
                searchBar
                    .padding(.top, 14)

                content
                    .padding(.top, 14)
            }
            .padding(.bottom, 110) // tab bar clearance
            .background(DS.Color.paper.ignoresSafeArea())
            .task {
                locationManager.start()
                if allLines.isEmpty { await loadLines() }
            }
            .onChange(of: selectedOperator) { _, _ in
                searchQuery = ""
            }
            // U1 — `.preferredColorScheme(.light)` retiré : DS.Color.* a
            // déjà des variantes dark via le paramètre `dark:` dans
            // StibAlertDesignSystem.swift. Forcer light cassait l'expérience
            // dark mode iOS (transitions jarrantes entre tabs).
        }
    }

    // MARK: - Header

    private var header: some View {
        // Compact centered title — kept consistent with Infos trafic /
        // Favoris so the navigation feels coherent. Dropped the eyebrow
        // + Dela Gothic display font to free up vertical space for the
        // mode-grouped lines grid below.
        Text("Horaires")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(DS.Color.ink)
            .padding(.top, 16)
            .frame(maxWidth: .infinity)
    }

    // MARK: - Search bar

    private var searchBar: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
            TextField(selectedOperator == .sncb ? "Chercher une gare" : "Chercher une ligne", text: $searchQuery)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(DS.Color.paper2.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .padding(.horizontal, 18)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        if selectedOperator == .sncb {
            sncbContent
        } else if selectedOperator == .delijn || selectedOperator == .tec {
            OperatorLineDirectory(op: selectedOperator, searchQuery: $searchQuery)
        } else if isLoading && allLines.isEmpty {
            VStack(spacing: 14) {
                Spacer().frame(height: 60)
                ProgressView().tint(DS.Color.ink)
                Text("Chargement des lignes…")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if let loadError, allLines.isEmpty {
            // N9 — Full blank state seulement si on n'avait JAMAIS chargé les
            // lignes. Si on en avait en cache, on garde l'affichage et on met
            // un banner soft (cf. cacheFallbackBanner ci-dessous).
            VStack(spacing: 12) {
                Spacer().frame(height: 60)
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 24, weight: .semibold))
                    .foregroundStyle(DS.Color.statusMinor)
                Text("Impossible de charger les lignes")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text(loadError)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
                Button("Réessayer") { Task { await loadLines() } }
                    .buttonStyle(.borderedProminent)
                Spacer()
            }
            .padding(.horizontal, 24)
        } else if groupedLines.isEmpty {
            VStack(spacing: 12) {
                Spacer().frame(height: 60)
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 22))
                    .foregroundStyle(DS.Color.inkMute)
                Text("Aucune ligne trouvée")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text("Réinitialise la recherche pour voir toutes les lignes \(selectedOperator.shortName).")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.easeOut(duration: 0.18)) { searchQuery = "" }
                } label: {
                    HStack(spacing: 8) {
                        Image(systemName: "list.bullet")
                            .font(.system(size: 13, weight: .bold))
                        Text("Voir toutes les lignes")
                            .font(DS.Font.bodyBold)
                    }
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 16)
                    .frame(height: 44)
                    .background(DS.Color.primary)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
                Spacer()
            }
        } else {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: DS.Spacing.lg) {
                    // N9 — Banner soft quand on a échoué à rafraîchir mais
                    // qu'on garde un cache utilisable. Pas de full blank state.
                    if loadError != nil {
                        cacheFallbackBanner
                    }
                    ForEach(Array(groupedLines.enumerated()), id: \.offset) { _, group in
                        section(for: group.mode, lines: group.lines)
                    }
                }
                .padding(.horizontal, 18)
                .padding(.top, 4)
                .padding(.bottom, 18)
            }
            .navigationDestination(for: String.self) { lineId in
                LigneDetailPage(lineId: lineId)
            }
        }
    }

    private var cacheFallbackBanner: some View {
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            Task { await loadLines() }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.statusMinor)
                VStack(alignment: .leading, spacing: 1) {
                    Text("Connexion limitée")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text("Données en cache · Tape pour réessayer")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMute)
                }
                Spacer(minLength: 0)
                if isLoading {
                    ProgressView().tint(DS.Color.inkMute).scaleEffect(0.7)
                } else {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 9)
            .background(DS.Color.statusMinor.opacity(0.10))
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(DS.Color.statusMinor.opacity(0.35), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var sncbContent: some View {
        ScrollView(showsIndicators: false) {
            SncbGareDirectory(
                searchQuery: $searchQuery,
                showsSearchField: false,
                userCoordinate: locationManager.userCoordinate,
                onSelect: { selectedGare = $0 }
            )
            .padding(.horizontal, 18)
            .padding(.top, 4)
            .padding(.bottom, 18)
        }
        // Tap a gare → push its full detail page opened on the Horaires tab.
        .navigationDestination(item: $selectedGare) { gare in
            GareDetailPage(station: gare, initialTab: .schedule, onReport: { _ in
                nav.showReportSheet = true
            })
        }
    }

    private func unavailableOperatorContent(_ transitOperator: TransitOperator) -> some View {
        VStack(spacing: 10) {
            Spacer().frame(height: 70)
            Image(transitOperator.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 42, height: 42)
            Text("\(transitOperator.shortName) arrive bientôt")
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
            Text("La base locale n’est pas encore branchée pour cet opérateur.")
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 24)
    }

    private func section(for mode: TransitLineMode, lines: [DisplayLine]) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Image(systemName: mode.sfSymbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 30, height: 30)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                Text(mode.label.uppercased())
                    .font(DS.Font.eyebrow)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
            }

            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 5),
                spacing: 10
            ) {
                ForEach(lines) { line in
                    NavigationLink(value: line.lookupId) {
                        // squareSide : tous les badges en carré identique 50×50,
                        // comme la grille Infos trafic (LineStatusGrid). Avant,
                        // LineBadge gardait sa largeur variable selon le nombre
                        // de chiffres et minWidth ne corrigeait que le plancher.
                        LineBadge(line: line.shortCode, size: .lg, squareSide: 50)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(12)
            .background(DS.Color.paper.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
    }

    // MARK: - Grouping & filtering

    /// Lightweight value type wrapping a normalised line code (e.g. "81")
    /// together with one of the backend ids we can use to load the detail
    /// page (e.g. "81:City"). Required because the STIB catalog ships every
    /// physical line twice — once per direction — under composite ids like
    /// "T7:Suburb" / "T7:City". We dedupe by the shortCode for display, but
    /// keep one lookupId so the LigneDetailPage still has a valid handle.
    fileprivate struct DisplayLine: Identifiable {
        let id: String          // unique shortCode key
        let shortCode: String   // "1", "7", "81" — what LineBadge expects
        let lookupId: String    // backend id for the detail fetch
    }

    private var groupedLines: [(mode: TransitLineMode, lines: [DisplayLine])] {
        let trimmed = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()

        // 1. Filter by search query (matches against raw lineid + nom + direction)
        let filtered: [LigneCatalogDTO]
        if trimmed.isEmpty {
            filtered = allLines
        } else {
            filtered = allLines.filter { line in
                let haystack = "\(line.lineid) \(line.nomComplet ?? "") \(line.direction ?? "")"
                    .folding(options: .diacriticInsensitive, locale: .current)
                    .lowercased()
                return haystack.contains(trimmed)
            }
        }

        // 2. Reduce to a unique DisplayLine per shortCode (first win).
        var byShortCode: [String: DisplayLine] = [:]
        for line in filtered {
            let short = Self.shortCode(from: line.lineid)
            guard !short.isEmpty else { continue }
            if byShortCode[short] != nil { continue }
            byShortCode[short] = DisplayLine(id: short, shortCode: short, lookupId: line.lineid)
        }
        let unique = Array(byShortCode.values)

        // 3. Group by transit mode and sort numerically inside each group.
        let groups = Dictionary(grouping: unique) { TransitLineMode.mode(for: $0.shortCode) }
        let orderedModes: [TransitLineMode] = [.metro, .tram, .bus]
        return orderedModes.compactMap { mode -> (mode: TransitLineMode, lines: [DisplayLine])? in
            guard let lines = groups[mode], !lines.isEmpty else { return nil }
            let sorted = lines.sorted { numericRank($0.shortCode) < numericRank($1.shortCode) }
            return (mode, sorted)
        }
    }

    /// Strip the ":City" / ":Suburb" direction suffix and any leading T/B/M
    /// prefix so "T7:City" → "7", "81:Suburb" → "81", "M1:City" → "1".
    /// Returns the canonical short code used by `TransitLinePalette` and
    /// `LineBadge` to colorise + label the badge.
    static func shortCode(from rawLineId: String) -> String {
        var token = rawLineId
        if let colonRange = token.range(of: ":") {
            token = String(token[..<colonRange.lowerBound])
        }
        token = token.trimmingCharacters(in: .whitespaces).uppercased()
        // Strip a single T/B/M prefix if followed by digits.
        if let first = token.first, "TBM".contains(first), token.dropFirst().allSatisfy(\.isNumber) {
            token = String(token.dropFirst())
        }
        return token
    }

    private func numericRank(_ shortCode: String) -> Int {
        Int(shortCode) ?? Int.max
    }

    // MARK: - Loading

    @MainActor
    private func loadLines() async {
        guard AppConfig.isBackendEnabled else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }
        do {
            let lines = try await LigneService.toutesLesLignes()
            allLines = lines
        } catch {
            loadError = error.localizedDescription
        }
    }
}
