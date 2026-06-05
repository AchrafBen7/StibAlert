import Foundation

@MainActor
final class STIBAIViewModel: ObservableObject {
    @Published var messages: [STIBAIMessage] = []
    @Published var input = ""
    @Published var isStreaming = false
    @Published var errorMessage: String?

    // Suggestions localisées (avant : codées en dur en français → elles
    // apparaissaient en FR même dans une app en NL). Computed pour suivre la
    // langue de l'app à chaque ouverture du chat.
    var quickPrompts: [String] {
        [
            AppLocalizer.string("stibai.prompt.disruptions", defaultValue: "Y a-t-il des perturbations en ce moment ?"),
            AppLocalizer.string("stibai.prompt.risk", defaultValue: "Mon trajet est-il à risque ?"),
            AppLocalizer.string("stibai.prompt.alternative", defaultValue: "Quelle alternative si ma ligne est bloquée ?"),
            AppLocalizer.string("stibai.prompt.around", defaultValue: "Que se passe-t-il autour de moi ?")
        ]
    }

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

// STIBAIDestinationExtractor (regex fast path) was moved to its own file
// — see STIBAIDestinationExtractor.swift
