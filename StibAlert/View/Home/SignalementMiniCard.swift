import SwiftUI
import UIKit

struct SignalementMiniCard: View {
    let signalement: SignalementDTO
    let arretName: String?
    let onClose: () -> Void

    @State private var isSubmitting = false
    @State private var feedback: String?
    @State private var showConfidenceExplanation = false
    @State private var reportedFake = false
    @State private var showReportOptions = false

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
                            .font(DS.Font.labelSmall)
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
                    metaPill(icon: "person.2.fill", text: AppLocalizer.format("plural.blocked_votes", defaultValue: "%lld bloqué·e·s", stillBlockedCount))
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

            // Les deux boutons « Toujours bloqué » / « C'est résolu » ont été
            // retirés de cette carte. Elle s'ouvre au tap sur une pastille de
            // la carte, y compris sur un communiqué OFFICIEL de la STIB : y
            // demander à l'usager de confirmer n'avait pas de sens, puisque
            // l'information ne vient pas de la communauté et qu'un vote ne
            // pouvait rien y changer. Le geste reste disponible sur le détail
            // d'un signalement communautaire, là où il sert vraiment.

            Button(action: { showReportOptions = true }) {
                HStack(spacing: 5) {
                    Image(systemName: reportedFake ? "flag.fill" : "flag")
                        .font(.system(size: 11, weight: .semibold))
                    Text(reportedFake ? "Contenu signalé" : "Signaler ce contenu")
                        .font(DS.Font.caption)
                }
                .foregroundStyle(reportedFake ? DS.Color.inkMute : DS.Color.statusCritical)
            }
            .buttonStyle(.plain)
            .disabled(reportedFake || isSubmitting)
            .padding(.top, 6)
            .confirmationDialog("Signaler ce contenu", isPresented: $showReportOptions, titleVisibility: .visible) {
                Button("Contenu offensant ou inapproprié", role: .destructive) { reportContent(.offensive) }
                Button("Spam") { reportContent(.spam) }
                Button("Information erronée ou fausse") { triggerReportFake() }
                Button("Annuler", role: .cancel) {}
            }
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

    private var confidenceTint: Color { ReportFreshness.level(signalement.liveConfidence).tint }

    private var confidenceIcon: String { ReportFreshness.level(signalement.liveConfidence).icon }


    /// Signale un contenu offensant/spam à la MODÉRATION (endpoint /flag),
    /// distinct du vote communautaire « faux » — exigé par Apple 1.2 (report
    /// offensive content). Le back-end classe reason:"offensive" en priorité.
    private func reportContent(_ reason: FlagReason) {
        guard !reportedFake && !isSubmitting else { return }
        UIImpactFeedbackGenerator(style: .rigid).impactOccurred()
        Task {
            do {
                _ = try await ClusterService.flagSignalement(signalement.id, reason: reason)
                reportedFake = true
            } catch {
                // Silent fail — déjà signalé ou erreur réseau
            }
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
