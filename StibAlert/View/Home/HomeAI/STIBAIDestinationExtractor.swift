import Foundation

/// Client-side regex extractor : finds a destination string in free-form user
/// text without hitting the backend. Used as the FAST PATH by both STIB·AI
/// (typed chat) and STIB·Micro (voice) — if it matches, we skip the extra AI
/// extraction round-trip and go straight to geocoding + planning.
///
/// When this returns nil, the caller falls back to a JSON backend extraction
/// (Gemini, more tolerant of phrasing). The regex covers ~80 % of typical
/// queries ("aller à X", "trajet pour X", "comment je vais à X", "meilleur
/// trajet pour X"), the backend covers the rest.
///
/// Output is post-processed via `cutAtPunctuation` + `cutAtTransition` so the
/// destination doesn't drag in interrogative/continuation text ("delacroix c
/// est quoi la meilleure route" → "delacroix").
enum STIBAIDestinationExtractor {
    static func extract(from text: String) -> String? {
        let cleaned = text
            .replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard cleaned.count >= 4 else { return nil }

        let patterns = [
            // "aller à X" / "trajet à X" / "route à X" (verbe/nom + préposition directe)
            #"(?i)(?:aller|vais|va|trajet|itin[eé]raire|route)\s+(?:à|a|au|aux|vers|jusqu['’]à|jusqu a)\s+(.+)"#,
            // "trajet/route/itinéraire/chemin pour [aller/arriver/me rendre/y aller] [à/au/vers/chez] X"
            // — couvre "route pour arriver a delacroix", "trajet pour aller à Schaerbeek",
            //   "itinéraire pour me rendre au Sablon", "chemin pour Atomium"
            #"(?i)\b(?:trajet|itin[eé]raire|route|chemin)\s+pour\s+(?:(?:aller|arriver|me\s+rendre|se\s+rendre|y\s+aller)\s+)?(?:[àa]\s+|au\s+|aux\s+|vers\s+|chez\s+)?(.+)"#,
            // "comment aller / comment arriver / comment je peux aller / comment faire pour aller à X"
            #"(?i)comment\s+(?:(?:je\s+(?:peux|pourrais|fais))\s+)?(?:aller|arriver|faire\s+pour\s+(?:aller|arriver))\s+(?:à|a|au|aux|vers|chez)?\s*(.+)"#,
            // "(le )?meilleur (trajet/route/...) (pour|vers) X"
            #"(?i)(?:le\s+|la\s+)?meilleur(?:e)?\s+(?:trajet|itin[eé]raire|route|chemin)\s+(?:pour\s+(?:aller\s+|arriver\s+)?|vers\s+|à\s+)?(?:à|a|au|aux|vers|chez)?\s*(.+)"#,
            #"(?i)(?:comment\s+aller\s+)(?:à|a|au|aux|vers)?\s*(.+)"#,
            #"(?i)(?:destination\s*:)\s*(.+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, range: range),
                  match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: cleaned) else { continue }
            if let destination = normalize(String(cleaned[matchRange])) {
                return destination
            }
        }

        return nil
    }

    private static func normalize(_ raw: String) -> String? {
        var candidate = raw
            .replacingOccurrences(of: #"["“”]"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)

        candidate = cutAtPunctuation(candidate)
        candidate = cutAtTransition(candidate)
        candidate = candidate
            .replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
            .trimmingCharacters(in: CharacterSet.whitespacesAndNewlines.union(.punctuationCharacters))

        guard candidate.count >= 3 else { return nil }
        return String(candidate.prefix(90))
    }

    private static func cutAtPunctuation(_ text: String) -> String {
        let separators = [",", ".", "?", "!", ";", ":"]
        let firstSeparator = separators
            .compactMap { separator in text.range(of: separator)?.lowerBound }
            .min()
        guard let index = firstSeparator else { return text }
        return String(text[..<index])
    }

    private static func cutAtTransition(_ text: String) -> String {
        let transitions = [
            " problème", " problèmes", " souci", " soucis",
            " avec la route", " la route", " le trajet", " mon trajet",
            " est-ce", " est ce", " y a-t-il", " y a t il",
            " ça va", " ca va", " c'est bon", " cest bon",
            " c est bon", " c’est bon", " possible", " dangereux",
            " perturbé", " perturbée", " retard", " bloqué", " bloquée",
            // Sentence-continuation / interrogative markers — sans ça l'extracteur
            // ramène "delacroix c est quoi la meilleure route" et MKLocalSearch
            // matche n'importe quel mot (ex: trouve "Rue de la Croix de Fer" sur
            // "croix") au lieu de l'arrêt Delacroix.
            " c est ", " c'est ", " c’est ", " ça ", " ca ",
            " quoi", " que ", " qui ", " comment ",
            " pourquoi ", " quand ", " où ",
            " peux ", " peux-tu", " peut-on", " pourrais ", " pourriez ",
            " stp", " svp", " merci", " s'il te plait", " s il te plait", " s'il vous plaît"
        ]
        let lower = text.lowercased()
        let firstTransition = transitions
            .compactMap { marker -> String.Index? in
                lower.range(of: marker)?.lowerBound
            }
            .min()
        guard let lowerIndex = firstTransition,
              let index = String.Index(lowerIndex, within: text) else { return text }
        return String(text[..<index])
    }
}
