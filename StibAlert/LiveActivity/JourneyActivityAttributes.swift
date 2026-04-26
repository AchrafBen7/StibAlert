import ActivityKit
import Foundation

@available(iOS 16.1, *)
struct JourneyActivityAttributes: ActivityAttributes {
    // Static — set at start, never changes
    let originName: String
    let destinationName: String
    let lineSummary: String

    // Dynamic — pushed via ActivityKit or APNs
    public struct ContentState: Codable, Hashable {
        var currentStepInstruction: String
        var arrivalMinutes: Int
        var currentLine: String?
        var isFinished: Bool
    }
}
