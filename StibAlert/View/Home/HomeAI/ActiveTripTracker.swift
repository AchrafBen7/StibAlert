import CoreLocation
import Foundation

/// Tracks turn-by-turn checkpoints while a trip is active. Announcements are
/// kept as readable UI text only; automatic voice guidance is intentionally
/// disabled so selecting a route never starts talking on its own.
@MainActor
final class ActiveTripTracker: ObservableObject {
    @Published private(set) var isActive = false
    /// Métadonnées du trip courant — utilisées par ActiveTripIndicatorView
    /// pour afficher destination + durée + prochaine instruction.
    @Published private(set) var summary: ActiveTripSummary?
    /// Dernière annonce vocale entendue. Affichée comme sous-titre pour que
    /// l'utilisateur puisse re-lire si la voix lui a échappé.
    @Published private(set) var lastAnnouncement: String?
    /// 0..1 — fraction de checkpoints déjà annoncés (rough progress).
    @Published private(set) var progress: Double = 0

    struct ActiveTripSummary {
        let destinationName: String
        let totalMinutes: Int
        let firstLineCode: String?
    }

    private struct Checkpoint: Identifiable {
        let id: String
        let coordinate: CLLocationCoordinate2D
        let triggerDistance: CLLocationDistance
        let announcement: String
    }

    private var checkpoints: [Checkpoint] = []
    private var announced: Set<String> = []
    private var lastTriggerAt: Date = .distantPast
    /// Skip the per-update distance scan if the previous tick was less than
    /// 3s ago. `locationManager.$userCoordinate` can fire several times per
    /// second; running the loop every time + computing CLLocation.distance
    /// over all checkpoints would add measurable CPU/heat on long trips.
    private var lastScanAt: Date = .distantPast
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
        progress = 0
        let firstLine: String? = {
            for chip in option.legChips {
                if case .line(let descriptor) = chip { return descriptor.code }
            }
            return nil
        }()
        summary = ActiveTripSummary(
            destinationName: option.destinationName,
            totalMinutes: option.totalDurationMinutes,
            firstLineCode: firstLine
        )
        let initial = Self.initialAnnouncement(option: option, firstLine: firstLine)
        lastAnnouncement = initial
    }

    func stop() {
        isActive = false
        checkpoints = []
        announced = []
        startCoordinate = nil
        lastScanAt = .distantPast
        lastTriggerAt = .distantPast
        progress = 0
        summary = nil
        lastAnnouncement = nil
    }

    func onLocationUpdate(_ coord: CLLocationCoordinate2D?) {
        guard let coord, isActive, !checkpoints.isEmpty else { return }
        if startCoordinate == nil { startCoordinate = coord }
        let now = Date()
        // Throttle: at most one scan every 3s (caps CPU + battery), and at
        // most one announcement every 6s after a previous one.
        guard now.timeIntervalSince(lastScanAt) > 3 else { return }
        lastScanAt = now
        guard now.timeIntervalSince(lastTriggerAt) > 6 else { return }

        let userLoc = CLLocation(latitude: coord.latitude, longitude: coord.longitude)
        for cp in checkpoints where !announced.contains(cp.id) {
            let cpLoc = CLLocation(latitude: cp.coordinate.latitude, longitude: cp.coordinate.longitude)
            let dist = userLoc.distance(from: cpLoc)
            if dist <= cp.triggerDistance {
                announced.insert(cp.id)
                lastTriggerAt = Date()
                lastAnnouncement = cp.announcement
                progress = Double(announced.count) / Double(max(checkpoints.count, 1))
                // If we've announced the final arrival, the trip is done.
                if cp.id == "final" {
                    isActive = false
                    summary = nil
                    // lastAnnouncement reste ("Tu es arrivé") pour rester
                    // visible 2-3 s avant que la sheet route ne soit fermée.
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

    private static func initialAnnouncement(option: HomeRouteOption, firstLine: String?) -> String {
        let mins = option.totalDurationMinutes
        let dest = option.destinationName
        if let firstLine {
            return "Itinéraire vers \(dest) démarré. Environ \(mins) minutes. Prends la ligne \(firstLine)."
        }
        return "Itinéraire vers \(dest) démarré. Environ \(mins) minutes."
    }
}
