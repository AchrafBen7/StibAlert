import Foundation
import AVFoundation

@MainActor
final class StibiSpeechSynthesizer: NSObject, ObservableObject {
    @Published private(set) var isSpeaking = false

    private let synthesizer = AVSpeechSynthesizer()

    override init() {
        super.init()
        synthesizer.delegate = self
    }

    func speak(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        stop()
        enqueue(trimmed)
    }

    func speak(brief: AssistantBriefDTO) {
        if brief.type == "guide",
           let steps = brief.supporting?.recommendedAlternatives?.first?.steps,
           !steps.isEmpty {
            speak(routeSteps: steps)
            return
        }
        speak(AssistantViewAdapters.spokenText(for: brief))
    }

    func speak(routeSteps: [TransportRouteStepDTO]) {
        let instructions = routeSteps
            .sorted { $0.order < $1.order }
            .map(\.instruction)
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        guard !instructions.isEmpty else { return }
        stop()
        instructions.forEach(enqueue)
    }

    func stop() {
        if synthesizer.isSpeaking {
            synthesizer.stopSpeaking(at: .immediate)
        }
        isSpeaking = false
    }

    private func enqueue(_ text: String) {
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-BE")
        utterance.rate = 0.46
        utterance.pitchMultiplier = 0.96
        utterance.volume = 0.85
        synthesizer.speak(utterance)
    }
}

extension StibiSpeechSynthesizer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = true
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in
            self.isSpeaking = false
        }
    }
}
