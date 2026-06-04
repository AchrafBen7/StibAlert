import SwiftUI

struct CurrentStepCard: View {
    let routeTitle: String
    let progressText: String
    let stepProgressText: String?
    let rerouteNotice: String?
    let offRouteWarning: String?
    let currentStep: TransportRouteStepDTO
    let upcomingSteps: [TransportRouteStepDTO]
    let onBack: () -> Void
    let onNext: () -> Void
    let onStop: () -> Void
    let onSpeak: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(routeTitle)
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    Text(stepTitle(for: currentStep))
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                }

                Spacer()

                Button(action: onStop) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .frame(width: 28, height: 28)
                        .background(DesignSystem.Colors.cardBackground)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Routing.stopGuidance)
                .accessibilityHint(L10n.Routing.stopGuidanceHint)
            }

            Text(currentStep.instruction)
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .fixedSize(horizontal: false, vertical: true)

            HStack(spacing: 10) {
                stepMeta(text: progressText)
                stepMeta(text: "\(currentStep.durationMinutes) min")

                if let stepProgressText {
                    stepMeta(text: stepProgressText)
                }

                if let line = currentStep.line {
                    stepMeta(text: L10n.Routing.line(line))
                }

                if let stopName = currentStep.stopName {
                    stepMeta(text: stopName)
                }

                if let arrivalStopName = currentStep.arrivalStopName {
                    stepMeta(text: "\(L10n.Routing.to) \(arrivalStopName)")
                }
            }

            if let rerouteNotice {
                Text(rerouteNotice)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if let offRouteWarning {
                Text(offRouteWarning)
                    .font(DesignSystem.Typography.description)
                    .foregroundStyle(DesignSystem.Colors.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if !upcomingSteps.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text(L10n.Routing.nextThen)
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    ForEach(upcomingSteps) { step in
                        Text("• \(step.instruction)")
                            .font(DesignSystem.Typography.description)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            HStack(spacing: 10) {
                Button(L10n.Routing.speakAgain) {
                    onSpeak()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityHint(L10n.Routing.speakAgain)

                Button(L10n.Routing.previous) {
                    onBack()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityHint(L10n.Routing.previous)

                Button(L10n.Routing.nextAction) {
                    onNext()
                }
                .buttonStyle(PrimaryButton())
                .accessibilityHint(L10n.Routing.nextAction)
            }
        }
        .padding(16)
        .background(DesignSystem.Colors.cardBackground.opacity(0.95))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DesignSystem.Colors.border, lineWidth: 1)
        )
    }

    private func stepTitle(for step: TransportRouteStepDTO) -> String {
        switch step.mode.lowercased() {
        case "walk":
            return L10n.Routing.walking
        case "bike":
            return L10n.Routing.bike
        case "tram", "metro", "bus":
            return L10n.Routing.transport
        default:
            return L10n.Routing.routeStep
        }
    }

    private func stepMeta(text: String) -> some View {
        Text(text)
            .font(DesignSystem.Typography.labelSemibold)
            .foregroundStyle(DesignSystem.Colors.primaryText)
            .padding(.horizontal, 8)
            .frame(height: 24)
            .background(DesignSystem.Colors.accentSoft)
            .clipShape(Capsule())
    }
}
