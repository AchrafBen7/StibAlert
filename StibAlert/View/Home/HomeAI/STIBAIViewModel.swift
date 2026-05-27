import Foundation

@MainActor
final class STIBAIViewModel: ObservableObject {
    @Published var messages: [STIBAIMessage] = []
    @Published var input = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?

    let quickPrompts = [
        "Y a-t-il des perturbations en ce moment ?",
        "Mon trajet est-il à risque ?",
        "Quelle alternative si ma ligne est bloquée ?",
        "Que se passe-t-il autour de moi ?"
    ]

    private let client: STIBAIClient
    private let contextProvider: @MainActor (_ userMessage: String) async -> STIBAIContext
    private var streamTask: Task<Void, Never>?

    init(
        client: STIBAIClient = STIBAIClient(),
        contextProvider: @escaping @MainActor (_ userMessage: String) async -> STIBAIContext
    ) {
        self.client = client
        self.contextProvider = contextProvider
    }

    func send(_ text: String? = nil) {
        let content = (text ?? input).trimmingCharacters(in: .whitespacesAndNewlines)
        guard !content.isEmpty, !isStreaming else { return }

        errorMessage = nil
        input = ""
        messages.append(STIBAIMessage(role: .user, content: content))

        let assistantID = UUID()
        messages.append(STIBAIMessage(id: assistantID, role: .assistant, content: ""))
        isStreaming = true

        let outbound = messages
            .filter { !$0.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .suffix(12)

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
                // Send the last 3 user messages joined as one "extraction
                // string" so the destination extractor can pick up a
                // destination mentioned in a previous turn (e.g. user says
                // "Je voudrais le trajet vers Delacroix" then "Oui station"
                // — without this, "Oui station" alone has no destination so
                // proposedRoutes never gets computed and the AI keeps
                // refusing with "veuillez utiliser le planner").
                let recentUserText = self.messages
                    .filter { $0.role == .user }
                    .suffix(3)
                    .map(\.content)
                    .joined(separator: " ")
                let context = await self.contextProvider(recentUserText)
                try await client.stream(messages: Array(outbound), context: context) { delta in
                    guard let index = self.messages.firstIndex(where: { $0.id == assistantID }) else { return }
                    self.messages[index].content += delta
                }
            } catch {
                guard !Task.isCancelled else { return }
                self.errorMessage = (error as? LocalizedError)?.errorDescription ?? "Assistant indisponible."
                if let index = self.messages.firstIndex(where: { $0.id == assistantID }),
                   self.messages[index].content.isEmpty {
                    self.messages[index].content = self.errorMessage ?? "Assistant indisponible."
                }
            }
            self.isStreaming = false
        }
    }

    func cancel() {
        streamTask?.cancel()
        streamTask = nil
        isStreaming = false
    }
}

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
            " perturbé", " perturbée", " retard", " bloqué", " bloquée"
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
