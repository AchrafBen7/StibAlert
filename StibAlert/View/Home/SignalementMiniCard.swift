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
        switch signalement.typeProbleme {
        case "Accident", "Agression": return AppTheme.Palette.alert
        case "Retard", "Panne": return AppTheme.Palette.warning
        case "Incivilité": return AppTheme.Palette.info
        case "Propreté": return AppTheme.Palette.success
        default: return AppTheme.Palette.brandStrong
        }
    }

    private var confirmations: Int { signalement.community?.confirmations ?? 0 }
    private var stillBlockedCount: Int { signalement.community?.stillBlocked ?? 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 12) {
                Text(signalement.ligne)
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.black)
                    .frame(width: 34, height: 34)
                    .background(accentColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                VStack(alignment: .leading, spacing: 2) {
                    Text(signalement.typeProbleme)
                        .font(.custom("DelaGothicOne-Regular", size: 16))
                        .foregroundStyle(.white)
                    if let arretName {
                        Text(arretName)
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(Color.white.opacity(0.7))
                            .lineLimit(1)
                    }
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(width: 26, height: 26)
                        .background(Color.white.opacity(0.1))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }

            Text(signalement.description)
                .font(.custom("Montserrat-Regular", size: 13))
                .foregroundStyle(Color.white.opacity(0.88))
                .lineLimit(2)
                .padding(.top, 10)

            HStack(spacing: 10) {
                metaPill(icon: "clock", text: signalement.freshnessLabel)
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
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                        .padding(.horizontal, 10)
                        .frame(height: 24)
                        .background(AppTheme.Palette.surfaceMuted)
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
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(accentColor)
                    .padding(.top, 10)
            }

            HStack(spacing: 10) {
                actionButton(
                    label: "Toujours bloqué",
                    icon: "exclamationmark.circle.fill",
                    background: AppTheme.Palette.warning,
                    isActive: userAction == "stillBlocked",
                    action: triggerStillBlocked
                )
                actionButton(
                    label: "C'est résolu",
                    icon: "checkmark.circle.fill",
                    background: AppTheme.Palette.success,
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
                        .font(.custom("Montserrat-Regular", size: 12))
                }
                .foregroundStyle(reportedFake ? AppTheme.Palette.textSecondary : AppTheme.Palette.alert.opacity(0.8))
            }
            .buttonStyle(.plain)
            .disabled(reportedFake || isSubmitting)
            .padding(.top, 6)
        }
        .padding(16)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(accentColor.opacity(0.45), lineWidth: 1)
        )
        .opacity(signalement.isStale ? 0.7 : 1)
        .shadow(color: .black.opacity(0.35), radius: 16, x: 0, y: 8)
        .alert("Pourquoi cette confiance ?", isPresented: $showConfidenceExplanation) {
            Button("OK", role: .cancel) {}
        } message: {
            Text(signalement.confidenceExplanation ?? "Basée sur la proximité GPS observée au moment du signalement.")
        }
    }

    private func metaPill(icon: String, text: String) -> some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 10, weight: .semibold))
            Text(text)
                .font(AppTheme.Fonts.caption)
        }
        .foregroundStyle(AppTheme.Palette.textSecondary)
        .padding(.horizontal, 10)
        .frame(height: 24)
        .background(AppTheme.Palette.surfaceMuted)
        .clipShape(Capsule())
    }

    private func actionButton(
        label: String,
        icon: String,
        background: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isSubmitting && isActive {
                    ProgressView().tint(.black)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .semibold))
                    Text(label)
                        .font(.custom("Montserrat-SemiBold", size: 13))
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.ButtonHeight.secondary)
            .background(isActive ? background : background.opacity(0.85))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
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
