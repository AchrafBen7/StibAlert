import Foundation
import Combine
import CoreLocation
import AVFoundation

/// Minimal speech synthesizer wrapper used by SearchGuidanceSession.
final class AVSpeechSynthesizerWrapper: NSObject, ObservableObject {
    private let synthesizer = AVSpeechSynthesizer()

    @Published private(set) var isSpeaking = false

    func speak(_ text: String) {
        synthesizer.stopSpeaking(at: .immediate)
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = AVSpeechSynthesisVoice(language: "fr-BE") ?? AVSpeechSynthesisVoice(language: "fr-FR")
        utterance.rate = 0.5
        isSpeaking = true
        synthesizer.speak(utterance)
    }

    func stop() {
        synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
    }
}

@MainActor
final class SearchGuidanceSession: ObservableObject {
    let guidance = GuidanceCoordinator()
    let speechSynthesizer = AVSpeechSynthesizerWrapper()
    @Published private(set) var rerouteRequestID = 0
    @Published private(set) var isRerouting = false

    private var cancellables = Set<AnyCancellable>()
    private var hasPendingOffRouteReroute = false

    init() {
        guidance.objectWillChange
            .sink { [weak self] _ in
                self?.objectWillChange.send()
            }
            .store(in: &cancellables)
    }

    func start(
        with alternative: SearchRouteAlternative,
        locationManager: SearchLocationManager,
        originName: String = "",
        destinationName: String = ""
    ) {
        guard !alternative.steps.isEmpty else { return }
        guidance.start(with: alternative)
        locationManager.startLiveTracking()
        hasPendingOffRouteReroute = false
        isRerouting = false
        replayCurrentStep()
        if #available(iOS 16.1, *) {
            JourneyActivityManager.shared.start(
                originName: originName,
                destinationName: destinationName,
                lineSummary: alternative.lineSummary,
                stepInstruction: guidance.currentStep?.instruction ?? alternative.title,
                arrivalMinutes: alternative.eta,
                currentLine: alternative.steps.first?.line
            )
        }
    }

    func stop(locationManager: SearchLocationManager) {
        guidance.stop()
        locationManager.stopLiveTracking()
        speechSynthesizer.stop()
        hasPendingOffRouteReroute = false
        isRerouting = false
        if #available(iOS 16.1, *) {
            JourneyActivityManager.shared.finish()
        }
    }

    func replayCurrentStep() {
        guard let currentStep = guidance.currentStep else { return }
        speechSynthesizer.speak(currentStep.instruction)
        if #available(iOS 16.1, *) {
            let remaining = guidance.activeAlternative?.eta ?? 0
            JourneyActivityManager.shared.update(
                stepInstruction: currentStep.instruction,
                arrivalMinutes: remaining,
                currentLine: currentStep.line
            )
        }
    }

    func goBack() {
        guidance.goBack()
        replayCurrentStep()
    }

    func advance() {
        guidance.advance()
        replayCurrentStep()
    }

    func handleLocationUpdate(_ location: CLLocation) {
        guard guidance.isGuiding else { return }
        let didAdvance = guidance.autoAdvanceIfNeeded(userLocation: location)
        if didAdvance {
            hasPendingOffRouteReroute = false
            replayCurrentStep()
            return
        }

        if guidance.offRouteUpdates >= 4 && !hasPendingOffRouteReroute {
            hasPendingOffRouteReroute = true
            isRerouting = true
            rerouteRequestID += 1
            speechSynthesizer.speak("Je recalcule une option plus fiable.")
        } else if guidance.offRouteUpdates == 0 {
            hasPendingOffRouteReroute = false
            isRerouting = false
        }
    }

    func consumeRerouteRequest() {
        hasPendingOffRouteReroute = false
        isRerouting = false
    }
}
