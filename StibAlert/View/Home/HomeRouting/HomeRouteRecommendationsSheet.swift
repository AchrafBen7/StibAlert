import CoreLocation
import SwiftUI

struct RouteRecommendationsSheet: View {
    let options: [HomeRouteOption]
    let modeSummaries: [RouteModeSummary]
    /// Lignes évitées par le calcul à cause de signalements/perturbations
    /// fiables. Non vide → on affiche la bannière "itinéraire recalculé" qui
    /// rend la boucle Waze PERÇUE (ce n'est pas qu'un re-route silencieux).
    var blockedLines: [String] = []
    @Binding var selectedRouteID: UUID?
    @Binding var isExpanded: Bool
    @Binding var preferredOperator: String?
    @Binding var departureTime: Date?
    @Binding var transitModes: Set<RouteTransitMode>
    /// Vrai pendant le recalcul déclenché par un changement de filtre : la
    /// liste passe en état de chargement au lieu de garder un résultat
    /// obsolète à l'écran.
    var isRouting: Bool = false
    var onFiltersChange: () -> Void = {}
    /// Le serveur n'a pas répondu — distinct de « ce trajet n'a pas de transport ».
    var backendUnreachable: Bool = false
    let onSelect: (HomeRouteOption) -> Void
    let onClose: () -> Void

    // Translation de drag en @State (et non @GestureState) : @GestureState se
    // remet à 0 INSTANTANÉMENT au relâchement → la feuille « sautait » avant que
    // la hauteur ne s'anime. Ici on anime le retour à 0 dans le même ressort que
    // le changement de hauteur.
    @State private var dragTranslation: CGFloat = 0
    @State private var expandedRouteID: UUID?
    @State private var selectedModeKey: String = "transit"
    @State private var detent: SheetDetent = .medium
    /// Hauteur disponible, mémorisée pour que le geste puisse calculer ses crans
    /// (le `GeometryReader` n'est pas accessible depuis `onEnded`).
    @State private var availableHeight: CGFloat = 0

    /// Les 3 crans du sheet. Tirer sous le plus petit = fermer.
    enum SheetDetent: CaseIterable {
        case small, medium, large

        func height(in available: CGFloat) -> CGFloat {
            switch self {
            case .small:  return min(available * 0.26, 220)
            case .medium: return min(available * 0.52, 440)
            case .large:  return min(available * 0.88, 760)
            }
        }
    }

    /// Geste à 3 crans, fluide.
    ///
    /// L'ancien geste ne suivait le doigt QUE vers le bas : monter ne produisait
    /// aucun mouvement, la feuille sautait d'un coup au relâchement. D'où la
    /// sensation de blocage. Ici la hauteur suit le doigt dans LES DEUX SENS,
    /// puis se cale sur le cran le plus proche de la position PROJETÉE (élan du
    /// geste inclus) — donc un petit coup sec envoie au cran suivant, un
    /// glissement lent s'arrête au plus proche.
    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 4)
            .onChanged { value in
                let raw = value.translation.height
                // Résistance au-delà du plus grand cran : on peut tirer un peu
                // plus haut, mais ça freine (comme un sheet iOS natif).
                if raw < 0, currentHeight >= SheetDetent.large.height(in: availableHeight) {
                    dragTranslation = raw * 0.25
                } else {
                    dragTranslation = raw
                }
            }
            .onEnded { value in
                let available = availableHeight
                let projected = detent.height(in: available) - value.predictedEndTranslation.height
                let smallest = SheetDetent.small.height(in: available)

                // Tiré nettement sous le plus petit cran → on ferme.
                if projected < smallest * 0.55 {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
                        dragTranslation = 0
                    }
                    onClose()
                    return
                }

                let target = SheetDetent.allCases.min {
                    abs($0.height(in: available) - projected) < abs($1.height(in: available) - projected)
                } ?? .medium

                withAnimation(.interpolatingSpring(stiffness: 260, damping: 27)) {
                    detent = target
                    dragTranslation = 0
                    isExpanded = (target == .large)
                }
            }
    }

    /// Hauteur réellement affichée = cran courant, décalé par le doigt.
    private var currentHeight: CGFloat {
        let base = detent.height(in: availableHeight)
        let maxH = SheetDetent.large.height(in: availableHeight) + 60
        return min(max(base - dragTranslation, 80), maxH)
    }

    /// Trié par HEURE D'ARRIVÉE, pas par durée.
    ///
    /// Ce qui compte pour un voyageur qui part maintenant, c'est « j'arrive
    /// quand ? », pas « combien de temps dure le trajet ». Le tri par durée
    /// produisait des classements absurdes, observés en conditions réelles :
    ///   • option A — 20:26 → 20:45 (31 min), affichée « la plus rapide »
    ///   • option B — 20:14 → 20:34 (32 min), affichée « +1 min »
    /// B arrive ONZE minutes plus tôt et part plus tôt : elle est strictement
    /// meilleure, mais une minute de durée en plus la reléguait au second rang.
    /// Le backend classe déjà par heure d'arrivée (routeScoringService) ; ce tri
    /// local écrasait son travail.
    ///
    /// Repli sur la durée quand aucune heure d'arrivée n'est connue (marche /
    /// vélo, ou trajet sans données horaires).
    private var filteredOptions: [HomeRouteOption] {
        let subset = options.filter { $0.primaryModeKey == selectedModeKey }
        let base = subset.isEmpty ? options : subset
        return base.sorted { lhs, rhs in
            switch (lhs.effectiveArrivalDate, rhs.effectiveArrivalDate) {
            case let (l?, r?):
                if l != r { return l < r }
                return lhs.totalDurationMinutes < rhs.totalDurationMinutes
            case (nil, _?): return false   // sans horaire → après ceux qui en ont
            case (_?, nil): return true
            default: return lhs.totalDurationMinutes < rhs.totalDurationMinutes
            }
        }
    }

    /// Vrai quand l'utilisateur regarde le mode Transport mais qu'AUCUNE option
    /// transit n'existe (provider transit en échec, ou trajet trop court).
    /// `filteredOptions` retombe alors en silence sur marche/vélo : sans cette
    /// bannière l'utilisateur croyait que ces options étaient « le transport »
    /// — c'est le 🔴 « échec d'API silencieux ». On l'avertit explicitement.
    private var showTransitUnavailableNotice: Bool {
        // `!options.isEmpty` évite que cette bannière ("transport en commun
        // indisponible, voici marche/vélo") se superpose à l'état "aucun
        // itinéraire avec ces filtres" quand la liste est VRAIMENT vide
        // (options.isEmpty) : ce sont deux causes différentes, une seule
        // doit s'afficher à la fois.
        //
        // Et surtout : elle ne doit PAS s'afficher quand le serveur n'a pas
        // répondu. « Aucun transport en commun sur ce trajet » est un VERDICT
        // sur le réseau ; une panne réseau n'autorise aucun verdict. Dans ce
        // cas c'est `backendUnreachableBanner` qui parle, et lui propose de
        // réessayer.
        !backendUnreachable
            && !options.isEmpty
            && selectedModeKey == "transit"
            && !options.contains { $0.primaryModeKey == "transit" }
    }
    /// La carte « recommandée » (grande, en haut) suit la route SÉLECTIONNÉE :
    /// taper une autre route la fait monter en tête (« sélectionner à la place »)
    /// au lieu de rester enterrée dans la liste. Par défaut (rien de sélectionné)
    /// c'est la plus rapide.
    private var recommended: HomeRouteOption? {
        if let selectedRouteID, let selected = filteredOptions.first(where: { $0.id == selectedRouteID }) {
            return selected
        }
        return filteredOptions.first
    }
    private var others: [HomeRouteOption] {
        guard let recommendedID = recommended?.id else { return [] }
        return filteredOptions.filter { $0.id != recommendedID }
    }

    /// Route recommandée pour un mode donné, calculée sans dépendre de la
    /// propagation de `selectedModeKey` (utilisé dans onAppear/onChange où le
    /// @State n'est pas encore reflété). Même règle que `filteredOptions`.
    private func recommendedOption(for mode: String) -> HomeRouteOption? {
        let subset = options.filter { $0.primaryModeKey == mode }
        let base = subset.isEmpty ? options : subset
        return base.min { $0.totalDurationMinutes < $1.totalDurationMinutes }
    }
    private var preferredInitialMode: String {
        if modeSummaries.contains(where: { $0.modeKey == "transit" && $0.durationText != "—" }) {
            return "transit"
        }
        return modeSummaries.first(where: { $0.durationText != "—" })?.modeKey ?? "transit"
    }

    var body: some View {
        GeometryReader { proxy in
            let sheetHeight = currentHeight

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    // EN-TÊTE FIXE ET SAISISSABLE : poignée + bande de modes.
                    // La poignée seule offrait une cible minuscule ; on peut
                    // désormais attraper le sheet sur toute cette zone. La bande
                    // reste visible pendant qu'on fait défiler la liste (les
                    // onglets de mode sont une navigation, pas du contenu).
                    VStack(alignment: .leading, spacing: 0) {
                        sheetHandle
                        modeSummaryStrip
                    }
                    .contentShape(Rectangle())
                    .gesture(sheetDragGesture)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            routeFiltersBar
                            if isRouting {
                                routeLoadingState
                            } else {
                                backendUnreachableBanner
                                transitUnavailableBanner
                                // `rerouteBanner` retiré de la recherche d'itinéraire
                                // (décision produit) : l'utilisateur veut son trajet,
                                // pas un encart sur ce qui est évité. La vue reste
                                // définie plus bas si on veut la remettre ailleurs.
                                recommendedSection
                                optionsHeader
                                otherOptionsList
                            }
                        }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: sheetHeight, alignment: .top)
                .background(DS.Color.paper)
                .overlay(alignment: .topTrailing) {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 14, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute)
                            .frame(width: 32, height: 32)
                            .background(DS.Color.paper)
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                            )
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 14)
                    .padding(.trailing, 14)
                    .opacity(isExpanded ? 1 : 0)
                }
                .overlay(alignment: .top) {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.1))
                        .frame(height: 1)
                }
                .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 22, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                )
                // ⚠️ PAS d'`.offset(y: dragTranslation)` ici : la hauteur
                // (`currentHeight`) absorbe DÉJÀ le geste. Le sheet est ancré en
                // bas, donc réduire sa hauteur fait descendre son bord haut —
                // c'est le même effet visuel. Cumuler les deux le faisait bouger
                // deux fois plus vite et glisser hors de l'écran.
                .allowsHitTesting(true)
            }
            .ignoresSafeArea()
            .onChange(of: proxy.size.height) { _, newValue in
                availableHeight = newValue
            }
            .onAppear {
                availableHeight = proxy.size.height
                let mode = preferredInitialMode
                selectedModeKey = mode
                let rec = recommendedOption(for: mode)
                expandedRouteID = rec?.id
                // Aligne la CARTE sur la route recommandée (1ʳᵉ carte, la plus
                // rapide du mode). Sans ça, la carte traçait `routeOptions.first`
                // (1er trajet brut, non trié) → un itinéraire différent de la
                // proposition affichée → confusion. On ne force que si rien
                // n'est déjà sélectionné (respecte un choix manuel).
                if selectedRouteID == nil {
                    selectedRouteID = rec?.id
                }
            }
            .onChange(of: modeSummaries.map(\.modeKey)) { _, _ in
                let mode = preferredInitialMode
                selectedModeKey = mode
                let rec = recommendedOption(for: mode)
                expandedRouteID = rec?.id
                // Nouveau jeu de routes → on réaligne la carte sur la nouvelle
                // recommandation pour qu'elles ne divergent jamais.
                selectedRouteID = rec?.id
            }
        }
    }

    private var sheetHandle: some View {
        Capsule()
            .fill(DS.Color.ink.opacity(0.24))
            .frame(width: 76, height: 4)
            .frame(maxWidth: .infinity)
            .padding(.top, 10)
            .padding(.bottom, 14)
    }

    /// Rangée de filtres (Départ / Transports / Opérateur), sous les onglets
    /// de mode. Remplace l'ancienne bande "opérateur seul" (#4) : même règle
    /// de visibilité — filtrer par opérateur, heure ou mode n'a pas de sens
    /// sur une option 100% marche/vélo, donc masquée sans alternative transit.
    @ViewBuilder private var routeFiltersBar: some View {
        if modeSummaries.contains(where: { $0.modeKey == "transit" && $0.durationText != "—" }) {
            RouteFiltersBar(
                departureTime: $departureTime,
                transitModes: $transitModes,
                preferredOperator: $preferredOperator,
                onChange: onFiltersChange
            )
            .padding(.top, 8)
        }
    }

    private var hasActiveFilters: Bool {
        preferredOperator != nil || departureTime != nil || !transitModes.isEmpty
    }

    private func resetFilters() {
        UISelectionFeedbackGenerator().selectionChanged()
        preferredOperator = nil
        departureTime = nil
        transitModes = []
        onFiltersChange()
    }

    /// « Je n'ai pas pu joindre le serveur », et on propose de réessayer.
    /// Surtout PAS « aucun itinéraire en transport en commun sur ce trajet » :
    /// c'est un verdict sur le réseau bruxellois qu'une panne réseau ne permet
    /// pas de rendre — et c'est ce que l'app affichait.
    @ViewBuilder private var backendUnreachableBanner: some View {
        if backendUnreachable {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "antenna.radiowaves.left.and.right.slash")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.statusMajor)
                VStack(alignment: .leading, spacing: 6) {
                    Text(AppLocalizer.string("routing.backend_unreachable.title",
                                             defaultValue: "Serveur injoignable"))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text(AppLocalizer.string("routing.backend_unreachable.body",
                                             defaultValue: "Les itinéraires en transport n'ont pas pu être chargés. Ce n'est pas le réseau qui manque, c'est la connexion."))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.Color.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                    Button(action: { onFiltersChange() }) {
                        Text(AppLocalizer.string("common.retry", defaultValue: "Réessayer"))
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(DS.Color.paper)
                            .padding(.horizontal, 14)
                            .frame(height: 30)
                            .background(Capsule().fill(DS.Color.ink))
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 2)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(DS.Color.statusMajor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.statusMajor.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 10)
        }
    }

    @ViewBuilder private var transitUnavailableBanner: some View {
        if showTransitUnavailableNotice {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.statusMajor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Routing.transitUnavailableTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text(L10n.Routing.transitUnavailableSubtitle)
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.Color.inkMute)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(DS.Color.statusMajor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.statusMajor.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.top, 6)
            .padding(.bottom, 6)
        }
    }

    // Bannière "itinéraire recalculé" : montre EXPLICITEMENT que le trajet
    // évite une ou plusieurs lignes signalées comme perturbées. C'est ce qui
    // transforme un re-route silencieux en boucle Waze perçue par l'utilisateur.
    @ViewBuilder
    private var rerouteBanner: some View {
        if !blockedLines.isEmpty {
            HStack(alignment: .center, spacing: 10) {
                Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.statusMajor)
                VStack(alignment: .leading, spacing: 4) {
                    Text(L10n.Routing.recalculatedTitle)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    HStack(spacing: 6) {
                        Text(L10n.Routing.avoids)
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.Color.inkMute)
                        ForEach(blockedLines.prefix(4), id: \.self) { line in
                            LineBadge(line: line, size: .sm)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 11)
            .background(DS.Color.statusMajor.opacity(0.08))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.statusMajor.opacity(0.25), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 6)
        }
    }

    @ViewBuilder
    private var modeSummaryStrip: some View {
        if !modeSummaries.isEmpty {
            HStack(spacing: 0) {
                ForEach(Array(modeSummaries.enumerated()), id: \.offset) { index, summary in
                    RouteModeSummaryTile(
                        summary: summary,
                        isHighlighted: summary.modeKey == selectedModeKey
                    )
                    .onTapGesture {
                        selectedModeKey = summary.modeKey
                        // Promeut la PLUS RAPIDE du mode choisi (cohérent avec la
                        // carte « recommandée » qui suit la sélection).
                        if let fastest = recommendedOption(for: summary.modeKey) {
                            expandedRouteID = fastest.id
                            onSelect(fastest)
                        }
                    }
                    if index < modeSummaries.count - 1 {
                        // ⚠️ HAUTEUR EXPLICITE. Un Rectangle sans hauteur est
                        // GLOUTON : tant que la bande vivait dans la ScrollView
                        // (hauteur libre) il se calait sur les carreaux, mais
                        // épinglée dans un en-tête à hauteur contrainte, il
                        // s'étirait et gonflait la bande à ~250 pt de haut.
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.12))
                            .frame(width: 1, height: 24)
                    }
                }
            }
            .frame(height: 40)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.horizontal, 16)
            .padding(.bottom, 10)
        }
    }

    @ViewBuilder
    private var recommendedSection: some View {
        if let recommended {
            RouteOptionCard(
                option: recommended,
                isRecommended: true,
                isFastest: recommended.id == filteredOptions.first?.id,
                isSelected: selectedRouteID == recommended.id,
                action: {
                    onSelect(recommended)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        expandedRouteID = recommended.id
                        isExpanded = true
                        detent = .large
                    }
                },
                isExpandedCard: expandedRouteID == recommended.id,
                expandedContent: AnyView(InlineRouteDetails(option: recommended)),
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        expandedRouteID = expandedRouteID == recommended.id ? nil : recommended.id
                        isExpanded = true
                        detent = .large
                    }
                },
                comparisonText: recommended.comparisonTag
            )
            .padding(.horizontal, 16)
        } else if hasActiveFilters {
            // Résultat backend vide À CAUSE des filtres (cf. HomeView ->
            // buildBackendFirstRouteOptions/respectActiveFilters) : un état
            // dédié, honnête, plutôt que le message générique "active ta
            // position" qui n'a rien à voir avec la cause réelle.
            noItineraryWithFiltersState
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
        } else {
            // E1 — État vide : avant la feuille s'affichait sans contenu
            // (zéro option + tous les modeSummaries à "—"). Désormais on
            // explique pourquoi et on guide le user vers la solution.
            emptyTripState
                .padding(.horizontal, 16)
                .padding(.vertical, 20)
        }
    }

    private var emptyTripState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "location.slash.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.Color.statusMinor)
                    .frame(width: 32, height: 32)
                    .background(DS.Color.statusMinor.opacity(0.12))
                    .clipShape(Circle())
                Text(L10n.Routing.noItineraryTitle)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
            }
            Text(L10n.Routing.noItineraryBody)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
                .lineSpacing(2)
        }
        .padding(14)
        .background(DS.Color.paper2.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Cas fréquent : un filtre légitime (ex. "SNCB" sur un trajet
    /// intra-Bruxelles) ne donne simplement aucun résultat. Plutôt que de
    /// laisser croire à une panne, on nomme la cause et on propose la sortie.
    private var noItineraryWithFiltersState: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                Image(systemName: "line.3.horizontal.decrease.circle.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(DS.Color.statusMinor)
                    .frame(width: 32, height: 32)
                    .background(DS.Color.statusMinor.opacity(0.12))
                    .clipShape(Circle())
                Text(L10n.Routing.noItineraryWithFiltersTitle)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
            }
            Button(action: resetFilters) {
                Text(L10n.Routing.resetFilters)
                    .font(.system(size: 12, weight: .bold))
                    .foregroundStyle(DS.Color.primaryForeground)
                    .padding(.horizontal, 14)
                    .frame(height: 32)
                    .background(DS.Color.primary)
                    .clipShape(Capsule())
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DS.Color.paper2.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Remplace la liste pendant le recalcul déclenché par un changement de
    /// filtre — "remet la liste en chargement" plutôt que de laisser un
    /// résultat obsolète (potentiellement pour d'autres filtres) à l'écran.
    private var routeLoadingState: some View {
        VStack(spacing: 10) {
            ProgressView()
                .tint(DS.Color.ink)
            Text(L10n.Common.loading)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    /// En-tête « AUTRES ITINÉRAIRES · N ». Rendu UNIQUEMENT s'il y en a :
    /// affiché sur une liste vide, il annonçait « AUTRES ITINÉRAIRES 00 » —
    /// un titre de section suivi de rien, avec un compteur zéro-padded qui
    /// ressemblait à un bug d'affichage.
    @ViewBuilder private var optionsHeader: some View {
        if !others.isEmpty {
            HStack(alignment: .center) {
                Text(L10n.Routing.otherItineraries.uppercased(with: AppLocale.current))
                    .font(DS.Font.labelSmall.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(DS.Color.ink)
                Text("\(others.count)")
                    .font(DS.Font.labelSmall)
                    .foregroundStyle(DS.Color.inkMute)
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.12))
                    .frame(height: 1)
            }
            .padding(.horizontal, 16)
            .padding(.top, 14)
        }
    }

    private var otherOptionsList: some View {
        VStack(spacing: 8) {
            ForEach(others) { option in
                RouteOptionCard(
                    option: option,
                    isRecommended: false,
                    isFastest: option.id == filteredOptions.first?.id,
                    isSelected: selectedRouteID == option.id,
                    action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            if expandedRouteID == option.id {
                                expandedRouteID = nil
                            } else {
                                onSelect(option)
                                expandedRouteID = option.id
                                isExpanded = true
                            detent = .large
                                detent = .large
                        detent = .large
                            }
                        }
                    },
                    isExpandedCard: expandedRouteID == option.id,
                    expandedContent: AnyView(InlineRouteDetails(option: option)),
                    onToggleExpanded: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            expandedRouteID = expandedRouteID == option.id ? nil : option.id
                            isExpanded = true
                            detent = .large
                        detent = .large
                        }
                    },
                    comparisonText: option.comparisonTag ?? option.deltaText(comparedTo: recommended)
                )
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 18)
    }
}

private struct RouteOptionCard: View {
    let option: HomeRouteOption
    let isRecommended: Bool
    /// Vraie option la plus rapide de la liste filtrée. Indépendant de
    /// `isRecommended`, qui suit la sélection MANUELLE de l'utilisateur
    /// (cf. `RouteRecommendationsSheet.recommended`) — un choix plus lent
    /// promu en tête ne doit jamais s'afficher "Le plus rapide".
    var isFastest: Bool = false
    let isSelected: Bool
    let action: () -> Void
    var isExpandedCard: Bool = false
    var expandedContent: AnyView? = nil
    var onToggleExpanded: (() -> Void)? = nil
    /// Pourquoi cette option diffère de la recommandée — le label backend
    /// ("Plus fiable", "Moins de marche"…) si disponible, sinon un delta de
    /// minutes en repli (cas Apple-Maps-only, sans alternative backend).
    var comparisonText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                compactLayout
            }
            .buttonStyle(.plain)

            if let expandedContent, isExpandedCard {
                expandedContent
            }
        }
        .background(DS.Color.paper)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(option.leadingAccentColor)
                .frame(width: isRecommended ? 5 : 3)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? DS.Color.primary : DS.Color.ink.opacity(0.16), lineWidth: isRecommended ? 1.35 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    /// Rangée compacte façon Google Maps (~72-84 pt, contre ~150-200 pt avant) :
    /// colonne durée fixe à gauche, plage horaire + séquence de tronçons +
    /// temps réel empilés à droite. UNE seule mise en page pour la carte
    /// recommandée et les alternatives (avant : deux layouts distincts) — seuls
    /// le liseré et le tag "Le plus rapide" distinguent la meilleure option.
    /// La vignette de carte (`RouteShapeThumbnail`) a disparu : elle bouffait
    /// la place et le tracé réel est déjà dessiné sur la carte sous le sheet.
    private var compactLayout: some View {
        HStack(alignment: .top, spacing: 12) {
            durationColumn

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(option.scheduleRangeText)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                        .layoutPriority(1)
                    if let tag = displayedTag {
                        tagPill(tag)
                    }
                    Spacer(minLength: 0)
                    if let onToggleExpanded {
                        Button(action: onToggleExpanded) {
                            Image(systemName: isExpandedCard ? "chevron.up" : "chevron.down")
                                .font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                                .frame(width: 22, height: 22)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if !option.legChips.isEmpty {
                    RouteLinesStrip(chips: option.legChips)
                }

                if let nextDeparture = option.nextDepartureInsight {
                    RouteNextDepartureLine(insight: nextDeparture)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }

    /// Nombre en gros + unité dessous, largeur fixe pour que toutes les
    /// rangées s'alignent verticalement (comme les résultats Google Maps).
    private var durationColumn: some View {
        VStack(spacing: 0) {
            Text("\(option.totalDurationMinutes)")
                .font(.system(size: 22, weight: .black))
                .tracking(-0.5)
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(L10n.Routing.minutesUnit)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(width: 56)
    }

    /// Priorité à la raison backend ("Plus fiable"…) ; à défaut, "Le plus
    /// rapide" UNIQUEMENT sur la vraie option la plus rapide — jamais sur une
    /// option juste promue par sélection manuelle (cf. `isFastest`).
    private var displayedTag: String? {
        if let comparisonText, !comparisonText.isEmpty { return comparisonText }
        return isFastest ? L10n.Routing.fastestTag : nil
    }

    // Casse normale, sans-serif : un tag « Het snelste traject » se lit comme un
    // label, pas comme un code en capitales monospace. La mono reste réservée au
    // temps réel (minutes d'attente), pas à une étiquette de comparaison.
    private func tagPill(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 10.5, weight: .bold))
            .foregroundStyle(DS.Color.primary)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .padding(.horizontal, 6)
            .frame(height: 18)
            .background(DS.Color.primary.opacity(0.12))
            .clipShape(Capsule())
    }
}

/// Séquence des lignes d'un itinéraire (🚶 → 35 → 🚶 → R30), affichée
/// directement sur la carte pour qu'on voie les lignes utilisées SANS avoir à
/// déplier le détail. Badges aux couleurs officielles de chaque ligne.
private struct RouteLinesStrip: View {
    let chips: [RouteLegChip]

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                if index > 0 {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 7, weight: .black))
                        .foregroundStyle(DS.Color.inkMute.opacity(0.45))
                }
                switch chip {
                case .walk(let minutes):
                    HStack(spacing: 2) {
                        Image(systemName: "figure.walk")
                            .font(.system(size: 10, weight: .bold))
                        Text("\(minutes)")
                            .font(.system(size: 10, weight: .heavy))
                    }
                    .foregroundStyle(DS.Color.inkMute)
                case .line(let descriptor):
                    Text(descriptor.code)
                        .font(.system(size: 11, weight: .heavy))
                        .foregroundStyle(descriptor.foregroundColor)
                        .padding(.horizontal, 5)
                        .frame(minWidth: 20, minHeight: 18)
                        .background(descriptor.fillColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }
            }
        }
        .lineLimit(1)
    }
}

/// Compact single-line replacement for the old big "PROCHAIN DÉPART" banner.
/// Shows the next leg's line badge, when it leaves, and a realtime dot — no
/// duplicate arrival/departure times since those already appear on the card
/// above. Drops the visual weight of the original orange pill.
private struct RouteNextDepartureLine: View {
    let insight: RouteDepartureInsight

    var body: some View {
        HStack(spacing: 6) {
            if insight.isRealtime {
                Circle()
                    .fill(DS.Color.statusOK)
                    .frame(width: 6, height: 6)
            }
            Text(L10n.Routing.next)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
            RouteLineMiniBadge(line: insight.lineCode)
                .frame(height: 22)
                .fixedSize()
            Text(insight.waitText)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Color.primary)
        }
    }
}

/// Onglet de mode, façon Google Maps : icône, un temps, le nom du mode — centré,
/// sans-serif. L'ancienne version empilait un badge « ⚡ SNEL » (qui se posait sur
/// la cellule la plus rapide et se battait avec le reste) au-dessus d'un libellé en
/// monospace majuscule serré : trois traitements typographiques pour un simple
/// bouton, d'où l'effet « technique et compressé ». Le « plus rapide » se lit
/// maintenant sur la carte d'itinéraire, pas dans le sélecteur.
private struct RouteModeSummaryTile: View {
    let summary: RouteModeSummary
    let isHighlighted: Bool

    private var icon: String {
        switch summary.modeKey {
        case "bike": return "bicycle"
        case "walk": return "figure.walk"
        default: return "tram.fill"
        }
    }

    /// Une SEULE ligne : icône + durée côte à côte. La version empilée (icône /
    /// durée / titre sur trois lignes) faisait ~78 pt de haut et mangeait le
    /// sheet avant même le premier itinéraire. Le pictogramme dit déjà « vélo »
    /// ou « à pied » : réécrire le mot dessous est redondant. On tombe à ~40 pt.
    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(isHighlighted ? DS.Color.paper : DS.Color.inkMute)
            Text(summary.durationText)
                .font(.system(size: 14, weight: .heavy))
                .tracking(-0.3)
                .foregroundStyle(isHighlighted ? DS.Color.paper : DS.Color.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .frame(height: 40)
        .background(isHighlighted ? DS.Color.ink : DS.Color.paper)
        // Le mot reste lisible par VoiceOver, il n'est simplement plus dessiné.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(summary.title) \(summary.durationText)")
    }
}

private struct RouteLineMiniBadge: View {
    let descriptor: RouteLineDescriptor

    init(line: String) {
        self.descriptor = RouteLineDescriptor(code: line)
    }

    init(descriptor: RouteLineDescriptor) {
        self.descriptor = descriptor
    }

    var body: some View {
        Text(descriptor.code)
            .font(DS.Font.labelSmall.weight(.bold))
            .foregroundStyle(descriptor.foregroundColor)
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, 3)
            .background(descriptor.fillColor)
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}

private struct InlineRouteDetails: View {
    let option: HomeRouteOption

    /// Opérateur d'un segment. Uniquement pour les segments transport (pas la marche).
    /// Un segment transport sans opérateur explicite est supposé STIB — l'app est
    /// bruxelloise, centrée MIVB ; De Lijn / TEC / SNCB arrivent taggés par le backend.
    private func operatorFor(_ item: InlineRouteStepItem) -> TransitOperator? {
        guard item.lineCode != nil else { return nil }
        return item.lineDescriptor?.operatorType ?? .stib
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DS.Color.primary)
                .frame(height: 2)
                .padding(.horizontal, -14)
                .padding(.bottom, 8)

            ForEach(Array(option.inlineSteps.enumerated()), id: \.element.id) { index, item in
                InlineRouteStepRow(
                    item: item,
                    operatorType: operatorFor(item),
                    isLast: index == option.inlineSteps.count - 1
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}

/// Une rangée du détail inline : le tronçon, puis — pour un tronçon STIB — les
/// arrêts traversés et les autres départs, chacun dépliable. Extraite en vue à
/// part pour porter son propre état de dépliage (impossible dans un `ForEach`).
private struct InlineRouteStepRow: View {
    let item: InlineRouteStepItem
    let operatorType: TransitOperator?
    let isLast: Bool

    @State private var showsStops = false
    @State private var showsDepartures = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 10) {
                if let lineCode = item.lineCode {
                    RouteLineMiniBadge(line: lineCode)
                        .frame(width: 30, height: 30)
                } else {
                    ZStack {
                        Circle()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.5)
                            .frame(width: 28, height: 28)
                        if let icon = item.icon {
                            Image(systemName: icon)
                                .font(.system(size: 12, weight: .medium))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                }

                VStack(alignment: .leading, spacing: 5) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(item.title)
                            .font(.system(size: 12.5, weight: .bold))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(2)
                        Spacer(minLength: 6)
                        if let timingBadge = item.timingBadge {
                            Text(timingBadge)
                                .font(.system(size: 10.5, weight: .black))
                                .tracking(-0.1)
                                .foregroundStyle(DS.Color.primary)
                                .lineLimit(1)
                        }
                    }
                    if let timingDetail = item.timingDetail {
                        Text(timingDetail)
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        if let op = operatorType {
                            Text(op.mapLabel)
                                .font(.system(size: 9, weight: .black))
                                .tracking(0.3)
                                .foregroundStyle(op.brandTextColor)
                                .padding(.horizontal, 5)
                                .padding(.vertical, 2)
                                .background(op.brandColor)
                                .clipShape(Capsule())
                                .accessibilityLabel(op.accessibilityLabel)
                        }
                        Text(item.meta)
                            .font(DS.Font.labelSmall)
                            .tracking(1.2)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }

                    // Les arrêts traversés + les autres départs. Le backend ne les
                    // fournit que pour la STIB : vides ailleurs → aucun chevron
                    // (un dépliant qui s'ouvre sur du vide est pire que rien).
                    if !item.intermediateStops.isEmpty {
                        InlineDisclosure(
                            title: L10n.Routing.stopsBetween(item.intermediateStops.count),
                            isExpanded: $showsStops
                        ) {
                            ForEach(Array(item.intermediateStops.enumerated()), id: \.offset) { _, stop in
                                HStack(spacing: 8) {
                                    Circle().fill(DS.Color.inkMute.opacity(0.4)).frame(width: 4, height: 4)
                                    Text(stop)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(DS.Color.inkMute)
                                }
                            }
                        }
                    }
                    if !item.otherDepartures.isEmpty {
                        InlineDisclosure(
                            title: L10n.Routing.otherDepartures,
                            isExpanded: $showsDepartures
                        ) {
                            ForEach(item.otherDepartures) { dep in
                                InlineDepartureLine(departure: dep)
                            }
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, 8)

            if let wait = item.waitAfterMinutes {
                HStack(spacing: 8) {
                    Image(systemName: "hourglass")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Color.statusMinor)
                        .frame(width: 30)
                    Text(L10n.Routing.waitTransfer(wait))
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(DS.Color.statusMinor)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, 7)
                .padding(.horizontal, 6)
                .background(DS.Color.statusMinor.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            } else if !isLast {
                Rectangle()
                    .fill(DS.Color.ink.opacity(0.12))
                    .frame(height: 1)
            }
        }
    }
}

/// Un dépliant discret : un titre + chevron, le contenu dessous quand ouvert.
private struct InlineDisclosure<Content: View>: View {
    let title: String
    @Binding var isExpanded: Bool
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button {
                withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) { isExpanded.toggle() }
            } label: {
                HStack(spacing: 5) {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .black))
                        .rotationEffect(.degrees(isExpanded ? 90 : 0))
                    Text(title)
                        .font(.system(size: 11.5, weight: .bold))
                    Spacer(minLength: 0)
                }
                .foregroundStyle(DS.Color.inkMute)
            }
            .buttonStyle(.plain)

            if isExpanded {
                VStack(alignment: .leading, spacing: 5) { content() }
                    .padding(.leading, 4)
            }
        }
        .padding(.top, 2)
    }
}

/// Une ligne « autre départ » : l'heure, le retard temps réel, le nôtre surligné.
/// Tappable (sauf le passage courant) : recalcule le trajet depuis cette heure,
/// comme Google Maps. La closure vient de l'Environment (`routeReplan`).
private struct InlineDepartureLine: View {
    let departure: RouteOtherDeparture
    @Environment(\.routeReplan) private var routeReplan

    private var tappableDate: Date? {
        departure.isThisTrip ? nil : departure.scheduledAt
    }

    var body: some View {
        if let date = tappableDate {
            Button { routeReplan(date) } label: { row(showReplanHint: true) }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.Routing.replanFromDeparture)
        } else {
            row(showReplanHint: false)
        }
    }

    private func row(showReplanHint: Bool) -> some View {
        HStack(spacing: 8) {
            Text(departure.timeText)
                .font(.system(size: 11.5, weight: departure.isThisTrip ? .black : .semibold))
                .foregroundStyle(departure.isThisTrip ? DS.Color.primary : DS.Color.ink)
            if let realtime = departure.realtimeText {
                Text(realtime)
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(DS.Color.statusMinor)
            }
            Spacer(minLength: 0)
            if showReplanHint {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 9.5, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute.opacity(0.7))
            }
        }
        .contentShape(Rectangle())
        .padding(.vertical, 3)
        .padding(.horizontal, 6)
        .background(departure.isThisTrip ? DS.Color.primary.opacity(0.12) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
    }
}
