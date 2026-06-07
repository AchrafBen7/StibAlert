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
    let onSelect: (HomeRouteOption) -> Void
    let onClose: () -> Void

    @GestureState private var dragOffset: CGFloat = 0
    @State private var expandedRouteID: UUID?
    @State private var selectedModeKey: String = "transit"

    private var sheetDragGesture: some Gesture {
        DragGesture(minimumDistance: 8)
            .updating($dragOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let verticalMove = value.translation.height
                let predictedMove = value.predictedEndTranslation.height

                withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                    if verticalMove < -70 || predictedMove < -120 {
                        isExpanded = true
                    } else if verticalMove > 110 || predictedMove > 180 {
                        if isExpanded {
                            isExpanded = false
                        } else {
                            onClose()
                        }
                    }
                }
            }
    }

    private var filteredOptions: [HomeRouteOption] {
        let subset = options.filter { $0.primaryModeKey == selectedModeKey }
        let base = subset.isEmpty ? options : subset
        return base.sorted { $0.totalDurationMinutes < $1.totalDurationMinutes }
    }
    private var recommended: HomeRouteOption? { filteredOptions.first }
    private var others: [HomeRouteOption] { Array(filteredOptions.dropFirst()) }

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
            let expandedHeight = min(proxy.size.height * 0.66, 584)
            let collapsedHeight = min(proxy.size.height * 0.34, 286)
            let sheetHeight = isExpanded ? expandedHeight : collapsedHeight

            VStack(spacing: 0) {
                Spacer()

                VStack(alignment: .leading, spacing: 0) {
                    sheetHandle
                        .contentShape(Rectangle())
                        .gesture(sheetDragGesture)

                    ScrollView(showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            modeSummaryStrip
                            rerouteBanner
                            recommendedSection
                            optionsHeader
                            otherOptionsList
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
                .offset(y: max(0, dragOffset))
                .allowsHitTesting(true)
            }
            .ignoresSafeArea()
            .onAppear {
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
                        if let first = options.first(where: { $0.primaryModeKey == summary.modeKey }) {
                            expandedRouteID = first.id
                            onSelect(first)
                        }
                    }
                    if index < modeSummaries.count - 1 {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.12))
                            .frame(width: 1)
                    }
                }
            }
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
                isSelected: selectedRouteID == recommended.id,
                action: {
                    onSelect(recommended)
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        expandedRouteID = recommended.id
                        isExpanded = true
                    }
                },
                isExpandedCard: expandedRouteID == recommended.id,
                expandedContent: AnyView(InlineRouteDetails(option: recommended)),
                onToggleExpanded: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                        expandedRouteID = expandedRouteID == recommended.id ? nil : recommended.id
                        isExpanded = true
                    }
                }
            )
            .padding(.horizontal, 16)
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

    private var optionsHeader: some View {
        HStack(alignment: .center) {
            Text(L10n.Routing.otherItineraries.uppercased(with: AppLocale.current))
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.ink)
            Text(String(format: "%02d", max(others.count, 0)))
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.inkMute)
            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 14)
    }

    private var otherOptionsList: some View {
        VStack(spacing: 12) {
            ForEach(others) { option in
                RouteOptionCard(
                    option: option,
                    isRecommended: false,
                    isSelected: selectedRouteID == option.id,
                    action: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            if expandedRouteID == option.id {
                                expandedRouteID = nil
                            } else {
                                onSelect(option)
                                expandedRouteID = option.id
                                isExpanded = true
                            }
                        }
                    },
                    isExpandedCard: expandedRouteID == option.id,
                    expandedContent: AnyView(InlineRouteDetails(option: option)),
                    onToggleExpanded: {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.84)) {
                            expandedRouteID = expandedRouteID == option.id ? nil : option.id
                            isExpanded = true
                        }
                    },
                    deltaText: option.deltaText(comparedTo: recommended)
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
    let isSelected: Bool
    let action: () -> Void
    var isExpandedCard: Bool = false
    var expandedContent: AnyView? = nil
    var onToggleExpanded: (() -> Void)? = nil
    var deltaText: String? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Button(action: action) {
                if isRecommended {
                    recommendedLayout
                } else {
                    alternativeLayout
                }
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
                .frame(width: isRecommended ? 6 : 4)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(isSelected ? DS.Color.primary : DS.Color.ink.opacity(0.16), lineWidth: isRecommended ? 1.35 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private var recommendedLayout: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                ZStack {
                    Circle()
                        .fill(DS.Color.ink)
                        .frame(width: 42, height: 42)
                    Image(systemName: option.primaryModeIcon)
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(DS.Color.paper)
                }

                VStack(alignment: .leading, spacing: 9) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.durationText)
                            .font(.system(size: 26, weight: .black))
                            .tracking(-0.8)
                            .foregroundStyle(DS.Color.ink)
                        if let timingSecondaryText = option.timingSecondaryText {
                            Text(timingSecondaryText)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Color.statusMinor)
                                .padding(.horizontal, 6)
                                .frame(height: 18)
                                .background(DS.Color.statusMinor.opacity(0.14))
                                .clipShape(Capsule())
                        }
                        Spacer(minLength: 12)
                        Button(action: { onToggleExpanded?() }) {
                            Image(systemName: isExpandedCard ? "chevron.up" : "chevron.down")
                                .font(.system(size: 16, weight: .semibold))
                                .foregroundStyle(DS.Color.inkMute)
                                .frame(width: 28, height: 28)
                        }
                        .buttonStyle(.plain)
                    }

                    Text(option.timingHeadlineText)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)

                    Text("\(option.primaryModeLabel.uppercased()) · \(option.transferSummary.uppercased())")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.8)
                        .foregroundStyle(DS.Color.inkMute)

                    RouteLegFlowStrip(chips: option.legChips)
                        .padding(.top, 2)

                    if let nextDeparture = option.nextDepartureInsight {
                        RouteNextDepartureLine(insight: nextDeparture)
                            .padding(.top, 2)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)
            .padding(.bottom, isExpandedCard ? 10 : 16)
        }
    }

    private var alternativeLayout: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text(option.durationText)
                    .font(.system(size: 18, weight: .black))
                    .tracking(-0.6)
                    .foregroundStyle(DS.Color.ink)
                if let deltaText {
                    Text(deltaText.uppercased())
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                }
                Text(option.timingHeadlineText)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
                if let nextDeparture = option.nextDepartureInsight {
                    Text("\(nextDeparture.lineCode) · \(nextDeparture.waitText)")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.1)
                        .foregroundStyle(DS.Color.primary)
                        .lineLimit(1)
                }
            }
            .frame(width: 88, alignment: .leading)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.12))
                .frame(width: 1)
                .frame(maxHeight: .infinity)

            VStack(alignment: .leading, spacing: 10) {
                RouteLegFlowStrip(chips: option.legChips)

                Text("\(option.transferSummary.uppercased()) · \(option.terminalLabel.uppercased())")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }

            Spacer(minLength: 10)

            Image(systemName: "chevron.right")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.trailing, 2)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
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

private struct RouteModeSummaryTile: View {
    let summary: RouteModeSummary
    let isHighlighted: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if summary.isFastest {
                Text("⚡ \(L10n.Routing.fastest.uppercased(with: AppLocale.current))")
                    .font(.system(size: 8, weight: .heavy, design: .monospaced))
                    .tracking(1)
                    .foregroundStyle(isHighlighted ? DS.Color.ink : DS.Color.paper)
                    .padding(.horizontal, 5)
                    .frame(height: 16)
                    .background(isHighlighted ? DS.Color.paper : DS.Color.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            } else {
                Spacer().frame(height: 16)
            }
            HStack(spacing: 6) {
                Image(systemName: summary.modeKey == "bike" ? "bicycle" : summary.modeKey == "walk" ? "figure.walk" : "tram.fill")
                    .font(.system(size: 10, weight: .medium))
                Text(summary.title.uppercased())
            }
            .font(DS.Font.monoSmall.weight(.bold))
            .tracking(1.2)
            .foregroundStyle(isHighlighted ? DS.Color.paper : DS.Color.inkMute)
            Text(summary.durationText)
                .font(.system(size: 14, weight: .black))
                .tracking(-0.4)
                .foregroundStyle(isHighlighted ? DS.Color.paper : DS.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(isHighlighted ? DS.Color.ink : DS.Color.paper)
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
            .font(DS.Font.monoSmall.weight(.bold))
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

/// Google-style journey flow: 🚶 → line → line → 🚶, with chevrons between
/// legs. Makes a multi-leg trip readable at a glance instead of a bare list of
/// line badges. Le flux PASSE À LA LIGNE (flow layout) au lieu d'être coupé /
/// scrollé : un trajet multi-correspondances (🚶 → 7 → 🚶 → IC → 🚶 → 9)
/// s'affiche en entier sur plusieurs lignes, plus rien n'est rogné au bord de
/// la carte.
private struct RouteLegFlowStrip: View {
    let chips: [RouteLegChip]

    var body: some View {
        // Chaque chevron reste collé au chip qui le suit (HStack groupé) pour
        // ne jamais laisser un « › » orphelin en fin de ligne quand ça wrappe.
        RouteLegWrapLayout(horizontalSpacing: 5, verticalSpacing: 6) {
            ForEach(Array(chips.enumerated()), id: \.offset) { index, chip in
                if index == 0 {
                    chipView(chip)
                } else {
                    HStack(spacing: 5) {
                        Image(systemName: "chevron.right")
                            .font(.system(size: 8, weight: .black))
                            .foregroundStyle(DS.Color.inkMute)
                        chipView(chip)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func chipView(_ chip: RouteLegChip) -> some View {
        switch chip {
        case .walk:
            Image(systemName: "figure.walk")
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
                .frame(width: 30, height: 30)
                .background(DS.Color.paper2.opacity(0.7))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        case .line(let descriptor):
            RouteLineMiniBadge(descriptor: descriptor)
        }
    }
}

/// Flow layout maison : place les chips de gauche à droite et passe à la ligne
/// dès que la largeur dispo est dépassée (même logique que STIBAIFlowLayout).
/// Permet à la séquence d'un itinéraire alternatif de ne jamais être coupée au
/// bord de la carte.
private struct RouteLegWrapLayout: Layout {
    var horizontalSpacing: CGFloat
    var verticalSpacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? 320
        let rows = computeRows(maxWidth: maxWidth, subviews: subviews)
        return CGSize(width: maxWidth, height: rows.last.map { $0.y + $0.height } ?? 0)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in computeRows(maxWidth: bounds.width, subviews: subviews) {
            for item in row.items {
                subviews[item.index].place(
                    at: CGPoint(x: bounds.minX + item.x, y: bounds.minY + row.y),
                    proposal: ProposedViewSize(width: item.size.width, height: item.size.height)
                )
            }
        }
    }

    private func computeRows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var currentItems: [Item] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let nextX = currentItems.isEmpty ? 0 : x + horizontalSpacing
            if !currentItems.isEmpty, nextX + size.width > maxWidth {
                rows.append(Row(y: y, height: rowHeight, items: currentItems))
                y += rowHeight + verticalSpacing
                currentItems = []
                x = 0
                rowHeight = 0
            }

            let itemX = currentItems.isEmpty ? 0 : x + horizontalSpacing
            currentItems.append(Item(index: index, x: itemX, size: size))
            x = itemX + size.width
            rowHeight = max(rowHeight, size.height)
        }

        if !currentItems.isEmpty {
            rows.append(Row(y: y, height: rowHeight, items: currentItems))
        }
        return rows
    }

    private struct Row {
        let y: CGFloat
        let height: CGFloat
        let items: [Item]
    }

    private struct Item {
        let index: Int
        let x: CGFloat
        let size: CGSize
    }
}

private struct RouteDurationStrip: View {
    let segments: [RouteVisualSegment]

    private var totalWeight: CGFloat {
        max(segments.reduce(0) { $0 + $1.weight }, 1)
    }

    var body: some View {
        GeometryReader { geo in
            let totalSpacing = CGFloat(max(segments.count - 1, 0)) * 2
            let usableWidth = max(geo.size.width - totalSpacing, 0)

            HStack(spacing: 2) {
                ForEach(Array(segments.enumerated()), id: \.offset) { _, segment in
                    RoundedRectangle(cornerRadius: 2.5, style: .continuous)
                        .fill(segment.tint)
                        .frame(width: max(10, usableWidth * (segment.weight / totalWeight)), height: 12)
                }
            }
            .padding(.horizontal, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 16)
            .background(DS.Color.ink.opacity(0.22))
            .clipShape(Capsule())
        }
        .frame(height: 16)
    }
}

private struct InlineRouteDetails: View {
    let option: HomeRouteOption

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Rectangle()
                .fill(DS.Color.primary)
                .frame(height: 2)
                .padding(.horizontal, -14)
                .padding(.bottom, 8)

            ForEach(Array(option.inlineSteps.enumerated()), id: \.element.id) { index, item in
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
                        Text(item.meta)
                            .font(DS.Font.monoSmall)
                            .tracking(1.2)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
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
                } else if index < option.inlineSteps.count - 1 {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.12))
                        .frame(height: 1)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 12)
    }
}
