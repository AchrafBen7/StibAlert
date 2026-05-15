import ActivityKit
import WidgetKit
import SwiftUI

// Mirror of StibAlert/LiveActivity/JourneyActivityAttributes.swift.
// ActivityKit matches attribute types by name across app/widget targets, so
// both files MUST keep identical struct definitions. If you change one, change
// both. (Long-term fix: extract to a shared SPM target.)
@available(iOS 16.1, *)
struct JourneyActivityAttributes: ActivityAttributes {
    let originName: String
    let destinationName: String
    let lineSummary: String

    public struct ContentState: Codable, Hashable {
        var currentStepInstruction: String
        var arrivalMinutes: Int
        var currentLine: String?
        var isFinished: Bool
    }
}

// MARK: - Widget configuration

@available(iOS 16.1, *)
struct JourneyLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: JourneyActivityAttributes.self) { context in
            // Lock screen / banner
            JourneyLockScreenView(
                attributes: context.attributes,
                state: context.state
            )
            .padding(.horizontal, 4)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    JourneyDynamicIslandExpandedView(
                        attributes: context.attributes,
                        state: context.state
                    )
                }
            } compactLeading: {
                JourneyDynamicIslandCompactLeading(state: context.state)
            } compactTrailing: {
                JourneyDynamicIslandCompactTrailing(state: context.state)
            } minimal: {
                Image(systemName: context.state.isFinished ? "checkmark.circle.fill" : "tram.fill")
                    .foregroundStyle(Color(red: 0.06, green: 0.42, blue: 0.93))
            }
        }
    }
}

// MARK: - Views (mirrored from app target, simplified)

@available(iOS 16.1, *)
struct JourneyLockScreenView: View {
    let attributes: JourneyActivityAttributes
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 14) {
            ZStack {
                Circle()
                    .fill(Color(red: 0.06, green: 0.42, blue: 0.93).opacity(0.18))
                    .frame(width: 44, height: 44)
                Image(systemName: state.isFinished ? "checkmark.circle.fill" : "tram.fill")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Color(red: 0.06, green: 0.42, blue: 0.93))
            }

            VStack(alignment: .leading, spacing: 3) {
                if state.isFinished {
                    Text("Arrivé à \(attributes.destinationName)")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                } else {
                    Text(state.currentStepInstruction)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(.primary)
                        .lineLimit(2)
                }
                Text(attributes.originName + " → " + attributes.destinationName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            if !state.isFinished {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("\(state.arrivalMinutes)")
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.primary)
                    Text("min")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

@available(iOS 16.1, *)
struct JourneyDynamicIslandCompactLeading: View {
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "tram.fill")
                .font(.system(size: 11, weight: .bold))
            if let line = state.currentLine {
                Text(line)
                    .font(.system(size: 11, weight: .black, design: .rounded))
            }
        }
        .foregroundStyle(Color(red: 0.06, green: 0.42, blue: 0.93))
    }
}

@available(iOS 16.1, *)
struct JourneyDynamicIslandCompactTrailing: View {
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        HStack(spacing: 2) {
            Text("\(state.arrivalMinutes)")
                .font(.system(size: 13, weight: .black, design: .rounded))
            Text("m")
                .font(.system(size: 10))
        }
        .foregroundStyle(.white)
    }
}

@available(iOS 16.1, *)
struct JourneyDynamicIslandExpandedView: View {
    let attributes: JourneyActivityAttributes
    let state: JourneyActivityAttributes.ContentState

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label {
                    Text(attributes.lineSummary)
                        .font(.system(size: 13, weight: .semibold))
                } icon: {
                    Image(systemName: "tram.fill")
                        .font(.system(size: 12))
                }
                .foregroundStyle(Color(red: 0.06, green: 0.42, blue: 0.93))

                Spacer()

                if !state.isFinished {
                    Text("→ \(state.arrivalMinutes) min")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.white)
                }
            }

            Text(state.isFinished ? "Vous êtes arrivé !" : state.currentStepInstruction)
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(.white)
                .lineLimit(2)

            Text(attributes.originName + " → " + attributes.destinationName)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(1)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}
