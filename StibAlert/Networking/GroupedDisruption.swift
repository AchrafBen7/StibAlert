import Foundation

/// Une perturbation, pas un communiqué.
///
/// La STIB publie **un communiqué par conseil**, pas par perturbation. Vérifié sur
/// les données réelles :
///
///     « Travaux. 8/6-30/8, tram 92 interrompu. Prenez le T-bus vers SCHAERBEEK
///       GARE à l'arrêt du bus 65 vers MACHELEN. »
///     « Travaux. 8/6-30/8, tram 92 interrompu jusqu'à SAINTE-MARIE. T-bus vers
///       PARC à l'arrêt du bus 56 vers BUDA. »
///
/// C'est **une** interruption (tram 92, 8/6→30/8) avec **deux** alternatives selon
/// où tu te trouves. Affichée en deux cartes, elle se lit comme un copié-collé, et
/// noie le fait qu'il n'y a qu'un seul problème.
///
/// Ici on regroupe sur (ligne + effet + période) — c'est-à-dire « le même problème,
/// au même endroit, aux mêmes dates » — et les conseils deviennent la liste
/// d'alternatives. Le découpage vient de `DisruptionDigest` : pas de second analyseur.
struct GroupedDisruption: Identifiable {
    let id: String
    let digest: DisruptionDigest
    let line: String?
    /// Les arrêts nommés par les communiqués regroupés (« Abbaye », « Legrand »).
    let stopNames: [String]
    /// Un conseil par communiqué, dédupliqué. Vide = perturbation sèche, sans issue.
    let alternatives: [String]
    /// Combien de communiqués ce groupe absorbe. 1 = pas de regroupement.
    let sourceCount: Int

    var isGrouped: Bool { sourceCount > 1 }
}

extension GroupedDisruption {

    /// Deux communiqués décrivent la même perturbation s'ils partagent la ligne,
    /// l'effet et la période. On normalise avant de comparer : la STIB écrit
    /// « tram 92 interrompu » et « tram 92 interrompu jusqu'à SAINTE-MARIE » — même
    /// interruption, précision d'étendue en plus. On coupe donc l'effet à sa partie
    /// stable (avant « jusqu'à » / « entre » / « tot » / « tussen ») pour que les
    /// deux tombent dans le même groupe.
    private static func groupingKey(line: String?, digest: DisruptionDigest) -> String {
        var effect = digest.effect.lowercased()
        for cut in [" jusqu'à", " jusqu'au", " entre ", " tot ", " tussen "] {
            if let range = effect.range(of: cut) {
                effect = String(effect[..<range.lowerBound])
            }
        }
        effect = effect.trimmingCharacters(in: .whitespacesAndNewlines)
        let period = digest.period?.lowercased() ?? ""
        return "\(line?.uppercased() ?? "")|\(effect)|\(period)"
    }

    /// Regroupe une liste d'incidents officiels. L'ordre d'origine est préservé
    /// (premier vu = premier affiché) : on ne réordonne pas ce que la STIB a priorisé.
    static func group(_ incidents: [TransportIncidentDTO]) -> [GroupedDisruption] {
        var order: [String] = []
        var buckets: [String: [(incident: TransportIncidentDTO, digest: DisruptionDigest)]] = [:]

        for incident in incidents {
            let text = incident.localizedDescription ?? incident.localizedType ?? ""
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
            let digest = DisruptionDigest.parse(text)
            let key = groupingKey(line: incident.line, digest: digest)
            if buckets[key] == nil { order.append(key) }
            buckets[key, default: []].append((incident, digest))
        }

        return order.compactMap { key -> GroupedDisruption? in
            guard let bucket = buckets[key], let first = bucket.first else { return nil }

            // On garde le digest le plus COMPLET comme référence : celui qui porte
            // une période, sinon le premier. Sinon un groupe peut hériter d'un
            // communiqué sans dates alors qu'un autre les donnait.
            let reference = bucket.first(where: { $0.digest.period != nil })?.digest ?? first.digest

            var seenAdvice = Set<String>()
            let alternatives = bucket.compactMap { pair -> String? in
                guard let advice = pair.digest.advice?.trimmingCharacters(in: .whitespacesAndNewlines),
                      !advice.isEmpty else { return nil }
                // Deux communiqués peuvent donner le même conseil mot pour mot.
                let normalized = advice.lowercased()
                guard !seenAdvice.contains(normalized) else { return nil }
                seenAdvice.insert(normalized)
                return advice
            }

            var seenStops = Set<String>()
            let stopNames = bucket.compactMap { pair -> String? in
                guard let name = pair.incident.stop?.name, !name.isEmpty else { return nil }
                guard !seenStops.contains(name.uppercased()) else { return nil }
                seenStops.insert(name.uppercased())
                return name
            }

            return GroupedDisruption(
                id: bucket.map(\.incident.id).joined(separator: "+"),
                digest: reference,
                line: first.incident.line,
                stopNames: stopNames,
                alternatives: alternatives,
                sourceCount: bucket.count
            )
        }
    }
}
