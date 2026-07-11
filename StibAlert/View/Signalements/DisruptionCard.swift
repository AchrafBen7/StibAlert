import SwiftUI

/// Carte d'une perturbation officielle.
///
/// Avant, l'app affichait le texte brut de la STIB : un paragraphe entier servait de
/// titre, et la description était tronquée à trois lignes. L'usager devait lire
/// « Travaux. Du 27/4/26 à fin avril 2027, bus 50 dévié. Pour continuer vers GARE DU
/// MIDI, prenez le bus 49. » pour comprendre qu'il doit prendre le bus 49.
///
/// Ici, `DisruptionDigest` sépare les trois choses qui n'ont pas le même poids :
///
///   • **la cause** (Travaux)      → un bandeau discret, avec icône et teinte
///   • **l'effet** (bus 50 dévié)  → le TITRE : ce que l'usager subit
///   • **la période**              → une puce, factuelle
///   • **le conseil**              → mis en avant : la seule ligne actionnable
///
/// Le conseil est le différenciateur. C'est ce que les données officielles contiennent
/// déjà mais que personne ne montre.
struct DisruptionCard: View {
    let digest: DisruptionDigest
    /// Ligne concernée (« 50 »). Affichée en badge à droite du bandeau.
    var line: String?
    /// Arrêt concerné, si la STIB le précise.
    var stopName: String?

    /// Quand plusieurs communiqués décrivent LA MÊME perturbation, ils n'apportent
    /// chacun qu'un conseil différent (« à Abbaye, prends le 96 » / « à Legrand,
    /// marche 5 min »). On les fusionne en une carte, et leurs conseils deviennent
    /// cette liste — au lieu de N cartes qui se répètent presque mot pour mot.
    /// Vide ⇒ la carte retombe sur `digest.advice`, son comportement d'origine.
    var alternatives: [String] = []

    /// Nombre de communiqués fusionnés. > 1 affiche « d'après N communiqués » : on
    /// ne cache pas qu'on a réécrit la source, on l'assume.
    var sourceCount: Int = 1

    private var adviceList: [String] {
        if !alternatives.isEmpty { return alternatives }
        if let advice = digest.advice, !advice.isEmpty { return [advice] }
        return []
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            causeHeader
            effectTitle
            factsRow
            if !adviceList.isEmpty {
                DS.Rule()
                    .padding(.vertical, 12)
                adviceSection
            }
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        // VoiceOver lit le texte d'origine : le découpage est une aide visuelle,
        // pas une réécriture. Rien ne doit se perdre pour un lecteur d'écran.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(digest.raw)
    }

    // MARK: - Bandeau de cause

    private var causeHeader: some View {
        HStack(spacing: 8) {
            Image(systemName: symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 22, height: 22)
                .background(tint.opacity(0.14))
                .clipShape(Circle())

            Text(digest.cause ?? AppLocalizer.string("disruption.network_info", defaultValue: "Info réseau"))
                .font(DS.Font.eyebrow)
                .textCase(.uppercase)   // majuscules APRÈS traduction
                .tracking(1.2)
                .foregroundStyle(DS.Color.inkMute)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            Spacer(minLength: 8)

            if let line, !line.isEmpty {
                LineBadge(line: line, size: .sm)
            }
        }
    }

    // MARK: - Effet : le titre

    private var effectTitle: some View {
        Text(digest.effect)
            .font(DS.Font.bodyBold)
            .foregroundStyle(DS.Color.ink)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.top, 10)
    }

    // MARK: - Faits : période + arrêt

    @ViewBuilder
    private var factsRow: some View {
        let facts: [(String, String)] = [
            digest.period.map { ("calendar", $0) },
            stopName.map { ("mappin.and.ellipse", $0) },
        ].compactMap { $0 }

        if !facts.isEmpty {
            // Les puces passent à la ligne : le néerlandais est plus long, et une
            // période comme « Du 27/4/26 à fin avril 2027 » ne tient pas à côté d'un
            // nom d'arrêt sur un iPhone étroit.
            FlowRow(spacing: 6) {
                ForEach(Array(facts.enumerated()), id: \.offset) { _, fact in
                    factChip(icon: fact.0, text: fact.1)
                }
            }
            .padding(.top, 10)
        }
    }

    private func factChip(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 9, weight: .semibold))
            // Pas de monospace ici : elle est réservée aux données TEMPS RÉEL
            // (minutes d'attente, compteurs). Une période de travaux n'en est pas une.
            Text(text)
                .font(DS.Font.caption)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .foregroundStyle(DS.Color.inkMute)
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(DS.Color.paper2)
        .clipShape(Capsule())
    }

    // MARK: - Conseil : la seule ligne actionnable

    @ViewBuilder
    private var adviceSection: some View {
        if adviceList.count > 1 {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text("ALTERNATIVES")
                        .font(DS.Font.labelSmall.weight(.heavy))
                        .tracking(1.4)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(AppLocalizer.format(
                        "disruption.merged_sources",
                        defaultValue: "d'après %lld communiqués",
                        sourceCount
                    ))
                    .font(DS.Font.labelSmall)
                    .foregroundStyle(DS.Color.inkMute.opacity(0.7))
                }
                ForEach(adviceList, id: \.self) { advice in
                    AdviceStrip(text: advice)
                }
            }
        } else if let only = adviceList.first {
            AdviceStrip(text: only)
        }
    }

    // MARK: - Habillage par famille

    private var symbolName: String {
        switch digest.kind {
        case .works: return "hammer.fill"
        case .event: return "calendar.badge.exclamationmark"
        case .interrupted: return "exclamationmark.triangle.fill"
        case .info: return "info.circle.fill"
        }
    }

    private var tint: Color {
        switch digest.kind {
        case .works: return DS.Color.statusMinor
        case .event: return DS.Color.community
        case .interrupted: return DS.Color.statusMajor
        case .info: return DS.Color.inkMute
        }
    }
}

/// Le bloc « quoi faire ». Partagé entre la carte de perturbation et l'alternative
/// d'itinéraire : c'est le même geste pour l'usager, il mérite le même habillage.
struct AdviceStrip: View {
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "arrow.turn.down.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Color.primary)
                .padding(.top, 1)

            Text(text)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .background(DS.Color.primary.opacity(0.07))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous))
    }
}

/// Disposition en lignes qui passent à la ligne quand la largeur manque.
/// SwiftUI n'offre pas de flow layout tout fait avant iOS 16 `Layout` ; celui-ci est
/// minimal et suffit pour deux ou trois puces.
struct FlowRow: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth == .infinity ? x : maxWidth, height: y + rowHeight)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
