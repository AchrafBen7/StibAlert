import Foundation
import CoreLocation

@MainActor
final class GuidanceCoordinator: ObservableObject {
    @Published private(set) var activeAlternative: SearchRouteAlternative?
    @Published private(set) var currentStepIndex = 0
    @Published private(set) var isGuiding = false
    @Published private(set) var rerouteNotice: String?
    @Published private(set) var stepProgress = 0.0
    @Published private(set) var offRouteWarning: String?
    @Published private(set) var snappedCoordinate: CLLocationCoordinate2D?
    @Published private(set) var offRouteUpdates = 0

    private var consecutiveOffRouteUpdates = 0

    var progressText: String {
        guard let activeAlternative else { return "" }
        let total = activeAlternative.steps.count
        guard total > 0 else { return "" }
        return "Étape \(min(currentStepIndex + 1, total)) sur \(total)"
    }

    var currentStep: TransportRouteStepDTO? {
        guard let activeAlternative else { return nil }
        guard activeAlternative.steps.indices.contains(currentStepIndex) else { return nil }
        return activeAlternative.steps[currentStepIndex]
    }

    var upcomingSteps: [TransportRouteStepDTO] {
        guard let activeAlternative else { return [] }
        let startIndex = min(currentStepIndex + 1, activeAlternative.steps.count)
        return Array(activeAlternative.steps.dropFirst(startIndex).prefix(3))
    }

    func start(with alternative: SearchRouteAlternative, notice: String? = nil) {
        guard !alternative.steps.isEmpty else { return }
        activeAlternative = alternative
        currentStepIndex = 0
        isGuiding = true
        rerouteNotice = notice
        stepProgress = 0
        offRouteWarning = nil
        snappedCoordinate = nil
        offRouteUpdates = 0
        consecutiveOffRouteUpdates = 0
    }

    func stop() {
        activeAlternative = nil
        currentStepIndex = 0
        isGuiding = false
        rerouteNotice = nil
        stepProgress = 0
        offRouteWarning = nil
        snappedCoordinate = nil
        offRouteUpdates = 0
        consecutiveOffRouteUpdates = 0
    }

    func advance() {
        guard let activeAlternative else { return }
        let nextIndex = currentStepIndex + 1
        if activeAlternative.steps.indices.contains(nextIndex) {
            currentStepIndex = nextIndex
            stepProgress = 0
            offRouteWarning = nil
            snappedCoordinate = nil
            offRouteUpdates = 0
            consecutiveOffRouteUpdates = 0
        } else {
            stop()
        }
    }

    func goBack() {
        guard isGuiding else { return }
        currentStepIndex = max(0, currentStepIndex - 1)
        stepProgress = 0
    }

    @discardableResult
    func autoAdvanceIfNeeded(userLocation: CLLocation) -> Bool {
        guard let currentStep else { return false }
        if let projected = projectedProgress(for: userLocation, on: currentStep) {
            stepProgress = max(stepProgress, projected.progress)
            snappedCoordinate = projected.snappedCoordinate

            let isWalk = currentStep.mode.lowercased() == "walk"
            let offPathThreshold: CLLocationDistance = isWalk ? 90 : 180
            if projected.distanceFromPath > offPathThreshold {
                consecutiveOffRouteUpdates += 1
                offRouteUpdates = consecutiveOffRouteUpdates
                if consecutiveOffRouteUpdates >= 2 {
                    offRouteWarning = "Tu t’éloignes du corridor recommandé. Je surveille un éventuel reroutage."
                }
                return false
            }

            consecutiveOffRouteUpdates = 0
            offRouteUpdates = 0
            offRouteWarning = nil

            let completionDistance: CLLocationDistance = isWalk ? 80 : 170
            let completionProgress = isWalk ? 0.9 : 0.86
            if projected.progress >= 0.98
                || (projected.progress >= completionProgress && projected.distanceToEnd <= completionDistance) {
                advance()
                rerouteNotice = nil
                return true
            }
            return false
        }

        guard let targetLatitude = currentStep.targetLatitude,
              let targetLongitude = currentStep.targetLongitude else {
            return false
        }

        let target = CLLocation(latitude: targetLatitude, longitude: targetLongitude)
        let distance = userLocation.distance(from: target)
        let threshold: CLLocationDistance = currentStep.mode.lowercased() == "walk" ? 55 : 120
        guard distance <= threshold else { return false }

        advance()
        rerouteNotice = nil
        return true
    }

    @discardableResult
    func refresh(using alternatives: [SearchRouteAlternative]) -> Bool {
        guard let activeAlternative else { return false }
        if let updated = alternatives.first(where: { $0.id == activeAlternative.id }) {
            let didChangeRoute = updated.steps != activeAlternative.steps || updated.eta != activeAlternative.eta
            if updated.steps != activeAlternative.steps || updated.eta != activeAlternative.eta {
                rerouteNotice = "Le guidage a été ajusté avec la dernière situation réseau."
            } else {
                rerouteNotice = nil
            }
            self.activeAlternative = updated
            if !updated.steps.indices.contains(currentStepIndex) {
                currentStepIndex = 0
            }
            stepProgress = 0
            offRouteWarning = nil
            snappedCoordinate = nil
            offRouteUpdates = 0
            consecutiveOffRouteUpdates = 0
            return didChangeRoute
        }

        if let fallback = alternatives.first, !fallback.steps.isEmpty {
            start(
                with: fallback,
                notice: "L’option guidée n’est plus la meilleure. Je bascule sur une alternative plus stable."
            )
            return true
        } else {
            stop()
            return false
        }
    }

    private func projectedProgress(for userLocation: CLLocation, on step: TransportRouteStepDTO) -> (progress: Double, distanceFromPath: CLLocationDistance, distanceToEnd: CLLocationDistance, snappedCoordinate: CLLocationCoordinate2D)? {
        let path = (step.path ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
        guard path.count >= 2 else { return nil }

        let projected = project(userLocation.coordinate, onto: path)
        let end = CLLocation(latitude: path[path.count - 1].latitude, longitude: path[path.count - 1].longitude)
        return (
            progress: projected.progress,
            distanceFromPath: projected.distanceFromPath,
            distanceToEnd: userLocation.distance(from: end),
            snappedCoordinate: projected.snappedCoordinate
        )
    }

    private func project(_ user: CLLocationCoordinate2D, onto path: [CLLocationCoordinate2D]) -> (progress: Double, distanceFromPath: CLLocationDistance, snappedCoordinate: CLLocationCoordinate2D) {
        let totalLength = totalPathLength(path)
        guard totalLength > 1 else { return (0, .greatestFiniteMagnitude, path.first ?? user) }

        var bestDistance = CLLocationDistance.greatestFiniteMagnitude
        var bestTravelled = 0.0
        var travelled = 0.0
        var bestCoordinate = path.first ?? user

        for index in 0..<(path.count - 1) {
            let start = path[index]
            let end = path[index + 1]
            let segmentLength = distance(start, end)
            guard segmentLength > 1 else { continue }

            let projection = projectPoint(user, ontoSegmentFrom: start, to: end)
            let distanceFromPath = distance(user, projection.coordinate)
            if distanceFromPath < bestDistance {
                bestDistance = distanceFromPath
                bestTravelled = travelled + segmentLength * projection.t
                bestCoordinate = projection.coordinate
            }

            travelled += segmentLength
        }

        return (
            progress: min(max(bestTravelled / totalLength, 0), 1),
            distanceFromPath: bestDistance,
            snappedCoordinate: bestCoordinate
        )
    }

    private func totalPathLength(_ path: [CLLocationCoordinate2D]) -> Double {
        guard path.count >= 2 else { return 0 }
        return zip(path, path.dropFirst()).reduce(0) { partial, pair in
            partial + distance(pair.0, pair.1)
        }
    }

    private func projectPoint(_ point: CLLocationCoordinate2D, ontoSegmentFrom start: CLLocationCoordinate2D, to end: CLLocationCoordinate2D) -> (coordinate: CLLocationCoordinate2D, t: Double) {
        let origin = start
        let startVector = projectedPoint(start, relativeTo: origin)
        let endVector = projectedPoint(end, relativeTo: origin)
        let pointVector = projectedPoint(point, relativeTo: origin)

        let segmentX = endVector.x - startVector.x
        let segmentY = endVector.y - startVector.y
        let lengthSquared = segmentX * segmentX + segmentY * segmentY
        guard lengthSquared > 0 else { return (start, 0) }

        let pointX = pointVector.x - startVector.x
        let pointY = pointVector.y - startVector.y
        let rawT = ((pointX * segmentX) + (pointY * segmentY)) / lengthSquared
        let t = min(max(rawT, 0), 1)

        return (
            coordinate: CLLocationCoordinate2D(
                latitude: start.latitude + (end.latitude - start.latitude) * t,
                longitude: start.longitude + (end.longitude - start.longitude) * t
            ),
            t: t
        )
    }

    private func projectedPoint(_ point: CLLocationCoordinate2D, relativeTo origin: CLLocationCoordinate2D) -> (x: Double, y: Double) {
        let latScale = 111_000.0
        let lonScale = 111_000.0 * cos(((origin.latitude + point.latitude) / 2.0) * .pi / 180.0)
        return (
            x: (point.longitude - origin.longitude) * lonScale,
            y: (point.latitude - origin.latitude) * latScale
        )
    }

    private func distance(_ lhs: CLLocationCoordinate2D, _ rhs: CLLocationCoordinate2D) -> Double {
        CLLocation(latitude: lhs.latitude, longitude: lhs.longitude)
            .distance(from: CLLocation(latitude: rhs.latitude, longitude: rhs.longitude))
    }
}
