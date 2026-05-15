import SwiftUI
import CoreLocation
import MapKit

struct DecisionView: View {
    enum Mode: Equatable {
        case routine
        case trip(destination: CLLocationCoordinate2D, label: String?)

        static func == (lhs: Mode, rhs: Mode) -> Bool {
            switch (lhs, rhs) {
            case (.routine, .routine):
                return true
            case let (.trip(leftCoordinate, leftLabel), .trip(rightCoordinate, rightLabel)):
                return leftCoordinate.latitude == rightCoordinate.latitude
                    && leftCoordinate.longitude == rightCoordinate.longitude
                    && leftLabel == rightLabel
            default:
                return false
            }
        }
    }

    let coordinate: CLLocationCoordinate2D?
    let preferredLine: String?
    let mode: Mode
    let onDismiss: () -> Void
    let onOpenMap: ((Int) -> Void)?
    let onOpenItinerary: ((DecisionWalkStop) -> Void)?
    let onLaunchRoute: ((CLLocationCoordinate2D, String?) -> Void)?

    init(
        coordinate: CLLocationCoordinate2D?,
        preferredLine: String?,
        mode: Mode = .routine,
        onDismiss: @escaping () -> Void,
        onOpenMap: ((Int) -> Void)? = nil,
        onOpenItinerary: ((DecisionWalkStop) -> Void)? = nil,
        onLaunchRoute: ((CLLocationCoordinate2D, String?) -> Void)? = nil
    ) {
        self.coordinate = coordinate
        self.preferredLine = preferredLine
        self.mode = mode
        self.onDismiss = onDismiss
        self.onOpenMap = onOpenMap
        self.onOpenItinerary = onOpenItinerary
        self.onLaunchRoute = onLaunchRoute
    }

    @State private var decision: DecisionDTO? = nil
    @State private var isLoading = true
    @State private var loadError: String? = nil

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    topBar
                    if isLoading {
                        loadingState
                    } else if let loadError {
                        errorState(message: loadError)
                    } else if let decision {
                        verdictHeader(decision)
                        if decision.tripMode == true {
                            tripContent(decision)
                        } else {
                            if let cluster = decision.affectedCluster {
                                clusterInfo(cluster)
                            }
                            if let liveLine = decision.liveLine, !liveLine.stops.isEmpty {
                                VehicleTrackVisualizer(liveLine: liveLine)
                                    .padding(.top, 4)
                            }
                            if let recommendation = decision.recommendation {
                                recommendationCard(recommendation, cluster: decision.affectedCluster)
                            } else if decision.verdict == .allClear {
                                allClearReassurance
                            } else if decision.verdict == .watch {
                                watchExplainer
                            }
                            if let cluster = decision.affectedCluster, decision.verdict != .allClear {
                                secondaryActions(cluster: cluster)
                            }
                        }
                    }
                }
                .padding(.horizontal, 22)
                .padding(.top, 16)
                .padding(.bottom, 60)
            }
        }
        .task { await loadDecision() }
    }

    private var topBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text("STIB ALERT")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                Text("Verdict")
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)
            }
            Spacer()
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 40, height: 40)
                    .background(DS.Color.paper2)
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer le verdict")
        }
    }

    private var loadingState: some View {
        VStack(spacing: 12) {
            ProgressView()
                .scaleEffect(1.2)
            Text("Analyse de la situation…")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity, minHeight: 200)
    }

    private func errorState(message: String) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 28, weight: .semibold))
                .foregroundStyle(DS.Color.danger)
            Text(message)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
            Button("Réessayer") {
                Task { await loadDecision() }
            }
            .buttonStyle(.borderedProminent)
        }
        .padding(.vertical, 40)
    }

    private func verdictHeader(_ decision: DecisionDTO) -> some View {
        let ribbon = Color(hex: decision.verdict.ribbonColor)
        return VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 10) {
                Image(systemName: decision.verdict.iconSystemName)
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundStyle(ribbon)
                Text(decision.verdict.shortLabel)
                    .font(DS.Font.monoSmall.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(ribbon)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(ribbon.opacity(0.12))
                    .clipShape(Capsule())
            }

            Text(decision.headline)
                .font(DS.Font.displayH1)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let subhead = decision.subhead, !subhead.isEmpty {
                Text(subhead)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if decision.isInRoutineWindow == true {
                HStack(spacing: 6) {
                    Image(systemName: "clock.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text("Pile dans ta fenêtre de trajet habituelle")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(0.6)
                }
                .foregroundStyle(ribbon)
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper2)
        .overlay(
            Rectangle()
                .fill(ribbon)
                .frame(width: 4)
                .frame(maxHeight: .infinity),
            alignment: .leading
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func clusterInfo(_ cluster: DecisionClusterRef) -> some View {
        HStack(spacing: 10) {
            LineBadge(line: cluster.ligne, size: .sm)
            VStack(alignment: .leading, spacing: 2) {
                Text(cluster.typeProbleme)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text(detailLine(for: cluster))
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.Color.paper2.opacity(0.5))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    private func detailLine(for cluster: DecisionClusterRef) -> String {
        var parts: [String] = []
        if let nom = cluster.arretNom, !nom.isEmpty {
            parts.append(nom)
        }
        parts.append("\(cluster.reportCount) signalement\(cluster.reportCount > 1 ? "s" : "")")
        parts.append("il y a \(cluster.ageMinutes) min")
        return parts.joined(separator: " · ")
    }

    private func recommendationCard(_ rec: DecisionRecommendation, cluster: DecisionClusterRef?) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .heavy))
                Text("NOTRE PLAN B")
                    .font(DS.Font.monoSmall.weight(.heavy))
                    .tracking(2)
            }
            .foregroundStyle(DS.Color.primary)

            Text(rec.action)
                .font(DS.Font.displayH3)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            if let walkToStop = rec.walkToStop {
                walkStopRow(walkToStop)
            }

            if let alts = rec.alternativeLines, !alts.isEmpty {
                HStack(spacing: 6) {
                    Text("Via:")
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                    ForEach(alts, id: \.self) { line in
                        LineBadge(line: line, size: .sm)
                    }
                }
            }

            if let viaRoute = rec.viaRoute, let eta = viaRoute.etaMinutes {
                HStack(spacing: 8) {
                    Image(systemName: "clock")
                        .font(.system(size: 12, weight: .semibold))
                    Text("ETA: \(eta) min")
                        .font(DS.Font.monoSmall.weight(.bold))
                }
                .foregroundStyle(DS.Color.inkMute)
            }

            if let reasoning = rec.reasoning, !reasoning.isEmpty {
                Text(reasoning)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }

            if let reasons = rec.reasons, !reasons.isEmpty {
                reasonsBlock(reasons)
            }

            if let multimodal = rec.multimodalAlternatives, !multimodal.isEmpty {
                multimodalBlock(multimodal)
            }

            if let walkToStop = rec.walkToStop {
                Button {
                    onOpenItinerary?(walkToStop)
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16, weight: .heavy))
                        Text("J'y vais")
                            .font(DS.Font.bodyBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.Color.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 6)
            }
        }
        .padding(18)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.primary.opacity(0.3), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: DS.Color.primary.opacity(0.1), radius: 8, x: 0, y: 4)
    }

    private func multimodalBlock(_ options: [DecisionMultimodalOption]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("OU SANS LES TRANSPORTS")
                .font(DS.Font.monoSmall.weight(.heavy))
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 4)

            HStack(spacing: 8) {
                ForEach(options) { option in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Image(systemName: option.displayIcon)
                                .font(.system(size: 14, weight: .heavy))
                                .foregroundStyle(DS.Color.primary)
                            Text(option.label)
                                .font(DS.Font.monoSmall.weight(.bold))
                                .tracking(0.5)
                                .foregroundStyle(DS.Color.ink)
                        }
                        Text("\(option.durationMinutes) min")
                            .font(DS.Font.displayH3)
                            .foregroundStyle(DS.Color.ink)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(10)
                    .background(DS.Color.paper2.opacity(0.5))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
        }
    }

    private func reasonsBlock(_ reasons: [DecisionReason]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("POURQUOI CE CHOIX")
                .font(DS.Font.monoSmall.weight(.heavy))
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 6)

            VStack(alignment: .leading, spacing: 6) {
                ForEach(reasons) { reason in
                    HStack(alignment: .top, spacing: 8) {
                        Image(systemName: reason.icon ?? "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundStyle(DS.Color.success)
                            .frame(width: 16, alignment: .leading)
                            .padding(.top, 2)
                        Text(reason.label)
                            .font(DS.Font.body)
                            .foregroundStyle(DS.Color.ink)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(DS.Color.success.opacity(0.06))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.success.opacity(0.2), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
    }

    private func walkStopRow(_ walkStop: DecisionWalkStop) -> some View {
        HStack(spacing: 10) {
            VStack {
                Image(systemName: "figure.walk")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 28, height: 28)
                    .background(DS.Color.success.opacity(0.15))
                    .clipShape(Circle())
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(walkStop.name)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Text("\(walkStop.distanceMeters) m · \(walkStop.walkMinutes) min à pied")
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer()
        }
    }

    private var allClearReassurance: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 30, weight: .regular))
                    .foregroundStyle(DS.Color.statusOK)
                VStack(alignment: .leading, spacing: 2) {
                    Text("Voie libre")
                        .font(.custom("DelaGothicOne-Regular", size: 24))
                        .foregroundStyle(DS.Color.ink)
                    Text(greetingForTime())
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .tracking(1.2)
                }
                Spacer()
            }

            Text("Tes lignes habituelles tournent sans accroc. Tu peux partir tranquille.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 8) {
                Image(systemName: "info.circle")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
                Text("On t'enverra une push si la situation change avant ton départ.")
                    .font(DS.Font.monoSmall)
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.top, 4)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    DS.Color.success.opacity(0.12),
                    DS.Color.success.opacity(0.05),
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.success.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func greetingForTime() -> String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<11: return "BON MATIN"
        case 11..<14: return "BONNE JOURNÉE"
        case 14..<18: return "BON APRÈS-MIDI"
        case 18..<23: return "BONNE SOIRÉE"
        default: return "BONNE NUIT"
        }
    }

    private var watchExplainer: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Garde un œil sur tes lignes")
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
            Text("Il y a quelques signalements isolés mais pas assez pour être sûr. Surveille la carte.")
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper2)
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func secondaryActions(cluster: DecisionClusterRef) -> some View {
        HStack(spacing: 10) {
            Button {
                onOpenMap?(cluster.clusterIndex)
            } label: {
                HStack {
                    Image(systemName: "map.fill")
                    Text("Voir sur la carte")
                        .font(DS.Font.body.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .foregroundStyle(DS.Color.ink)
                .background(DS.Color.paper2)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
            .buttonStyle(.plain)
        }
    }

    private func loadDecision() async {
        isLoading = true
        loadError = nil
        do {
            let result: DecisionDTO
            switch mode {
            case .routine:
                result = try await DecisionService.current(coordinate: coordinate, line: preferredLine)
            case .trip(let destination, let label):
                guard let origin = coordinate else {
                    await MainActor.run {
                        self.loadError = "Position introuvable. Active la géoloc."
                        self.isLoading = false
                    }
                    return
                }
                result = try await DecisionService.trip(
                    origin: origin,
                    destination: destination,
                    destinationLabel: label
                )
            }
            await MainActor.run {
                self.decision = result
                self.isLoading = false
            }
        } catch {
            await MainActor.run {
                self.loadError = "Impossible de calculer le verdict. Réessaie."
                self.isLoading = false
            }
        }
    }

    // MARK: - Trip Mode (ad-hoc destination)

    @ViewBuilder
    private func tripContent(_ decision: DecisionDTO) -> some View {
        VStack(spacing: 14) {
            if let bestRoute = decision.bestRoute {
                tripRouteCard(
                    title: "ITINÉRAIRE RECOMMANDÉ",
                    route: bestRoute,
                    emphasis: true,
                    showsDisruptionFlag: false
                )
            }
            if let defaultRoute = decision.defaultRoute {
                tripRouteCard(
                    title: "TON ROUTE HABITUEL",
                    route: defaultRoute,
                    emphasis: false,
                    showsDisruptionFlag: true
                )
            }
            if let alternatives = decision.alternatives, !alternatives.isEmpty {
                tripAlternativesList(alternatives)
            }
            if let disruptedLines = decision.disruptedLinesInArea, !disruptedLines.isEmpty {
                disruptedAreaHint(disruptedLines)
            }
        }
    }

    private func tripRouteCard(
        title: String,
        route: DecisionTripRoute,
        emphasis: Bool,
        showsDisruptionFlag: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                if emphasis {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(emphasis ? DS.Color.primary : DS.Color.inkMute)
                }
                Text(title)
                    .font(DS.Font.monoSmall.weight(.heavy))
                    .tracking(2)
                    .foregroundStyle(emphasis ? DS.Color.primary : DS.Color.inkMute)
            }

            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(route.durationMinutes) min")
                        .font(DS.Font.displayH2)
                        .foregroundStyle(DS.Color.ink)
                    if let walking = route.walkingMinutes, walking > 0 {
                        Text("dont \(walking) min à pied")
                            .font(DS.Font.monoSmall)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
                Spacer()
                if let lines = route.lines, !lines.isEmpty {
                    HStack(spacing: 4) {
                        ForEach(lines.prefix(3), id: \.self) { line in
                            LineBadge(line: line, size: .sm)
                        }
                    }
                }
            }

            if let summary = route.summary, !summary.isEmpty {
                Text(summary)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if showsDisruptionFlag, let disrupted = route.disruptedLines, !disrupted.isEmpty {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .heavy))
                    Text("Passe par \(disrupted.joined(separator: ", ")) · perturbé")
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(0.5)
                }
                .foregroundStyle(DS.Color.danger)
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(DS.Color.danger.opacity(0.1))
                .clipShape(Capsule())
            }

            if emphasis, case .trip(let destCoord, let label) = mode {
                let effectiveLabel = decision?.destinationLabel ?? label
                Button {
                    onLaunchRoute?(destCoord, effectiveLabel)
                } label: {
                    HStack {
                        Image(systemName: "arrow.right.circle.fill")
                            .font(.system(size: 16, weight: .heavy))
                        Text("Lancer l'itinéraire")
                            .font(DS.Font.bodyBold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(DS.Color.primary)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .buttonStyle(.plain)
                .padding(.top, 4)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(emphasis ? DS.Color.paper : DS.Color.paper2.opacity(0.6))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(emphasis ? DS.Color.primary.opacity(0.3) : DS.Color.ink.opacity(0.08), lineWidth: emphasis ? 1.5 : 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }

    private func tripAlternativesList(_ alternatives: [DecisionTripRoute]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("AUTRES OPTIONS")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.top, 6)

            ForEach(Array(alternatives.enumerated()), id: \.offset) { _, alt in
                HStack(alignment: .center, spacing: 10) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(alt.durationMinutes) min")
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                        if let summary = alt.summary {
                            Text(summary)
                                .font(DS.Font.monoSmall)
                                .foregroundStyle(DS.Color.inkMute)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    if let disrupted = alt.disruptedLines, !disrupted.isEmpty {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 12))
                            .foregroundStyle(DS.Color.danger)
                    }
                    if let lines = alt.lines, !lines.isEmpty {
                        ForEach(lines.prefix(2), id: \.self) { line in
                            LineBadge(line: line, size: .sm)
                        }
                    }
                }
                .padding(10)
                .background(DS.Color.paper2.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            }
        }
    }

    private func disruptedAreaHint(_ lines: [String]) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "bolt.fill")
                .font(.system(size: 11, weight: .heavy))
                .foregroundStyle(DS.Color.primary)
            Text("Lignes perturbées dans la zone : \(lines.prefix(6).joined(separator: ", "))")
                .font(DS.Font.monoSmall)
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(.top, 6)
    }
}
