import SwiftUI

struct RouteRecommendationsSheet: View {
    let options: [HomeRouteOption]
    let modeSummaries: [RouteModeSummary]
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
                selectedModeKey = preferredInitialMode
                expandedRouteID = recommended?.id
            }
            .onChange(of: modeSummaries.map(\.modeKey)) { _, _ in
                selectedModeKey = preferredInitialMode
                expandedRouteID = filteredOptions.first?.id
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
        }
    }

    private var optionsHeader: some View {
        HStack(alignment: .center) {
            Text("AUTRES ITINÉRAIRES")
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

                VStack(alignment: .leading, spacing: 6) {
                    HStack(alignment: .firstTextBaseline) {
                        Text(option.durationText)
                            .font(.system(size: 24, weight: .black))
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

                    HStack(spacing: 8) {
                        ForEach(option.displayLineCodes, id: \.self) { code in
                            RouteLineMiniBadge(line: code)
                        }
                    }

                    if let nextDeparture = option.nextDepartureInsight {
                        RouteNextDepartureLine(insight: nextDeparture)
                            .padding(.top, 2)
                    }

                    RouteDurationStrip(segments: option.visualSegments)
                        .padding(.top, 4)
                }
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, isExpandedCard ? 8 : 14)
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
                HStack(spacing: 6) {
                    ForEach(Array(option.displayLineCodes.enumerated()), id: \.offset) { index, code in
                        RouteLineMiniBadge(line: code)
                        if index < option.displayLineCodes.count - 1 {
                            Image(systemName: "chevron.right")
                                .font(.system(size: 9, weight: .bold))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                }

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
            Text("Prochain")
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
                Text("⚡ RAPIDE")
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
    let line: String

    var body: some View {
        Text(line)
            .font(DS.Font.monoSmall.weight(.bold))
            .foregroundStyle(TransitLinePalette.foreground(for: line))
            .frame(minWidth: 30, minHeight: 30)
            .padding(.horizontal, 3)
            .background(TransitLinePalette.fill(for: line))
            .overlay(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

                if index < option.inlineSteps.count - 1 {
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
