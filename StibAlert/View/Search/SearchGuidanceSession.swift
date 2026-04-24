import Foundation
import Combine
import CoreLocation

@MainActor
final class SearchGuidanceSession: ObservableObject {
    let guidance = GuidanceCoordinator()
    let speechSynthesizer = StibiSpeechSynthesizer()
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

    func start(with alternative: SearchRouteAlternative, locationManager: SearchLocationManager) {
        guard !alternative.steps.isEmpty else { return }
        guidance.start(with: alternative)
        locationManager.startLiveTracking()
        hasPendingOffRouteReroute = false
        isRerouting = false
        replayCurrentStep()
    }

    func stop(locationManager: SearchLocationManager) {
        guidance.stop()
        locationManager.stopLiveTracking()
        speechSynthesizer.stop()
        hasPendingOffRouteReroute = false
        isRerouting = false
    }

    func replayCurrentStep() {
        guard let currentStep = guidance.currentStep else { return }
        speechSynthesizer.speak(currentStep.instruction)
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
