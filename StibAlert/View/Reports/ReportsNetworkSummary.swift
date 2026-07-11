import SwiftUI

/// Synthèse « En ce moment » — la première chose qu'on lit en ouvrant Alertes.
///
/// Avant, l'écran s'ouvrait directement sur la grille des ~40 lignes : il fallait
/// scanner 40 pastilles pour se faire une idée. Or la question qu'on se pose en
/// ouvrant cet onglet n'est pas « quelle est la pastille de la ligne 8 ? », c'est
/// « est-ce que le réseau va bien, là, maintenant ? ». La grille répond à la
/// première ; cette carte répond à la seconde, et la grille devient le détail.
///
/// Les compteurs réutilisent **exactement** la classification de `LineIncidentBadge`
/// (la grille, juste en dessous) : un incident compté 🔨 ici porte un badge 🔨 là.
/// Deux classifications = deux vérités sur le même écran.
struct ReportsNetworkSummary: View {
    let incidents: [TransportIncidentDTO]

    private struct Tally {
        /// Lignes dont le service est réellement COUPÉ. Pas « lignes citées dans un
        /// communiqué » : la STIB publie des travaux qui courent jusqu'en 2027, et
        /// les compter comme « perturbées en ce moment » badgeait 38 lignes sur ~50.
        /// Un écran où tout est rouge n'informe plus, il affole.
        var blockedLines = 0
        var works = 0
        var delays = 0
        var community = 0
        var isCalm: Bool { blockedLines == 0 }
        var hasAnything: Bool { blockedLines + works + delays + community > 0 }
    }

    private var tally: Tally {
        var t = Tally()
        var blocked = Set<String>()

        for incident in incidents {
            let badge = LineIncidentBadge(severity: incident.severity ?? "", type: incident.type ?? "")

            // Une LIGNE coupée, pas un incident : 3 communiqués sur la ligne 8
            // restent une seule ligne coupée. C'est la question de l'utilisateur.
            if badge.isBlocking,
               let line = incident.line?.trimmingCharacters(in: .whitespaces), !line.isEmpty {
                blocked.insert(line)
            }

            // ⚠️ Les signalements communauté arrivent ici SYNTHÉTISÉS
            // (`syntheticIncidentsFromCommunityReports`) : `source == "community"`
            // mais `community == nil`. Tester `community != nil` renvoyait donc
            // toujours 0 — la puce ne s'affichait jamais. C'est `source` qui décide.
            if incident.isCommunitySourced { t.community += 1 }

            switch badge.icon {
            case "hammer.fill": t.works += 1
            case "clock.fill":  t.delays += 1
            default: break
            }
        }
        t.blockedLines = blocked.count
        return t
    }

    var body: some View {
        let t = tally

        VStack(alignment: .leading, spacing: 12) {
            Text("EN CE MOMENT")
                .font(DS.Font.labelSmall.weight(.heavy))
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)

            if t.isCalm {
                // Le verdict rassurant reste un VERDICT : « rien de coupé » ne veut pas
                // dire « rien du tout ». Les travaux et les signalements restent visibles
                // juste en dessous, sans faire peur.
                HStack(spacing: 10) {
                    Image(systemName: "checkmark.seal.fill")
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundStyle(DS.Color.statusOK)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rien d'interrompu")
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                        Text(t.hasAnything
                             ? "Aucune ligne coupée. Détail ci-dessous."
                             : "Aucune perturbation en cours.")
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("\(t.blockedLines)")
                        .font(DesignSystem.Typography.display)
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.statusMajor)
                    // Pas de variante de pluriel ici : Xcode l'interdit sur une chaîne
                    // sans spécificateur numérique, et le nombre est rendu à part (en
                    // gros). Deux clés, l'accord se fait en Swift. FR et NL ont la même
                    // règle one/other, donc c'est exact dans les deux langues.
                    Text(t.blockedLines == 1
                         ? AppLocalizer.string("reports.summary.blocked_line_one", defaultValue: "ligne interrompue")
                         : AppLocalizer.string("reports.summary.blocked_lines_other", defaultValue: "lignes interrompues"))
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                }
            }

            // Le détail ne s'affiche que s'il ajoute quelque chose : une puce
            // « 0 travaux » est du bruit. Affiché dans les deux cas — les travaux
            // existent même quand rien n'est coupé.
            let chips = breakdownChips(t)
            if !chips.isEmpty {
                HStack(spacing: 8) {
                    ForEach(chips, id: \.label) { chip in
                        HStack(spacing: 5) {
                            Image(systemName: chip.icon)
                                .font(.system(size: 10, weight: .bold))
                            Text(chip.label)
                                .font(DS.Font.caption.weight(.semibold))
                                .monospacedDigit()
                        }
                        .foregroundStyle(chip.tint)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(chip.tint.opacity(0.1))
                        .clipShape(Capsule())
                    }
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }

    private struct Chip {
        let icon: String
        let label: String
        let tint: Color
    }

    private func breakdownChips(_ t: Tally) -> [Chip] {
        var chips: [Chip] = []
        if t.works > 0 {
            chips.append(Chip(
                icon: "hammer.fill",
                label: AppLocalizer.format("plural.works", defaultValue: "%lld travaux", t.works),
                tint: DS.Color.statusMinor
            ))
        }
        if t.delays > 0 {
            chips.append(Chip(
                icon: "clock.fill",
                label: AppLocalizer.format("plural.delays", defaultValue: "%lld retards", t.delays),
                tint: DS.Color.statusMinor
            ))
        }
        if t.community > 0 {
            chips.append(Chip(
                icon: "person.2.fill",
                label: AppLocalizer.format("plural.community_reports", defaultValue: "%lld signalements", t.community),
                tint: DS.Color.community
            ))
        }
        return chips
    }
}
