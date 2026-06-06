import SwiftUI
import UIKit

struct SignalementMiniCard: View {
    let signalement: SignalementDTO
    let arretName: String?
    let onClose: () -> Void
    let onStillBlocked: () async -> Void
    let onResolved: () async -> Void

    @State private var isSubmitting = false
    @State private var userAction: String?
    @State private var feedback: String?
    @State private var showConfidenceExplanation = false
    @State private var reportedFake = false

    private var accentColor: Color {
        // Logique couleur sur le type CANONIQUE (français stable), pas sur le
        // libellé affiché qui est désormais localisé.
        switch signalement.canonicalTypeProbleme {
        case "Accident", "Agression": return DS.Color.statusCritical
        case "Retard", "Panne", "Travaux", "Déviation", "Interruption", "Arrêt non desservi": return DS.Color.statusMinor
        case "Incivilité": return DS.Color.community
        case "Propreté": return DS.Color.statusOK
        default: return DS.Color.primary
        }
    }

    private var confirmations: Int { signalement.community?.confirmations ?? 0 }
    private var stillBlockedCount: Int { signalement.community?.stillBlocked ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                LineBadge(line: signalement.ligne, size: .lg)

                VStack(alignment: .leading, spacing: 4) {
                    Text(signalement.displayTypeProbleme)
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)
                    if let arretName {
                        Text(arretName)
                            .font(DS.Font.monoSmall)
                            .tracking(1.0)
                            .textCase(.uppercase)
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 34, height: 34)
                        .background(DS.Color.paper2.opacity(0.8))
                        .clipShape(Circle())
                        .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                }
                .buttonStyle(.plain)
            }

            Text(signalement.description)
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkSoft)
                .lineLimit(3)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.top, 10)

            HStack(spacing: 10) {
                metaPill(icon: "clock", text: signalement.freshnessLabel)
                metaPill(
                    icon: confidenceIcon,
                    text: signalement.liveConfidenceLabel,
                    tint: confidenceTint
                )
                if let confirmationsSummary = signalement.confirmationsSummaryLabel {
                    metaPill(icon: "checkmark.seal.fill", text: confirmationsSummary)
                }
                if stillBlockedCount > 0 {
                    metaPill(icon: "person.2.fill", text: "\(stillBlockedCount) bloqué·e")
                }
            }
            .padding(.top, 12)

            HStack(spacing: 8) {
                metaPill(icon: "person.2.wave.2.fill", text: signalement.sourceLabel)

                if let confidenceLabel = signalement.confidenceLabel {
                    Button {
                        showConfidenceExplanation = true
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "location.circle.fill")
                                .font(.system(size: 10, weight: .semibold))
                            Text(confidenceLabel)
                                .font(.custom("Montserrat-Regular", size: 11))
                            Image(systemName: "questionmark.circle")
                                .font(.system(size: 10, weight: .semibold))
                        }
                        .foregroundStyle(DS.Color.inkSoft)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(DS.Color.paper2.opacity(0.7))
                        .overlay(Capsule().stroke(DS.Color.ink.opacity(0.10), lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if let stalePrompt = signalement.stalePromptLabel {
                    metaPill(icon: "clock.badge.exclamationmark", text: stalePrompt)
                }
            }
            .padding(.top, 8)

            if let feedback {
                Text(feedback)
                    .font(DS.Font.caption)
                    .foregroundStyle(accentColor)
                    .padding(.top, 10)
            }

            HStack(spacing: 10) {
                actionButton(
                    label: "Toujours bloqué",
                    icon: "exclamationmark.circle.fill",
                    tint: DS.Color.statusMinor,
                    isActive: userAction == "stillBlocked",
                    action: triggerStillBlocked
                )
                actionButton(
                    label: "C'est résolu",
                    icon: "checkmark.circle.fill",
                    tint: DS.Color.statusOK,
                    isActive: userAction == "resolved",
                    action: triggerResolved
                )
            }
            .padding(.top, 14)

            Button(action: triggerReportFake) {
                HStack(spacing: 5) {
                    Image(systemName: reportedFake ? "flag.fill" : "flag")
                        .font(.system(size: 11, weight: .semibold))
                    Text(reportedFake ? "Signalé comme faux" : "Signaler comme faux / abus")
                        .font(DS.Font.caption)
                }
                .foregroundStyle(reportedFake ? DS.Color.inkMute : DS.Color.statusCritical)
            }
            .buttonStyle(.plain)
            .disabled(reportedFake || isSubmitting)
            .padding(.top, 6)
        }
        .padding(DS.Spacing.lg)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1.2)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 2, style: .continuous)
                .fill(accentColor)
                .frame(width: 4)
                .padding(.vertical, DS.Spacing.lg)
        }
        .opacity(signalement.isStale ? 0.7 : 1)
        .shadow(DS.Shadow.floating)
        .alert("Pourquoi cette confiance ?", isPresented: $showConfidenceExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signalement.confidenceExplanation ?? AppLocalizer.string("confidence.gps_default", defaultValue: "Basée sur la proximité GPS observée au moment du signalement."))
        }
    }

    private func metaPill(icon: String, text: String, tint: Color? = nil) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(DS.Font.caption)
        }
        .foregroundStyle(tint ?? DS.Color.inkSoft)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background((tint ?? DS.Color.paper2).opacity(tint == nil ? 0.7 : 0.16))
        .overlay(Capsule().stroke((tint ?? DS.Color.ink).opacity(0.16), lineWidth: 1))
        .clipShape(Capsule())
    }

    private var confidenceTint: Color {
        switch signalement.liveConfidence {
        case 0.7...: return DS.Color.statusOK
        case 0.35..<0.7: return DS.Color.statusMinor
        default: return DS.Color.inkMute
        }
    }

    private var confidenceIcon: String {
        switch signalement.liveConfidence {
        case 0.7...: return "checkmark.seal.fill"
        case 0.35..<0.7: return "hourglass"
        default: return "questionmark.circle"
        }
    }

    private func actionButton(
        label: String,
        icon: String,
        tint: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSubmitting && isActive {
                    ProgressView().tint(DS.Color.ink)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(label)
                        .font(DS.Font.bodyBold)
                }
            }
            .foregroundStyle(DS.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 48)
            .background(isActive ? tint.opacity(0.24) : tint.opacity(0.14))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(isActive ? tint.opacity(0.7) : tint.opacity(0.35), lineWidth: 1.2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || userAction != nil)
        .opacity(userAction != nil && !isActive ? 0.5 : 1)
    }

    private func triggerStillBlocked() {
        guard !isSubmitting && userAction == nil else { return }
        isSubmitting = true
        userAction = "stillBlocked"
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            await onStillBlocked()
            feedback = "Merci, la communauté en est informée."
            isSubmitting = false
        }
    }

    private func triggerResolved() {
        guard !isSubmitting && userAction == nil else { return }
        isSubmitting = true
        userAction = "resolved"
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        Task {
            await onResolved()
            feedback = "Merci, le signalement est marqué résolu."
            isSubmitting = false
        }
    }

    private func triggerReportFake() {
        guard !reportedFake && !isSubmitting else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task {
            do {
                try await SignalementService.signalerFaux(signalementId: signalement.id)
                reportedFake = true
            } catch {
                // Silent fail — user has already reported or network error
            }
        }
    }
}
