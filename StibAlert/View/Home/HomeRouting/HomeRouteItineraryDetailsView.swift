import SwiftUI

struct RouteItineraryDetailsView: View {
    let option: HomeRouteOption
    let onBack: () -> Void
    let onClose: () -> Void
    let onShowMap: () -> Void

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            VStack(spacing: 0) {
                header

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 24) {
                        itinerarySummaryCard

                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(option.detailSegments.enumerated()), id: \.offset) { index, segment in
                                RouteTimelineRow(
                                    segment: segment,
                                    isFirst: index == 0,
                                    isLast: index == option.detailSegments.count - 1
                                )
                            }
                        }

                        actionButtons
                            .padding(.top, 8)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 12)
                    .padding(.bottom, 32)
                }
            }
        }
    }

    private var header: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 16, weight: .medium))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)

            Spacer()

            Text(L10n.Routing.detailedItinerary.uppercased(with: AppLocale.current))
                .font(DS.Font.labelSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.ink)

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                    )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
    }

    private var actionButtons: some View {
        VStack(spacing: 12) {
            Button(action: onShowMap) {
                Text(L10n.Routing.seeOnMap)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private var itinerarySummaryCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.Routing.recommendedTrip.uppercased(with: AppLocale.current))
                .font(DS.Font.labelSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)

            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(option.originName)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                    Text(L10n.Routing.to.uppercased(with: AppLocale.current))
                        .font(DS.Font.labelSmall.weight(.bold))
                        .tracking(1.6)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(option.destinationName)
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text(option.durationText)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text(option.timingHeadlineText.uppercased())
                        .font(DS.Font.labelSmall.weight(.bold))
                        .tracking(1.4)
                        .foregroundStyle(DS.Color.inkMute)
                    if let timingSecondaryText = option.timingSecondaryText {
                        Text(timingSecondaryText)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(DS.Color.inkMute.opacity(0.82))
                    }
                }
            }

            HStack(spacing: 8) {
                detailPill(option.transitSummary)
                detailPill(option.walkingSummary)
                detailPill(option.reliabilityText, tint: DS.Color.community.opacity(0.14), foreground: DS.Color.community)
            }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 14)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
    }

    private func detailPill(_ text: String, tint: Color = DS.Color.paper2, foreground: Color = DS.Color.ink) -> some View {
        Text(text.uppercased())
            .font(DS.Font.labelSmall.weight(.bold))
            .tracking(1)
            .foregroundStyle(foreground)
            .padding(.horizontal, 8)
            .frame(height: 22)
            .background(tint)
            .clipShape(Capsule())
    }
}

private struct RouteTimelineRow: View {
    let segment: RouteItinerarySegment
    let isFirst: Bool
    let isLast: Bool

    @State private var showsStops = false
    @State private var showsDepartures = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(segment.timeText)
                .font(DS.Font.label)
                .foregroundStyle(DS.Color.inkMute)
                .frame(width: 54, alignment: .leading)
                .padding(.top, 2)

            // Le trait de la timeline s'ÉTIRE sur la hauteur réelle du contenu.
            // Avant, sa longueur était une constante (120 pt, 188 pt selon la carte) :
            // en dépliant les arrêts traversés, le contenu grandissait et le trait
            // restait court — la timeline se cassait en deux.
            VStack(spacing: 0) {
                if !isFirst {
                    Rectangle()
                        .fill(segment.accentColor.opacity(0.9))
                        .frame(width: 3, height: 16)
                }

                Circle()
                    .fill(segment.accentColor)
                    .frame(width: 10, height: 10)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.paper, lineWidth: segment.stepCard == nil ? 1 : 0)
                    )

                if !isLast {
                    Rectangle()
                        .fill(segment.accentColor.opacity(0.9))
                        .frame(width: 3)
                        .frame(minHeight: 36, maxHeight: .infinity)
                }
            }
            .frame(width: 16)

            VStack(alignment: .leading, spacing: 10) {
                HStack(alignment: .center, spacing: 8) {
                    if let icon = segment.icon {
                        Image(systemName: icon)
                            .font(.system(size: 15, weight: .medium))
                            .foregroundStyle(DS.Color.ink)
                            .frame(width: 24)
                    }

                    Text(segment.placeTitle)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)

                    Spacer()

                    if let stopCountText = segment.stopCountText {
                        Text(stopCountText)
                            .font(DS.Font.labelSmall)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }

                if let card = segment.stepCard {
                    RouteInstructionCard(card: card)
                }

                if let durationBadge = segment.durationBadge {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 12, weight: .semibold))
                        Text(durationBadge)
                            .font(DS.Font.label.weight(.bold))
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 12)
                    .frame(height: 33)
                    .background(DS.Color.paper)
                    .overlay(
                        RoundedRectangle(cornerRadius: 6, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                }

                // Les arrêts TRAVERSÉS. Le backend ne les connaît que sur le réseau STIB :
                // ailleurs la liste est vide, et on n'affiche alors AUCUN chevron — un
                // dépliant qui s'ouvre sur du vide est pire que pas de dépliant.
                if !segment.intermediateStops.isEmpty {
                    RouteDisclosureRow(
                        title: stopsDisclosureTitle,
                        isExpanded: showsStops,
                        onToggle: { toggle($showsStops) }
                    ) {
                        VStack(alignment: .leading, spacing: 7) {
                            ForEach(Array(segment.intermediateStops.enumerated()), id: \.offset) { _, stop in
                                HStack(spacing: 9) {
                                    Circle()
                                        .fill(segment.accentColor.opacity(0.55))
                                        .frame(width: 5, height: 5)
                                    Text(stop)
                                        .font(.system(size: 12))
                                        .foregroundStyle(DS.Color.inkMute)
                                }
                            }
                        }
                        .padding(.leading, 2)
                    }
                }

                // Les AUTRES passages de cette ligne à cet arrêt. Même règle.
                if !segment.otherDepartures.isEmpty {
                    RouteDisclosureRow(
                        title: L10n.Routing.otherDepartures,
                        isExpanded: showsDepartures,
                        onToggle: { toggle($showsDepartures) }
                    ) {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(segment.otherDepartures) { departure in
                                RouteDepartureLine(departure: departure)
                            }
                        }
                    }
                }
            }
            .padding(.bottom, isLast ? 0 : 18)
        }
    }

    /// « 10 arrêts (14 min) », comme chez Google : le nombre d'arrêts ET la durée.
    private var stopsDisclosureTitle: String {
        let stops = segment.stopCountText ?? L10n.Routing.stopCount(segment.intermediateStops.count + 1)
        guard let durationBadge = segment.durationBadge else { return stops }
        return "\(stops) (\(durationBadge))"
    }

    private func toggle(_ flag: Binding<Bool>) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.86)) {
            flag.wrappedValue.toggle()
        }
    }
}

/// Une rangée dépliable : un titre, un chevron qui pivote, et le contenu en dessous.
/// L'appelant ne la construit QUE s'il a quelque chose à y mettre.
private struct RouteDisclosureRow<Content: View>: View {
    let title: String
    let isExpanded: Bool
    let onToggle: () -> Void
    @ViewBuilder let content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button(action: onToggle) {
                HStack(spacing: 6) {
                    Text(title)
                        .font(DS.Font.labelSmall.weight(.bold))
                        .foregroundStyle(DS.Color.ink)
                    Image(systemName: "chevron.down")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                    Spacer(minLength: 0)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(.isButton)
            .accessibilityValue(isExpanded ? L10n.Common.expanded : L10n.Common.collapsed)

            if isExpanded {
                content()
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
}

/// Un autre passage : l'heure, le temps réel s'il existe, surligné si c'est le nôtre.
private struct RouteDepartureLine: View {
    let departure: RouteOtherDeparture

    var body: some View {
        HStack(spacing: 8) {
            Text(departure.timeText)
                .font(.system(size: 13, weight: departure.isThisTrip ? .bold : .regular))
                .foregroundStyle(DS.Color.ink)

            if let realtimeText = departure.realtimeText {
                Text(realtimeText)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(DS.Color.community)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(departure.isThisTrip ? DS.Color.primary.opacity(0.12) : Color.clear)
        )
    }
}

private struct RouteInstructionCard: View {
    let card: RouteItineraryStepCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 6) {
                Text(card.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .fixedSize(horizontal: false, vertical: true)

                if let lineBadge = card.lineBadge {
                    Text(lineBadge.code)
                        .font(DS.Font.labelSmall.weight(.bold))
                        .foregroundStyle(lineBadge.foregroundColor)
                        .padding(.horizontal, 5)
                        .frame(height: 17)
                        .background(lineBadge.fillColor)
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                }

                Spacer(minLength: 0)
            }

            Text(card.subtitle)
                .font(DS.Font.labelSmall.weight(.bold))
                .foregroundStyle(DS.Color.community)

            if let serviceInfo = card.serviceInfo {
                RouteTransitServiceCard(info: serviceInfo)
                    .padding(.top, 2)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(card.style == .mint ? DS.Color.paper2.opacity(0.8) : DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
    }
}

private struct RouteTransitServiceCard: View {
    let info: RouteTransitServiceInfo

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Text(info.lineCode)
                .font(DS.Font.label.weight(.bold))
                .foregroundStyle(TransitLinePalette.foreground(for: info.lineCode))
                .frame(width: 29, height: 28)
                .background(TransitLinePalette.fill(for: info.lineCode))
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(info.statusTitle)
                    .font(DS.Font.labelSmall.weight(.bold))
                    .foregroundStyle(DS.Color.statusMajor)
                Text(info.detail)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.ink)
                Text(L10n.Routing.nextDeparture)
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.top, 4)
                Text(info.waitTime)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 4)
        }
        .padding(10)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
    }
}
