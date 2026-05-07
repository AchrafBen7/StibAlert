import Foundation

@MainActor
final class SearchCoordinator: ObservableObject {
    private var lastLiveGuidanceRefreshAt: Date?

    func applySuggestion(
        _ suggestion: SearchPlaceSuggestion,
        autocompleteManager: SearchAutocompleteManager,
        state: SearchViewState
    ) {
        state.isResolvingSuggestion = true

        Task {
            do {
                let place = try await autocompleteManager.resolve(suggestion)
                await MainActor.run {
                    state.applySelection(place)
                    state.isResolvingSuggestion = false
                }
            } catch {
                await MainActor.run {
                    state.isResolvingSuggestion = false
                }
            }
        }
    }

    func rebuildJourney(
        state: SearchViewState,
        effectiveOrigin: SearchPlace,
        guidance: GuidanceCoordinator,
        speechSynthesizer: AVSpeechSynthesizerWrapper,
        showLoading: Bool = true
    ) async {
        guard let destination = state.destination, destination.id != effectiveOrigin.id else {
            state.resetJourneyState()
            guidance.stop()
            return
        }

        if showLoading {
            state.isLoadingRoute = true
            state.routeNote = nil
        }

        let result = await SearchJourneyBuilder.build(
            origin: effectiveOrigin,
            destination: destination
        )

        state.applyBuildResult(result)
        let didReroute = guidance.refresh(using: result.journey.alternatives)
        if didReroute, let currentStep = guidance.currentStep {
            speechSynthesizer.speak(currentStep.instruction)
        }
    }

    func runGuidanceRefreshLoop(
        state: SearchViewState,
        effectiveOrigin: SearchPlace,
        guidance: GuidanceCoordinator,
        speechSynthesizer: AVSpeechSynthesizerWrapper
    ) async {
        guard guidance.isGuiding else { return }
        while guidance.isGuiding && !Task.isCancelled {
            try? await Task.sleep(nanoseconds: 45_000_000_000)
            guard guidance.isGuiding, !Task.isCancelled else { return }
            await rebuildJourney(
                state: state,
                effectiveOrigin: effectiveOrigin,
                guidance: guidance,
                speechSynthesizer: speechSynthesizer,
                showLoading: false
            )
        }
    }

    func handleGuidanceSignalement(
        _ signalement: SignalementDTO,
        state: SearchViewState,
        guidance: GuidanceCoordinator,
        effectiveOrigin: SearchPlace,
        speechSynthesizer: AVSpeechSynthesizerWrapper
    ) async {
        guard guidance.isGuiding else { return }

        let now = Date()
        if let lastRefresh = lastLiveGuidanceRefreshAt,
           now.timeIntervalSince(lastRefresh) < 20 {
            return
        }

        let activeLine = guidance.activeAlternative?.steps
            .compactMap(\.line)
            .first
        let isRelevant = activeLine == nil || signalement.ligne.localizedCaseInsensitiveContains(activeLine ?? "")
        guard isRelevant else { return }

        lastLiveGuidanceRefreshAt = now
        await rebuildJourney(
            state: state,
            effectiveOrigin: effectiveOrigin,
            guidance: guidance,
            speechSynthesizer: speechSynthesizer,
            showLoading: false
        )
    }

    func resetLiveRefreshThrottle() {
        lastLiveGuidanceRefreshAt = nil
    }
}
