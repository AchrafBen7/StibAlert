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
                .accessibilityLabel("Arrêter le guidage")
                .accessibilityHint("Quitte le guidage actif pour ce trajet.")
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
                    stepMeta(text: "Ligne \(line)")
                }

                if let stopName = currentStep.stopName {
                    stepMeta(text: stopName)
                }

                if let arrivalStopName = currentStep.arrivalStopName {
                    stepMeta(text: "Vers \(arrivalStopName)")
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
                    Text("Ensuite")
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
                Button("Reparler") {
                    onSpeak()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityHint("Relit l'instruction courante à voix haute.")

                Button("Précédent") {
                    onBack()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityHint("Revient à l'étape précédente du guidage.")

                Button("Suivant") {
                    onNext()
                }
                .buttonStyle(PrimaryButton())
                .accessibilityHint("Passe à l'étape suivante du guidage.")
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
            return "Marche"
        case "tram", "metro", "bus":
            return "Transport"
        default:
            return "Guidage"
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
