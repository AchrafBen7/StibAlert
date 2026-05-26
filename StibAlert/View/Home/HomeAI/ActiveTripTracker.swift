import CoreLocation
import Foundation

/// Speaks turn-by-turn announcements while a trip is active: an initial
/// "itinéraire démarré" line, a "descends à X et prends la ligne Y" at each
/// transit-stop checkpoint, and a "tu es arrivé" at the end. Driven by the
/// route's backend steps + a stream of user location updates from HomeView.
@MainActor
final class ActiveTripTracker: ObservableObject {
    @Published private(set) var isActive = false

    private struct Checkpoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let triggerDistance: CLLocationDistance
        let announcement: String
    }

    private let player = VoicePlayer()
    private var checkpoints: [Checkpoint] = []
    private var announced: Set<String> = []
    private var lastTriggerAt: Date = .distantPast
    /// Once active, only announce when the user has actually moved a bit —
    /// avoids the tracker firing all checkpoints at once if the trip starts
    /// already very close to the next stop.
    private var startCoordinate: CLLocationCoordinate2D?

    func start(option: HomeRouteOption) {
        stop()
        let steps = (option.backendAlternative?.steps ?? []).sorted { $0.order < $1.order }
        checkpoints = Self.buildCheckpoints(from: steps)
        guard !checkpoints.isEmpty else { return }
        isActive = true
        player.speak(Self.initialAnnouncement(option: option))
    }

    func stop() {
        isActive = false
        checkpoints = []
        announced = []
        startCoordinate = nil
        player.stop()
    }

    func onLocationUpdate(_ coord: CLLocationCoordinate2D?) {
        guard let coord, isActive, !checkpoints.isEmpty else { return }
        if startCoordinate == nil { startCoordinate = coord }
        // Throttle: at most one announcement every 6s.
        guard Date().timeIntervalSince(lastTriggerAt) > 6 else { return }

        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        for cp in checkpoints where !announced.contains(cp.id) {
            let cpLoc = CLLocation(latitude: cp.coordinate.latitude, longitude: cp.coordinate.longitude)
            let dist = userLoc.distance(from: cpLoc)
            if dist <= cp.triggerDistance {
                announced.insert(cp.id)
                lastTriggerAt = Date()
                player.speak(cp.announcement)
                // If we've announced the final arrival, the trip is done.
                if cp.id == "final" {
                    isActive = false
                }
                return
            }
        }
    }

    // MARK: - Helpers

    private static func buildCheckpoints(from steps: [TransportRouteStepDTO]) -> [Checkpoint] {
        var out: [Checkpoint] = []
        for (index, step) in steps.enumerated() {
            let isLast = index == steps.count - 1
            guard let lat = step.targetLatitude, let lng = step.targetLongitude else { continue }
            let coord = CLLocationCoordinate2D(latitude: lat, longitude: lng)
            if isLast {
                out.append(Checkpoint(
                    id: "final",
                    coordinate: coord,
                    triggerDistance: 90,
                    announcement: "Tu es arrivé à destination."
                ))
            } else if step.mode.lowercased() != "walking" {
                let stopName = step.arrivalStopName ?? step.stopName ?? "ton arrêt"
                let nextStep = index + 1 < steps.count ? steps[index + 1] : nil
                let nextLine = nextStep?.line
                let nextIsTransit = (nextStep?.mode.lowercased() ?? "walking") != "walking"
                let announcement: String
                if nextIsTransit, let nextLine, !nextLine.isEmpty {
                    announcement = "Descends à \(stopName) et prends la ligne \(nextLine)."
                } else if nextStep?.mode.lowercased() == "walking" {
                    announcement = "Descends à \(stopName), ensuite tu marches."
                } else {
                    announcement = "Prochain arrêt : \(stopName)."
                }
                out.append(Checkpoint(
                    id: "step-\(step.order)",
                    coordinate: coord,
                    triggerDistance: 150,
                    announcement: announcement
                ))
            }
        }
        return out
    }

    private static func initialAnnouncement(option: HomeRouteOption) -> String {
        let mins = option.totalDurationMinutes
        let dest = option.destinationName
        let firstLine: String? = {
            for chip in option.legChips {
                if case .line(let code) = chip { return code }
            }
            return nil
        }()
        if let firstLine {
            return "Itinéraire vers \(dest) démarré. Environ \(mins) minutes. Prends la ligne \(firstLine)."
        }
        return "Itinéraire vers \(dest) démarré. Environ \(mins) minutes."
    }
}
