import SwiftUI

@MainActor
final class LigneDetailViewModel: ObservableObject {
    enum DirectionVariant: String, CaseIterable, Identifiable {
        case city = "City"
        case suburb = "Suburb"
        case base = "Base"

        var id: String { rawValue }

        var label: String {
            switch self {
            case .city: return "Aller"
            case .suburb: return "Retour"
            case .base: return "Ligne"
            }
        }
    }

    struct StopSnapshot: Identifiable {
        let id: String
        let backendId: String?
        let stopId: String?
        let name: String
        let waits: [Int]
        let disruption: String?
        let reportsCount: Int
    }

    let line: LineStatusItem

    @Published var cityLine: TransportLineDTO?
    @Published var suburbLine: TransportLineDTO?
    @Published var baseLine: TransportLineDTO?
    @Published var stopCatalog: [ArretDTO] = []
    @Published var selectedVariant: DirectionVariant = .city
    @Published var isLoading = false
    @Published var loadError: String?
    @Published var isFollowed = false

    init(line: LineStatusItem) {
        self.line = line
    }

    var activeLine: TransportLineDTO? {
        switch selectedVariant {
        case .city:
            return cityLine ?? suburbLine ?? baseLine
        case .suburb:
            return suburbLine ?? cityLine ?? baseLine
        case .base:
            return baseLine ?? cityLine ?? suburbLine
        }
    }

    var availableVariants: [DirectionVariant] {
        var values: [DirectionVariant] = []
        if cityLine != nil { values.append(.city) }
        if suburbLine != nil { values.append(.suburb) }
        if values.isEmpty, baseLine != nil { values.append(.base) }
        return values.isEmpty ? [.base] : values
    }

    var destinationsLabel: String {
        let labels = availableVariants.compactMap { variantDestination($0) }
        let unique = Array(NSOrderedSet(array: labels)) as? [String] ?? labels
        if unique.count >= 2 {
            return "\(unique[0]) ⇄ \(unique[1])"
        }
        return unique.first ?? activeLine?.line.name ?? line.direction
    }

    var routeSubtitle: String {
        let stopsCount = orderedStops.count
        if orderedStops.contains(where: { $0.disruption != nil }) {
            let count = orderedStops.filter { $0.disruption != nil }.count
            return "\(stopsCount) arrêts · \(count) perturbation\(count > 1 ? "s" : "")"
        }
        return "\(stopsCount) arrêts · temps réel STIB"
    }

    var orderedStops: [StopSnapshot] {
        if let activeLine {
            let byStopId = stopCatalog.reduce(into: [String: ArretDTO]()) { result, dto in
                guard let stopId = dto.stopId, result[stopId] == nil else { return }
                result[stopId] = dto
            }
            let byBackendId = stopCatalog.reduce(into: [String: ArretDTO]()) { result, dto in
                guard result[dto.id] == nil else { return }
                result[dto.id] = dto
            }
            let byName = stopCatalog.reduce(into: [String: ArretDTO]()) { result, dto in
                let key = dto.nom.normalizedStopKey
                guard result[key] == nil else { return }
                result[key] = dto
            }

            return activeLine.line.stops.map { stop in
                let catalog = stop.stopId.flatMap { byStopId[$0] }
                    ?? byBackendId[stop.id]
                    ?? byName[stop.name.normalizedStopKey]
                return makeSnapshot(from: stop, catalog: catalog, lineDetail: activeLine)
            }
        }

        return stopCatalog.map { dto in
            StopSnapshot(
                id: dto.stopId ?? dto.id,
                backendId: dto.id,
                stopId: dto.stopId,
                name: dto.nom,
                waits: dto.nextPassages ?? dto.nextPassageMinutes.map { [$0] } ?? [],
                disruption: nil,
                reportsCount: 0
            )
        }
    }

    var summaryTitle: String {
        TransportViewAdapters.localizedSeverityLabel(
            severity: activeLine?.severity,
            fallback: activeLine?.label?.fr
        )
    }

    var summaryDetails: String {
        guard let activeLine else { return "Chargement des données de ligne…" }
        let departures = activeLine.nextDepartures.prefix(3).map { "\($0.line) \($0.minutes) min" }
        if departures.isEmpty {
            return activeLine.realtimeStatus
        }
        return departures.joined(separator: " • ")
    }

    var alternativeSummary: String? {
        activeLine?.recommendedAlternatives.first?.explanationDetails?.summary
            ?? activeLine?.recommendedAlternatives.first?.explanation
    }

    func load() async {
        guard AppConfig.isBackendEnabled else { return }
        guard !isLoading else { return }
        isLoading = true
        loadError = nil
        defer { isLoading = false }

        async let cityTask: TransportLineDTO? = try? await TransportService.line(id: "\(line.line):City")
        async let suburbTask: TransportLineDTO? = try? await TransportService.line(id: "\(line.line):Suburb")
        async let baseTask: TransportLineDTO? = try? await TransportService.line(id: line.line)
        async let stopsTask: [ArretDTO]? = try? await SignalementService.arretsParLigne(line.line)

        cityLine = await cityTask
        suburbLine = await suburbTask
        baseLine = await baseTask
        stopCatalog = await stopsTask ?? []

        if cityLine != nil {
            selectedVariant = .city
        } else if suburbLine != nil {
            selectedVariant = .suburb
        } else {
            selectedVariant = .base
        }

        if cityLine == nil && suburbLine == nil && baseLine == nil && stopCatalog.isEmpty {
            loadError = "Pas de données disponibles pour cette ligne."
        }
    }

    func toggleDirection() {
        let values = availableVariants
        guard values.count > 1, let currentIndex = values.firstIndex(of: selectedVariant) else { return }
        selectedVariant = values[(currentIndex + 1) % values.count]
    }

    private func variantDestination(_ variant: DirectionVariant) -> String? {
        let candidate: TransportLineDTO?
        switch variant {
        case .city: candidate = cityLine
        case .suburb: candidate = suburbLine
        case .base: candidate = baseLine
        }
        return candidate?.line.stops.last?.name
    }

    private func makeSnapshot(
        from stop: TransportLineStopDTO,
        catalog: ArretDTO?,
        lineDetail: TransportLineDTO
    ) -> StopSnapshot {
        let incidents = lineDetail.activeIncidents.filter {
            $0.stop?.id == stop.id
            || $0.stop?.id == catalog?.id
            || $0.stop?.id == catalog?.stopId
            || $0.stop?.name?.normalizedStopKey == stop.name.normalizedStopKey
        }

        let disruption = incidents.first?.description
            ?? incidents.first?.type

        let waits = catalog?.nextPassages ?? catalog?.nextPassageMinutes.map { [$0] } ?? []

        return StopSnapshot(
            id: stop.stopId ?? stop.id,
            backendId: catalog?.id ?? stop.id,
            stopId: catalog?.stopId ?? stop.stopId,
            name: stop.name,
            waits: waits.sorted(),
            disruption: disruption,
            reportsCount: incidents.count
        )
    }
}

struct LigneDetailPage: View {
    @StateObject private var viewModel: LigneDetailViewModel
    @Environment(\.dismiss) private var dismiss

    private let onBackOverride: (() -> Void)?

    init(lineId: String) {
        let fallback = LigneDetailPage.makeFallbackLine(lineId: lineId)
        _viewModel = StateObject(wrappedValue: LigneDetailViewModel(line: fallback))
        self.onBackOverride = nil
    }

    init(line: LineStatusItem, onBack: (() -> Void)? = nil) {
        _viewModel = StateObject(wrappedValue: LigneDetailViewModel(line: line))
        self.onBackOverride = onBack
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
            }
        }
        .modifier(PaperGrainBackground())
        .task {
            await viewModel.load()
        }
        .toolbar(.hidden, for: .navigationBar)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            HStack {
                Button(action: goBack) {
                    HStack(spacing: DS.Spacing.sm) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 16, weight: .semibold))
                        Text("Lignes")
                            .font(DS.Font.bodyBold)
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, DS.Spacing.lg)
                    .frame(height: 40)
                    .background(DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .shadow(DS.Shadow.raised)

                Spacer()

                Button {
                    viewModel.isFollowed.toggle()
                } label: {
                    HStack(spacing: 6) {
                        Image(systemName: viewModel.isFollowed ? "star.fill" : "star")
                            .font(.system(size: 12, weight: .bold))
                        Text("Suivre")
                            .font(DS.Font.bodySmall.weight(.semibold))
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, DS.Spacing.md)
                    .frame(height: 36)
                    .background(DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }

            PageHeader(
                title: "",
                eyebrow: "Ligne \(viewModel.line.line)",
                large: false
            )
        }
        .padding(.horizontal, DS.Spacing.xl)
        .padding(.top, DS.Spacing.md)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            identifierBlock

            if viewModel.availableVariants.count > 1 {
                directionToggle
            }

            summaryCard

            DS.Rule(thick: true)

            if viewModel.isLoading && viewModel.orderedStops.isEmpty {
                ProgressView()
                    .tint(DS.Color.ink)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 40)
            } else if let loadError = viewModel.loadError, viewModel.orderedStops.isEmpty {
                Text(loadError)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 48)
            } else {
                timeline
            }
        }
    }

    private var identifierBlock: some View {
        HStack(alignment: .center, spacing: DS.Spacing.lg) {
            LineBadge(
                line: viewModel.line.line,
                size: .lg,
                fill: viewModel.line.lineColor,
                foreground: viewModel.line.lineTextColor
            )

            VStack(alignment: .leading, spacing: 4) {
                Text(viewModel.destinationsLabel)
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)

                Text(viewModel.routeSubtitle)
                    .font(DS.Font.monoSmall)
                    .tracking(1.0)
                    .foregroundStyle(viewModel.orderedStops.contains(where: { $0.disruption != nil }) ? DS.Color.statusMajor : DS.Color.inkMute)
            }
        }
    }

    private var directionToggle: some View {
        Button {
            viewModel.toggleDirection()
        } label: {
            HStack(spacing: DS.Spacing.sm) {
                Image(systemName: "arrow.left.arrow.right")
                    .font(.system(size: 12, weight: .bold))
                Text("Direction · \(viewModel.selectedVariant.label)")
                    .font(DS.Font.bodyBold)
                Spacer()
                Text(activeDestination)
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, DS.Spacing.md)
            .frame(height: 40)
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private var summaryCard: some View {
        DS.PaperCard {
            VStack(alignment: .leading, spacing: DS.Spacing.md) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Temps réel")
                            .eyebrow()
                        Text(viewModel.summaryTitle)
                            .font(DS.Font.displayH3)
                            .foregroundStyle(DS.Color.ink)
                    }

                    Spacer()

                    DS.StatusPill(confidenceLabel, level: statusLevel)
                }

                Text(viewModel.summaryDetails)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)

                if let alternative = viewModel.alternativeSummary, !alternative.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Alternative")
                            .sectionTitle()
                        Text(alternative)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkSoft)
                    }
                }
            }
        }
    }

    private var timeline: some View {
        VStack(spacing: 0) {
            ForEach(Array(viewModel.orderedStops.enumerated()), id: \.element.id) { index, stop in
                LigneTimelineRow(
                    stop: stop,
                    isFirst: index == 0,
                    isLast: index == viewModel.orderedStops.count - 1
                )
            }
        }
    }

    private var activeDestination: String {
        viewModel.activeLine?.line.stops.last?.name ?? viewModel.line.destination
    }

    private var confidenceLabel: String {
        let confidence = viewModel.activeLine?.confidence ?? 0
        let value = Int((confidence * 100).rounded())
        return "\(value)% fiable"
    }

    private var statusLevel: DS.StatusLevel {
        switch viewModel.activeLine?.severity {
        case "critical": return .critical
        case "major": return .major
        case "minor": return .minor
        default: return .ok
        }
    }

    private func goBack() {
        if let onBackOverride {
            onBackOverride()
        } else {
            dismiss()
        }
    }

    private static func makeFallbackLine(lineId: String) -> LineStatusItem {
        let color = palette(for: lineId)
        return LineStatusItem(
            line: lineId,
            lineColor: color.fill,
            lineTextColor: color.foreground,
            origin: "Bruxelles",
            destination: "Bruxelles",
            direction: "Bruxelles",
            status: .fluid,
            reportsCount: 0,
            filter: LineFilter.from(line: lineId),
            confidenceText: nil
        )
    }

    private static func palette(for lineId: String) -> (fill: Color, foreground: Color) {
        switch LineFilter.from(line: lineId) {
        case .metro:
            return (DS.Color.metro, DS.Color.primaryForeground)
        case .tram:
            return (DS.Color.tram, DS.Color.ink)
        case .bus:
            return (DS.Color.bus, DS.Color.primaryForeground)
        case .all:
            return (DS.Color.primary, DS.Color.primaryForeground)
        }
    }
}

private struct LigneTimelineRow: View {
    let stop: LigneDetailViewModel.StopSnapshot
    let isFirst: Bool
    let isLast: Bool

    private var isTerminus: Bool { isFirst || isLast }

    var body: some View {
        HStack(alignment: .top, spacing: 0) {
            ZStack(alignment: .top) {
                if !isLast {
                    Rectangle()
                        .fill(DS.Color.ink.opacity(0.2))
                        .frame(width: 2)
                        .padding(.top, 24)
                        .frame(maxHeight: .infinity, alignment: .top)
                }

                Circle()
                    .fill(dotFill)
                    .frame(width: 12, height: 12)
                    .overlay(Circle().stroke(DS.Color.ink, lineWidth: 2))
                    .padding(.top, 12)
            }
            .frame(width: 24)

            HStack(alignment: .top, spacing: DS.Spacing.md) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(stop.name)
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)

                        if isTerminus {
                            Text("Terminus")
                                .font(DS.Font.monoSmall)
                                .tracking(1.2)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }

                    if let disruption = stop.disruption, !disruption.isEmpty {
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.system(size: 10))
                                .foregroundStyle(DS.Color.statusMajor)
                                .padding(.top, 2)
                            Text(disruption)
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(DS.Color.statusMajor)
                                .lineLimit(3)
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(DS.Color.statusMajor.opacity(0.08))
                        .overlay(alignment: .leading) {
                            Rectangle()
                                .fill(DS.Color.statusMajor)
                                .frame(width: 2)
                        }
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
                    }
                }

                Spacer(minLength: 8)

                if !stop.waits.isEmpty {
                    VStack(alignment: .trailing, spacing: 2) {
                        Text("\(stop.waits[0]) min")
                            .font(DS.Font.monoLarge)
                            .foregroundStyle(DS.Color.ink)
                        if stop.waits.count > 1 {
                            Text("+\(stop.waits[1])")
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                } else {
                    Text("--")
                        .font(DS.Font.mono)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.vertical, 10)
        }
    }

    private var dotFill: Color {
        if stop.disruption != nil { return DS.Color.statusMajor }
        if isTerminus { return DS.Color.ink }
        return DS.Color.paper
    }
}

private extension String {
    var normalizedStopKey: String {
        folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#if DEBUG
#Preview {
    NavigationStack {
        LigneDetailPage(lineId: "1")
    }
}
#endif
