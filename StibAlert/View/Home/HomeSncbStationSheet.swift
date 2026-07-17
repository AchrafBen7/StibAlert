import SwiftUI

struct HomeSncbStationSheet: View {
    let station: SNCBStation
    let onReport: () -> Void
    /// Ouvre la page détaillée de la gare (GareDetailPage) — mêmes horaires
    /// complets + infos trafic que par la liste Lijnen. nil-op par défaut pour
    /// ne pas casser d'éventuels autres appelants.
    var onOpenDetail: () -> Void = {}

    @State private var departures: [SNCBDeparture] = []
    @State private var isLoadingDepartures = true
    /// Temps réel iRail (facultatif) : sert UNIQUEMENT à annoter chaque départ
    /// théorique de sa VOIE. Le GTFS statique n'a aucun quai — la voie n'existe
    /// qu'en temps réel (comme dans GareDetailPage).
    @State private var realtime: SNCBRealtime?

    /// Départs temps réel groupés par minute planifiée, pour matcher le théorique.
    private var rtByMinute: [Int: [SNCBRTDeparture]] {
        Dictionary(grouping: realtime?.departures ?? [], by: \.scheduledMinutes)
    }

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 18) {
                HStack(alignment: .top, spacing: 12) {
                    Image("operator-sncb")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 38, height: 38)
                        .frame(width: 54, height: 54)
                        .background(DS.Color.paper2.opacity(0.8))
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                        )

                    VStack(alignment: .leading, spacing: 4) {
                        Text(station.displayProvince.uppercased() + " · GARE SNCB")
                            .font(DS.Font.eyebrow)
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)
                        Text(station.displayName)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(DS.Color.ink)
                    }
                    Spacer(minLength: 0)
                }

                departuresSection

                Button(action: onOpenDetail) {
                    HStack(spacing: 10) {
                        Image(systemName: "list.bullet.rectangle")
                            .font(.system(size: 15, weight: .bold))
                        Text(AppLocalizer.string("Voir la gare en détail", defaultValue: "Voir la gare en détail"))
                            .font(DS.Font.bodyBold)
                        Spacer(minLength: 0)
                        Image(systemName: "chevron.right")
                            .font(.system(size: 13, weight: .bold))
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 16)
                    .frame(maxWidth: .infinity)
                    .frame(height: 52)
                    .background(DS.Color.paper2.opacity(0.7))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)

                Button(action: onReport) {
                    HStack(spacing: 10) {
                        Image(systemName: "plus")
                            .font(.system(size: 16, weight: .black))
                        Text("Signaler cette gare")
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
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 24)
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task {
            async let depTask = SNCBStationService.departures(stationId: station.id, limit: 8)
            async let rtTask = SNCBStationService.realtime(stationId: station.id)
            departures = await depTask
            realtime = await rtTask
            isLoadingDepartures = false
        }
    }

    private var departuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROCHAINS DÉPARTS")
                .font(DS.Font.eyebrow)
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)

            if isLoadingDepartures {
                HStack { ProgressView().tint(DS.Color.ink); Spacer() }
                    .padding(.vertical, 8)
            } else if departures.isEmpty {
                Text(AppLocalizer.string("Aucun départ à venir pour le moment (horaires théoriques).", defaultValue: "Aucun départ à venir pour le moment (horaires théoriques)."))
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            } else {
                VStack(spacing: 0) {
                    ForEach(departures) { departureRow($0) }
                }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                Text(AppLocalizer.string("Horaires théoriques", defaultValue: "Horaires théoriques"))
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
    }

    private func departureRow(_ dep: SNCBDeparture) -> some View {
        HStack(spacing: 12) {
            Text(dep.time)
                .font(DS.Font.labelLarge)
                .foregroundStyle(DS.Color.ink)
                .frame(width: 52, alignment: .leading)

            if !dep.line.isEmpty {
                Text(dep.line)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color(hex: "#0055A4"))
                    .clipShape(Capsule())
            }

            Text(dep.destination)
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)

            Spacer(minLength: 0)

            // Voie temps réel (iRail), à droite comme sur un panneau de gare.
            // Absente = pas de badge (jamais de « Voie — »).
            if let voie = platform(for: dep) {
                Text("Voie \(voie)")
                    .font(.system(size: 11, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 8)
                    .frame(height: 22)
                    .background(DS.Color.paper2.opacity(0.8))
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(DS.Color.ink.opacity(0.10), lineWidth: 1))
                    .fixedSize()
            }
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1)
        }
    }

    /// Voie du départ théorique via le temps réel iRail (match par minute
    /// planifiée, désambiguïsé par destination puis ligne — même logique que
    /// GareDetailPage). nil si iRail ne la connaît pas ou renvoie « ? ».
    private func platform(for dep: SNCBDeparture) -> String? {
        guard let candidates = rtByMinute[dep.minutes], !candidates.isEmpty else { return nil }
        let rt: SNCBRTDeparture?
        if candidates.count == 1 {
            rt = candidates[0]
        } else {
            let destKey = dep.destination.normalizedStopKey
            rt = candidates.first { $0.destination.normalizedStopKey == destKey }
                ?? candidates.first { $0.line.caseInsensitiveCompare(dep.line) == .orderedSame }
        }
        guard let raw = rt?.platform?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw != "?" else { return nil }
        return raw
    }
}
