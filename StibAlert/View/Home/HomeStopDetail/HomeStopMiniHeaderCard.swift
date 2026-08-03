import SwiftUI
import CoreLocation

/// Compact stop "chip header" shown in place of the search bar when the user
/// taps a stop pin on the map. Lets them swap the focused line without
/// opening the full preview card — the map keeps the line-focus dim treatment
/// so they can watch live vehicles on the chosen tracé.
struct HomeStopMiniHeaderCard: View {
    let stop: TransportStopSummaryDTO
    let selectedLine: String?
    let nextDepartures: [TransportDepartureDTO]
    let isLoading: Bool
    let liveVehicleCount: Int
    let liveVehicles: [TransportVehicleDTO]
    let onClose: () -> Void
    let onSelectLine: (String) -> Void
    let onFollowVehicle: (TransportVehicleDTO) -> Void
    let onShowDetail: () -> Void
    let onRefresh: () -> Void

    /// Nombre de passages TEMPS RÉEL de la ligne sélectionnée À CET ARRÊT.
    ///
    /// L'ancien badge « N live » comptait les VÉHICULES de la ligne suivis sur la
    /// carte (flux positions), pas les arrivées à cet arrêt (flux WaitingTimes) —
    /// deux sources STIB distinctes. D'où « 3 live » affiché à côté de « Aucun
    /// passage prévu » : 3 bus de la ligne roulaient ailleurs, aucun n'était annoncé
    /// ici. On compte désormais les arrivées réelles à l'arrêt : une seule vérité.
    private var selectedLineLiveDepartureCount: Int {
        lineDepartures.filter { $0.source != "scheduled" && $0.source != nil }.count
    }

    private var displayedLines: [String] {
        // De-duplicate while preserving order; the API sometimes ships the
        // same line under both metro and tram catalogs.
        var seen = Set<String>()
        return stop.lines.filter { line in
            let key = line.trimmingCharacters(in: .whitespaces).uppercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }

    private var lineDepartures: [TransportDepartureDTO] {
        guard let selectedLine else { return [] }
        let normalized = normalize(selectedLine)
        // Pas de .prefix global ici : il coupait AVANT le groupement par
        // direction, donc quand les prochains passages partaient tous dans le
        // même sens, l'autre direction (pourtant bien présente — loadStopDetail
        // fusionne les départs des deux quais) disparaissait. La limite se fait
        // par direction dans departuresByDestination / directionRow.
        return nextDepartures.filter { normalize($0.line) == normalized }
    }

    /// Un passage par couple (ligne, direction), TOUTES lignes confondues,
    /// classé par heure — comme l'app officielle STIB.
    ///
    /// Avant, la fiche n'affichait que la ligne sélectionnée : il fallait
    /// toucher chaque badge un par un pour savoir ce qui passe à cet arrêt.
    /// Le détail était pourtant déjà chargé pour toutes les lignes. Le choix
    /// d'une ligne ne sert donc plus qu'à mettre son tracé en avant sur la
    /// carte, sans plus rien cacher ici.
    private var upcomingByLineAndDirection: [TransportDepartureDTO] {
        var seen = Set<String>()
        var rows: [TransportDepartureDTO] = []
        for departure in nextDepartures.sorted(by: { $0.minutes < $1.minutes }) {
            let destination = (departure.destination?.uppercased())
                .flatMap { $0.isEmpty ? nil : $0 }
                ?? AppLocalizer.string("departure.unknown_direction", defaultValue: "DIRECTION INCONNUE")
            let key = "\(normalize(departure.line))|\(destination)"
            guard seen.insert(key).inserted else { continue }
            rows.append(departure)
        }
        return rows
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onShowDetail()
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        HStack(spacing: 6) {
                            Text(AppLocalizer.string("ARRÊT", defaultValue: "ARRÊT"))
                                .font(.system(size: 9, weight: .bold))
                                .tracking(1.2)
                                .foregroundStyle(DS.Color.inkMute)
                            // Uniquement s'il y a de vraies arrivées temps réel ici :
                            // le badge ne peut donc plus contredire « Aucun passage prévu ».
                            if selectedLineLiveDepartureCount > 0 {
                                liveCountBadge
                            }
                        }
                        Text(stop.name)
                            .font(.system(size: 17, weight: .bold))
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityHint("Ouvre les détails complets de l'arrêt")

                Button {
                    UISelectionFeedbackGenerator().selectionChanged()
                    onRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 32, height: 32)
                        .background(DS.Color.paper2)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .opacity(isLoading ? 0.5 : 1)
                .disabled(isLoading)
                .accessibilityLabel(AppLocalizer.string("Rafraîchir les passages", defaultValue: "Rafraîchir les passages"))

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 32, height: 32)
                        .background(DS.Color.paper2)
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizer.string("Fermer le détail", defaultValue: "Fermer le détail"))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 6) {
                    ForEach(displayedLines, id: \.self) { line in
                        lineChip(line)
                    }
                }
            }

            departuresRow

            detailButton
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(DS.Color.paper.opacity(0.98))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
        )
        .shadow(DS.Shadow.overlay)
    }

    @ViewBuilder
    private var departuresRow: some View {
        if isLoading && nextDepartures.isEmpty {
            HStack(spacing: 6) {
                ProgressView().scaleEffect(0.7)
                Text(AppLocalizer.string("Chargement des prochains passages…", defaultValue: "Chargement des prochains passages…"))
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
        } else if nextDepartures.isEmpty {
            // Maintenant que TOUTES les lignes sont listées, un vide veut dire
            // que l'arrêt entier n'a rien d'annoncé — plus besoin de nommer la
            // ligne sélectionnée ni de résumer « les autres lignes ».
            Text(AppLocalizer.string("Aucun passage prévu", defaultValue: "Aucun passage prévu"))
                .font(.system(size: 11.5, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Toutes les lignes de l'arrêt, une rangée par direction.
                ForEach(Array(upcomingByLineAndDirection.prefix(8).enumerated()), id: \.offset) { index, departure in
                    departureRow(departure)
                    if index < min(upcomingByLineAndDirection.count, 8) - 1 {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.06))
                            .frame(height: 1)
                    }
                }
                if lineDeparturesAllScheduled {
                    scheduledCaption
                        .padding(.top, 6)
                }
            }
        }
    }

    /// `[7] VANDERKINDERE ............ 1 min`
    private func departureRow(_ departure: TransportDepartureDTO) -> some View {
        let mode = TransitLineMode.mode(for: departure.line)
        let destination = (departure.destination?.uppercased())
            .flatMap { $0.isEmpty ? nil : $0 }
            ?? AppLocalizer.string("departure.unknown_direction", defaultValue: "DIRECTION INCONNUE")
        let isSelected = selectedLine.map(normalize) == normalize(departure.line)

        return HStack(spacing: 9) {
            Image(systemName: mode.sfSymbol)
                .font(.system(size: 10, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
                .frame(width: 14)

            LineBadge(line: departure.line, size: .sm)

            Text(destination)
                .font(.system(size: 11.5, weight: .semibold))
                .tracking(0.3)
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 6)

            departureTimeLabel(departure)
        }
        .padding(.vertical, 6)
        .opacity(selectedLine == nil || isSelected ? 1 : 0.55)
    }

    /// Imminent → double chevron, comme l'app STIB : plus court qu'un mot, et
    /// il se lit dans n'importe quelle langue.
    @ViewBuilder
    private func departureTimeLabel(_ departure: TransportDepartureDTO) -> some View {
        HStack(spacing: 4) {
            if departure.source == "realtime" {
                Circle()
                    .fill(DS.Color.statusOK)
                    .frame(width: 5, height: 5)
            } else {
                Image(systemName: "clock")
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }

            if departure.minutes <= 0 {
                // Deux flèches composées plutôt qu'un symbole SF unique : la
                // double flèche « à quai » de l'app STIB n'a pas d'équivalent
                // garanti dans le catalogue système, et un nom invalide ne
                // dessine rien du tout.
                HStack(spacing: -1) {
                    Image(systemName: "arrow.down")
                    Image(systemName: "arrow.down")
                }
                .font(.system(size: 11, weight: .black))
                .foregroundStyle(DS.Color.statusOK)
                .accessibilityLabel(AppLocalizer.string("realtime.now", defaultValue: "maintenant"))
            } else {
                Text(departure.departureLabel)
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
            }
        }
    }

    /// Vrai quand l'arrêt n'a QUE des passages théoriques (temps réel vide) :
    /// on l'annonce pour ne pas laisser croire que ce sont des horaires live.
    ///
    /// Le résumé « les autres lignes qui, elles, passent » a disparu avec cette
    /// refonte : il compensait le fait que la fiche ne montrait qu'une ligne à
    /// la fois. Toutes les lignes étant listées, il n'a plus d'objet.
    private var lineDeparturesAllScheduled: Bool {
        !nextDepartures.isEmpty && nextDepartures.allSatisfy { $0.source == "scheduled" }
    }

    private var scheduledCaption: some View {
        HStack(spacing: 4) {
            Image(systemName: "clock")
                .font(.system(size: 9, weight: .bold))
            Text(AppLocalizer.string("Horaires théoriques", defaultValue: "Horaires théoriques"))
                .font(.system(size: 10, weight: .semibold))
        }
        .foregroundStyle(DS.Color.inkMute)
    }

    /// Full-width row at the bottom that opens the standalone ArretDetailPage
    /// — the user wanted a clear path to the full detail screen (community
    /// reports, official disruptions, lines & destinations) from the mini
    /// card without losing the live focus context.
    private var detailButton: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onShowDetail()
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "list.bullet.rectangle.fill")
                    .font(.system(size: 11, weight: .bold))
                Text(AppLocalizer.string("Voir l'arrêt en détail", defaultValue: "Voir l'arrêt en détail"))
                    .font(.system(size: 12, weight: .bold))
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .bold))
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(DS.Color.paper2.opacity(0.75))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .padding(.top, 2)
    }

    private var liveCountBadge: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(DS.Color.statusOK)
                .frame(width: 5, height: 5)
            Text("\(selectedLineLiveDepartureCount) live")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(.horizontal, 6)
        .frame(height: 14)
        .background(DS.Color.paper2.opacity(0.6))
        .clipShape(Capsule())
    }

    private func lineChip(_ line: String) -> some View {
        // Sélection = vif vs estompé (même traitement que HomeStopPreviewCard).
        // Plus de contour noir (le « carré » qui alourdissait le badge) : la
        // ligne choisie reste en couleur pleine, les autres sont désaturées +
        // estompées. Aucune sélection → tout vif.
        let isDimmed = selectedLine != nil && !(selectedLine.map(normalize) == normalize(line))
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            onSelectLine(line)
        } label: {
            LineBadge(line: line, size: .sm)
                .saturation(isDimmed ? 0.25 : 1)
                .opacity(isDimmed ? 0.5 : 1)
                .animation(.easeOut(duration: 0.18), value: selectedLine)
        }
        .buttonStyle(.plain)
    }

    private func normalize(_ line: String) -> String {
        line.trimmingCharacters(in: .whitespaces).uppercased()
    }
}
