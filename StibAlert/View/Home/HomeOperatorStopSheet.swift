import SwiftUI

/// Sheet shown when tapping a De Lijn / TEC stop on the map.
///
/// De Lijn : live next-departures via `OperatorRealtimeService.delijnStop`
/// (`/api/operators/delijn/stops/:id/realtime`). Auto-refresh every 30 s while
/// the sheet is open.
///
/// TEC : per-stop realtime isn't wired — TEC's GTFS-RT trip-update would
/// share the STIB Mobility quota and require parsing GTFS-static stop_times,
/// volontairement reporté post-TFE. Placeholder preserved.
struct HomeOperatorStopSheet: View {
    let stop: OperatorMapStop
    let onReport: () -> Void

    @State private var reply: OperatorRealtimeReply?
    @State private var stopInfo: OperatorStopInfoReply?
    @State private var stopDisruptions: OperatorStopDisruptionsReply?
    @State private var isLoading = false
    @State private var refreshTask: Task<Void, Never>?

    private var supportsRealtime: Bool { stop.op == .delijn }
    private var futurePassages: [OperatorRealtimePassage] {
        let now = Date().addingTimeInterval(-60) // tolérance 1 min pour les passages "à l'arrêt"
        return (reply?.passages ?? [])
            .filter { ($0.effectiveTime ?? .distantPast) >= now }
            .prefix(8)
            .map { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            header

            if supportsRealtime {
                // Header + CTA "Signaler" restent fixes ; seul le contenu
                // (lignes, passages, perturbations) scrolle. Sans ça, un arrêt
                // avec beaucoup de lignes poussait les passages temps réel hors
                // de l'écran sans aucun moyen de les atteindre.
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 16) {
                        linesSection
                        liveSection
                        disruptionsSection
                    }
                    .padding(.bottom, 4)
                }
            } else {
                Text("Horaires et infos trafic \(stop.op.mapLabel) arrivent bientôt pour cet arrêt.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer(minLength: 0)
            }

            reportButton
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper.ignoresSafeArea())
        .presentationDetents(supportsRealtime ? [.medium, .large] : [.height(250)])
        .presentationDragIndicator(.visible)
        // U1 — `.preferredColorScheme(.light)` retiré. DS.Color.* adapte.
        .task {
            await loadRealtime()
            startAutoRefresh()
        }
        .onDisappear {
            refreshTask?.cancel()
        }
    }

    private var reportButton: some View {
        Button(action: onReport) {
            HStack(spacing: 10) {
                Image(systemName: "plus")
                    .font(.system(size: 16, weight: .black))
                Text("Signaler cet arrêt")
                    .font(DS.Font.bodyBold)
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
    }

    // MARK: - Header

    private var header: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(stop.op.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 30, height: 30)
                .frame(width: 50, height: 50)
                .background(DS.Color.paper2.opacity(0.8))
                .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 15, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                )
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("ARRÊT \(stop.op.mapLabel.uppercased())")
                        .font(DS.Font.eyebrow)
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                    if supportsRealtime, reply?.live == true {
                        liveBadge
                    }
                }
                Text(stop.name)
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)
            }
            Spacer(minLength: 0)
        }
    }

    private var liveBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(DS.Color.statusOK)
                .frame(width: 6, height: 6)
            Text("LIVE")
                .font(DS.Font.eyebrow)
                .tracking(1.2)
                .foregroundStyle(DS.Color.statusOK)
        }
    }

    // MARK: - Realtime list (De Lijn only)

    @ViewBuilder
    private var liveSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Prochains passages")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.8)
                }
            }

            if let reply, !reply.live, futurePassages.isEmpty {
                // Cas dégradé : pas de live + pas de fallback
                Text(reply.error ?? AppLocalizer.string("realtime.unavailable_stop", defaultValue: "Données temps réel indisponibles pour cet arrêt."))
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            } else if futurePassages.isEmpty, !isLoading {
                Text("Aucun passage De Lijn annoncé dans les prochaines minutes.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            } else {
                // Plus de ScrollView imbriqué ici : le scroll global de la
                // feuille gère tout (un scroll dans un scroll = conflit de
                // gestes + double barre de défilement).
                VStack(spacing: 8) {
                    ForEach(futurePassages) { p in
                        passageRow(p)
                    }
                }
            }
        }
        .padding(.top, 4)
    }

    @ViewBuilder
    private var linesSection: some View {
        // Une ligne peut apparaître plusieurs fois (une entrée par direction) ;
        // en vue d'ensemble on ne veut qu'un badge par numéro. Les directions
        // réapparaissent ligne par ligne dans "Prochains passages".
        let uniqueLines = dedupedLines(stopInfo?.lines ?? [])
        if !uniqueLines.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Lignes à cet arrêt")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                // Grille compacte de badges : un arrêt avec 10+ lignes tient en
                // quelques rangées au lieu d'une liste pleine hauteur qui
                // enterrait les passages temps réel.
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 50), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(uniqueLines, id: \.self) { line in
                        lineBadge(line)
                    }
                }
            }
        }
    }

    @ViewBuilder
    private var disruptionsSection: some View {
        let items = Array((stopDisruptions?.omleidingen ?? []) + (stopDisruptions?.storingen ?? []))
        if !items.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.primary)
                    Text("Infos trafic à cet arrêt")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                }
                VStack(spacing: 8) {
                    ForEach(items.prefix(3)) { item in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(item.title)
                                .font(DS.Font.bodySmall.weight(.semibold))
                                .foregroundStyle(DS.Color.ink)
                                .lineLimit(2)
                            if !item.description.isEmpty {
                                Text(item.description)
                                    .font(DS.Font.monoSmall)
                                    .foregroundStyle(DS.Color.inkMute)
                                    .lineLimit(3)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(10)
                        .background(DS.Color.primary.opacity(0.08))
                        .overlay(
                            RoundedRectangle(cornerRadius: 10, style: .continuous)
                                .stroke(DS.Color.primary.opacity(0.18), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                }
            }
        }
    }

    @ViewBuilder
    private func passageRow(_ p: OperatorRealtimePassage) -> some View {
        HStack(alignment: .center, spacing: 12) {
            // Badge ligne aux couleurs De Lijn/TEC, cohérent avec la grille
            // de lignes au-dessus.
            Text(p.line)
                .font(DS.Font.bodyBold)
                .foregroundStyle(stop.op.brandTextColor)
                .frame(minWidth: 38, minHeight: 28)
                .padding(.horizontal, 8)
                .background(stop.op.brandColor)
                .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(p.destination)
                    .font(DS.Font.bodySmall.weight(.semibold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                if let scheduled = p.scheduledAt {
                    Text(timeLabel(scheduled, predicted: p.predictedAt))
                        .font(DS.Font.monoSmall)
                        .tracking(0.8)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }

            Spacer(minLength: 0)

            // Temps d'attente proéminent, juste à côté de sa ligne : c'est
            // l'info qu'on cherche en priorité (« mon bus arrive dans ? »).
            // Le countdown prime sur l'heure absolue ; le délai passe en
            // sous-texte coloré.
            VStack(alignment: .trailing, spacing: 1) {
                if let minutes = minutesUntil(p.effectiveTime) {
                    Text(minutes == 0 ? "maintenant" : "\(minutes) min")
                        .font(.system(size: minutes == 0 ? 13 : 17, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                        .monospacedDigit()
                }
                if let delay = p.delayMin, delay != 0 {
                    Text(delayLabel(delay))
                        .font(DS.Font.monoSmall.weight(.bold))
                        .foregroundStyle(delayColor(delay))
                }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 10)
        .background(DS.Color.paper2.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func lineBadge(_ line: String) -> some View {
        Text(line)
            .font(DS.Font.bodyBold)
            .foregroundStyle(stop.op.brandTextColor)
            .frame(minWidth: 44, minHeight: 34)
            .padding(.horizontal, 6)
            .background(stop.op.brandColor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.18), lineWidth: 1)
            )
    }

    /// Dédoublonne les lignes par numéro (le backend renvoie une entrée par
    /// direction), en préservant l'ordre d'apparition.
    private func dedupedLines(_ lines: [OperatorStopLineInfo]) -> [String] {
        var seen = Set<String>()
        return lines.compactMap { seen.insert($0.line).inserted ? $0.line : nil }
    }

    /// Minutes (plancher) avant le passage, jamais négatif — `futurePassages`
    /// a déjà écarté les passages dépassés.
    private func minutesUntil(_ date: Date?) -> Int? {
        guard let date else { return nil }
        return max(0, Int(date.timeIntervalSinceNow / 60))
    }

    // MARK: - Formatting helpers

    private static let hhmm: DateFormatter = {
        let f = DateFormatter()
        f.locale = AppLocale.current
        f.timeZone = TimeZone(identifier: "Europe/Brussels")
        f.dateFormat = "HH:mm"
        return f
    }()

    private func timeLabel(_ scheduled: Date, predicted: Date?) -> String {
        let s = Self.hhmm.string(from: scheduled)
        guard let predicted, abs(predicted.timeIntervalSince(scheduled)) >= 60 else {
            return s
        }
        let p = Self.hhmm.string(from: predicted)
        return "\(s) → \(p)"
    }

    private func delayLabel(_ minutes: Int) -> String {
        switch minutes {
        case ..<0: return "\(minutes) min"
        case 0:    return "à l'heure"
        default:   return "+\(minutes) min"
        }
    }

    private func delayColor(_ minutes: Int) -> Color {
        switch minutes {
        case ..<(-1): return DS.Color.statusOK
        case ...1:    return DS.Color.inkMute
        case ...4:    return DS.Color.statusMinor
        default:      return DS.Color.statusMajor
        }
    }

    // MARK: - Loading / refresh

    @MainActor
    private func loadRealtime() async {
        guard supportsRealtime else { return }
        isLoading = true
        defer { isLoading = false }
        async let realtime = OperatorRealtimeService.delijnStop(stop.id)
        async let info = OperatorRealtimeService.delijnStopInfo(stop.id)
        async let disruptions = OperatorRealtimeService.delijnStopDisruptions(stop.id)
        reply = await realtime
        stopInfo = await info
        stopDisruptions = await disruptions
    }

    private func startAutoRefresh() {
        guard supportsRealtime else { return }
        // B1 — annule TOUJOURS la précédente boucle avant d'en démarrer une
        // nouvelle (sinon dismiss + re-open rapide → 2 tasks concurrentes
        // qui réécrivent reply en alternance → UI glitch).
        refreshTask?.cancel()
        refreshTask = nil
        refreshTask = Task {
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 30_000_000_000) // 30 s
                if Task.isCancelled { return }
                await loadRealtime()
            }
        }
    }
}
