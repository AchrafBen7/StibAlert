import Foundation

/// Décompose le texte brut d'une perturbation officielle en informations utiles.
///
/// La STIB publie ses perturbations sous une forme très régulière :
///
///     <CAUSE>. <PÉRIODE>, <EFFET>. <CONSEIL>.
///     Travaux. Du 27/4/26 à fin avril 2027, bus 50 dévié. Pour continuer vers
///     GARE DU MIDI, prenez le bus 49.
///
/// Le néerlandais suit la même grammaire (« Werken. Van 27/4/26 tot eind april
/// 2027, bus 50 omgeleid. Om verder naar ZUIDSTATION te reizen, neem bus 49. »),
/// donc l'analyse est **structurelle** (dates, ponctuation) et non lexicale : elle
/// ne dépend pas de la langue, sauf pour les noms de mois.
///
/// L'app n'affichait que `raw` : un paragraphe entier en guise de titre. Ici, on
/// sépare ce qu'on subit (l'effet) de ce qu'on peut faire (le conseil).
struct DisruptionDigest: Equatable {
    /// « Travaux », « Werken », « Match coupe du monde ». Absent si le texte
    /// commence directement par l'effet.
    let cause: String?
    /// Ce qui change concrètement : « bus 50 dévié ». C'est le titre de la carte.
    let effect: String
    /// « Du 27/4/26 à fin avril 2027 ». Absent si la STIB ne date pas l'info.
    let period: String?
    /// « Pour continuer vers GARE DU MIDI, prenez le bus 49. » — la seule phrase
    /// qui dit à l'usager quoi faire. Absente sur les perturbations sèches.
    let advice: String?
    /// Le texte d'origine, conservé pour l'accessibilité et le « voir l'original ».
    let raw: String

    /// Famille de la perturbation, déduite de la cause. Sert à l'icône et à la teinte.
    enum Kind: Equatable {
        case works       // travaux / werken
        case event       // match, événement / wedstrijd, evenement
        case interrupted // interruption / onderbreking
        case info        // tout le reste
    }
    let kind: Kind
}

extension DisruptionDigest {

    // Un point qui TERMINE une phrase est précédé d'une lettre. Un point interne à
    // un nombre (« 16.30u ») est précédé d'un chiffre. Cette seule règle sépare
    // « Travaux.21/5/25 » (pas d'espace après le point) sans casser les heures.
    private static let sentenceSplit = try! NSRegularExpression(pattern: "(?<=[^0-9])\\.")

    /// Jetons temporels : dates, heures, années. Les noms de mois sont traités à part
    /// car « à fin août » ne contient aucun chiffre.
    private static let temporalToken = try! NSRegularExpression(
        pattern: "\\d{1,2}/\\d{1,2}(?:/\\d{2,4})?|\\d{1,2}\\s?[hu]\\d{0,2}\\b|\\d{1,2}[.:]\\d{2}\\s?u?\\b|\\b20\\d{2}\\b",
        options: [.caseInsensitive]
    )

    private static let monthNames: Set<String> = [
        // français
        "janvier", "février", "mars", "avril", "mai", "juin", "juillet",
        "août", "septembre", "octobre", "novembre", "décembre",
        // néerlandais
        "januari", "februari", "maart", "april", "mei", "juni", "juli",
        "augustus", "september", "oktober", "november", "december",
    ]

    /// Mots qui relient deux jetons temporels sans rompre la période :
    /// « Du 27/4 **à fin** avril 2027 », « Van 27/4 **tot eind** april 2027 ».
    private static let connectors: Set<String> = [
        "du", "de", "le", "la", "à", "a", "au", "en", "et", "jusqu'à", "jusqu",
        "fin", "mi", "début", "vers", "après", "avant", "dès", "entre",
        "van", "tot", "op", "na", "voor", "eind", "midden", "begin", "vanaf", "en",
    ]

    /// Analyse un texte brut. Ne jette jamais : au pire, tout part dans `effect`.
    static func parse(_ raw: String) -> DisruptionDigest {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // La STIB colle souvent la virgule au mot suivant (« 2027,halte niet bediend »).
        // On rétablit l'espace avant tout découpage en mots.
        let normalized = trimmed
            .replacingOccurrences(of: ",", with: ", ")
            .replacingOccurrences(of: "  ", with: " ")

        var sentences = splitSentences(normalized)
        guard !sentences.isEmpty else {
            return DisruptionDigest(cause: nil, effect: trimmed, period: nil,
                                    advice: nil, raw: raw, kind: .info)
        }

        // 1. La cause est la première phrase SI elle ne contient ni date ni virgule
        //    et reste courte. Sinon le texte attaque directement par la période.
        var cause: String?
        if let first = sentences.first,
           !containsTemporalToken(first),
           !first.contains(","),
           first.split(separator: " ").count <= 5 {
            cause = first
            sentences.removeFirst()
        }

        guard !sentences.isEmpty else {
            return DisruptionDigest(cause: nil, effect: cause ?? trimmed, period: nil,
                                    advice: nil, raw: raw, kind: kind(for: cause))
        }

        // 2. La phrase qui porte la période est la première à contenir un jeton temporel.
        var periodIndex = sentences.firstIndex(where: containsTemporalToken) ?? 0
        var (period, effect) = splitPeriodAndEffect(sentences[periodIndex])

        // 2b. Certains textes inversent l'ordre : « Jsq 2028, travaux. Dès le 6/6, T82
        //     remplace T97… ». Ce qui suit la période n'est alors pas l'effet mais la
        //     CAUSE. On la récupère et on cherche l'effet dans la phrase suivante.
        if cause == nil,
           kind(for: effect) != .info,
           effect.split(separator: " ").count <= 2,
           periodIndex + 1 < sentences.count {
            cause = effect
            periodIndex += 1
            let (nextPeriod, nextEffect) = splitPeriodAndEffect(sentences[periodIndex])
            period = [period, nextPeriod].compactMap { $0 }.joined(separator: " · ")
            effect = nextEffect
        }

        // 3. Tout ce qui suit dit quoi faire.
        let adviceSentences = sentences.enumerated()
            .filter { $0.offset > periodIndex }
            .map(\.element)
        let advice = adviceSentences.isEmpty
            ? nil
            : adviceSentences.joined(separator: ". ") + "."

        return DisruptionDigest(
            cause: cause,
            effect: effect.isEmpty ? trimmed : effect,
            period: (period?.isEmpty ?? true) ? nil : period,
            advice: advice,
            raw: raw,
            kind: kind(for: cause)
        )
    }

    // MARK: - Découpage

    private static func splitSentences(_ text: String) -> [String] {
        let ns = text as NSString
        var parts: [String] = []
        var start = 0
        sentenceSplit.enumerateMatches(in: text, range: NSRange(location: 0, length: ns.length)) { match, _, _ in
            guard let match else { return }
            let end = match.range.location
            let piece = ns.substring(with: NSRange(location: start, length: end - start))
            // Un point d'abréviation n'ouvre pas une phrase : « CARR. STALLE »,
            // « arrêt: r. Stalle ». Signature : le dernier mot est très court et
            // soit tout en majuscules, soit une unique lettre minuscule.
            if let lastWord = piece.split(separator: " ").last, isAbbreviation(String(lastWord)) {
                return
            }
            parts.append(piece)
            start = match.range.location + match.range.length
        }
        if start < ns.length { parts.append(ns.substring(from: start)) }
        return parts
            // Le point FINAL du texte est précédé d'un chiffre (« … bus 49. ») : il
            // n'ouvre pas de nouvelle phrase, donc il reste collé. On le retire ici,
            // sinon la reconstruction du conseil produisait « bus 49.. ».
            .map { $0.trimmingCharacters(in: CharacterSet(charactersIn: " \n\t.")) }
            .filter { !$0.isEmpty }
    }

    /// « CARR », « r », « Bd » : un point qui suit ne termine pas une phrase.
    private static func isAbbreviation(_ word: String) -> Bool {
        let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: "(),;:"))
        guard !bare.isEmpty, bare.count <= 4, bare.allSatisfy(\.isLetter) else { return false }
        return bare.count == 1 || bare == bare.uppercased()
    }

    private static func containsTemporalToken(_ text: String) -> Bool {
        let ns = text as NSString
        if temporalToken.firstMatch(in: text, range: NSRange(location: 0, length: ns.length)) != nil {
            return true
        }
        return text.lowercased().split(whereSeparator: { !$0.isLetter }).contains { monthNames.contains(String($0)) }
    }

    /// Sépare « Du 27/4/26 à fin avril 2027, bus 50 dévié » en période + effet.
    ///
    /// On étend la période tant que les mots rencontrés sont des jetons temporels,
    /// des mois ou des connecteurs. Le premier mot « réel » ouvre l'effet. La virgule
    /// n'est qu'un indice : le néerlandais s'en passe souvent (« Op 10/7 na 16.30u
    /// rijdt tram 39 … »).
    private static func splitPeriodAndEffect(_ sentence: String) -> (String?, String) {
        let words = sentence.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard !words.isEmpty else { return (nil, sentence) }

        var lastTemporalIndex = -1
        for (index, word) in words.enumerated() {
            let bare = word.trimmingCharacters(in: CharacterSet(charactersIn: ",.;:()"))
            let lower = bare.lowercased()
            if isTemporal(bare) || monthNames.contains(lower) {
                lastTemporalIndex = index
            } else if connectors.contains(lower) || lower.hasPrefix("mi-") || lower.hasPrefix("midden") {
                continue   // connecteur : on ne rompt pas, mais il ne prolonge pas seul
            } else if lastTemporalIndex >= 0 {
                break      // premier mot réel après la période
            }
        }
        guard lastTemporalIndex >= 0 else { return (nil, sentence) }

        let period = words[0...lastTemporalIndex].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        let effect = words[(lastTemporalIndex + 1)...].joined(separator: " ")
            .trimmingCharacters(in: CharacterSet(charactersIn: " ,"))
        return (period.isEmpty ? nil : period, effect)
    }

    /// Un mot est « temporel » s'il ne contient que des jetons temporels, des mois et
    /// des connecteurs. Exiger que le mot ENTIER soit un jeton échouait sur les formes
    /// composées bien réelles : « 21/5/25-mi-2027 », « 8/6-30/8 », « 21/5/25-midden ».
    private static func isTemporal(_ word: String) -> Bool {
        let ns = word as NSString
        let hasToken = temporalToken.firstMatch(in: word, range: NSRange(location: 0, length: ns.length)) != nil
        let letterRuns = word.lowercased()
            .split(whereSeparator: { !$0.isLetter })
            .map(String.init)
        let onlyKnownWords = letterRuns.allSatisfy { run in
            monthNames.contains(run) || connectors.contains(run) || run == "h" || run == "u"
        }
        let hasMonth = letterRuns.contains { monthNames.contains($0) }
        return (hasToken || hasMonth) && onlyKnownWords
    }

    private static func kind(for cause: String?) -> Kind {
        guard let value = cause?.lowercased() else { return .info }
        if value.contains("travaux") || value.contains("werken") { return .works }
        if value.contains("match") || value.contains("wedstrijd")
            || value.contains("événement") || value.contains("evenement") { return .event }
        if value.contains("interruption") || value.contains("onderbreking")
            || value.contains("interrompu") || value.contains("onderbroken") { return .interrupted }
        return .info
    }
}
