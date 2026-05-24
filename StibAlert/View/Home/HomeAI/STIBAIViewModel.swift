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
    private let contextProvider: () -> STIBAIContext
    private var streamTask: Task<Void, Never>?

    init(client: STIBAIClient = STIBAIClient(), contextProvider: @escaping () -> STIBAIContext) {
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
        var context = contextProvider()
        if context.proposedDestination == nil,
           let destination = STIBAIDestinationExtractor.extract(from: content) {
            context.proposedDestination = destination
        }

        streamTask = Task { [weak self] in
            guard let self else { return }
            do {
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
            #"(?i)(?:aller|vais|va|trajet|itin[eé]raire|route)\s+(?:à|a|au|aux|vers|jusqu['’]à|jusqu a)\s+(.+)"#,
            #"(?i)(?:comment\s+aller\s+)(?:à|a|au|aux|vers)?\s*(.+)"#,
            #"(?i)(?:destination\s*:)\s*(.+)"#
        ]

        for pattern in patterns {
            guard let regex = try? NSRegularExpression(pattern: pattern) else { continue }
            let range = NSRange(cleaned.startIndex..<cleaned.endIndex, in: cleaned)
            guard let match = regex.firstMatch(in: cleaned, range: range),
                  match.numberOfRanges > 1,
                  let matchRange = Range(match.range(at: 1), in: cleaned) else { continue }
            let candidate = String(cleaned[matchRange])
                .replacingOccurrences(of: "?", with: "")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            if candidate.count >= 3 { return String(candidate.prefix(120)) }
        }

        return nil
    }
}
