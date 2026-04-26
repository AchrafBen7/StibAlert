import ActivityKit
import Foundation

@available(iOS 16.1, *)
@MainActor
final class JourneyActivityManager {
    static let shared = JourneyActivityManager()
    private var activity: Activity<JourneyActivityAttributes>?

    func start(
        originName: String,
        destinationName: String,
        lineSummary: String,
        stepInstruction: String,
        arrivalMinutes: Int,
        currentLine: String?
    ) {
        guard ActivityAuthorizationInfo().areActivitiesEnabled else { return }

        let attrs = JourneyActivityAttributes(
            originName: originName,
            destinationName: destinationName,
            lineSummary: lineSummary
        )
        let state = JourneyActivityAttributes.ContentState(
            currentStepInstruction: stepInstruction,
            arrivalMinutes: arrivalMinutes,
            currentLine: currentLine,
            isFinished: false
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(600))

        do {
            activity = try Activity.request(
                attributes: attrs,
                content: content,
                pushType: nil
            )
        } catch {
            // Live Activities not available (iOS < 16.1 or simulator)
        }
    }

    func update(stepInstruction: String, arrivalMinutes: Int, currentLine: String?) {
        guard let activity else { return }
        let state = JourneyActivityAttributes.ContentState(
            currentStepInstruction: stepInstruction,
            arrivalMinutes: arrivalMinutes,
            currentLine: currentLine,
            isFinished: false
        )
        let content = ActivityContent(state: state, staleDate: Date().addingTimeInterval(300))
        Task {
            await activity.update(content)
        }
    }

    func finish() {
        guard let activity else { return }
        let finalState = JourneyActivityAttributes.ContentState(
            currentStepInstruction: "Vous êtes arrivé",
            arrivalMinutes: 0,
            currentLine: nil,
            isFinished: true
        )
        let finalContent = ActivityContent(state: finalState, staleDate: nil)
        Task {
            await activity.end(finalContent, dismissalPolicy: .after(Date().addingTimeInterval(30)))
        }
        self.activity = nil
    }
}
