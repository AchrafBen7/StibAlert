import SwiftUI
import UIKit

struct SignalementDetailView: View {
    let signalement: SignalementDTO
    var onDismiss: () -> Void
    var onOpenOnMap: (() -> Void)? = nil

    @State private var latest: SignalementDTO
    @State private var isSubmitting = false
    @State private var userAction: String? = nil
    @State private var feedback: String? = nil

    init(
        signalement: SignalementDTO,
        onDismiss: @escaping () -> Void,
        onOpenOnMap: (() -> Void)? = nil
    ) {
        self.signalement = signalement
        self.onDismiss = onDismiss
        self.onOpenOnMap = onOpenOnMap
        _latest = State(initialValue: signalement)
    }

    private var accentColor: Color {
        switch latest.typeProbleme {
        case "Accident", "Agression": return AppTheme.Palette.alert
        case "Retard", "Panne": return AppTheme.Palette.warning
        case "Incivilité": return AppTheme.Palette.info
        case "Propreté": return AppTheme.Palette.success
        default: return AppTheme.Palette.brand
        }
    }

    private var statusLabel: String {
        switch latest.status {
        case "resolved": return "Résolu"
        case "disputed": return "Contesté"
        default: return "Actif"
        }
    }

    private var statusColor: Color {
        switch latest.status {
        case "resolved": return AppTheme.Palette.success
        case "disputed": return AppTheme.Palette.alert
        default: return AppTheme.Palette.warning
        }
    }

    private var arretName: String? {
        if case .populated(let arret) = latest.arretId { return arret.nom }
        return nil
    }

    private var confirmations: Int { latest.community?.confirmations ?? 0 }
    private var stillBlocked: Int { latest.community?.stillBlocked ?? 0 }
    private var resolvedCount: Int { latest.community?.resolved ?? 0 }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    statusBadge
                    headerSection
                    descriptionSection
                    communitySection
                    if let confidenceLabel = latest.confidenceLabel {
                        confidenceSection(label: confidenceLabel, explanation: latest.confidenceExplanation)
                    }
                    sourceSection
                    if let feedback {
                        Text(feedback)
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(accentColor)
                    }
                    actionsRow
                    Spacer(minLength: 24)
                }
                .padding(20)
            }
            .background(AppTheme.Palette.screen.ignoresSafeArea())
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                    }
                }
                if onOpenOnMap != nil {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            onOpenOnMap?()
                        } label: {
                            Image(systemName: "map")
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                        }
                    }
                }
            }
            .navigationTitle("Signalement")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    private var statusBadge: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusLabel.uppercased())
                .font(AppTheme.Fonts.captionStrong)
                .kerning(1.2)
                .foregroundStyle(statusColor)
            Spacer()
            Text(latest.freshnessLabel)
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.Palette.textSecondary)
        }
        .padding(.horizontal, 14)
        .frame(height: 40)
        .background(statusColor.opacity(0.12))
        .clipShape(Capsule())
        .overlay(
            Capsule().stroke(statusColor.opacity(0.5), lineWidth: 1)
        )
    }

    private var headerSection: some View {
        HStack(alignment: .center, spacing: 14) {
            Text(latest.ligne)
                .font(AppTheme.Fonts.title2)
                .foregroundStyle(.black)
                .frame(width: 46, height: 46)
                .background(accentColor)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(latest.typeProbleme)
                    .font(AppTheme.Fonts.title2)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                if let arretName {
                    Text(arretName)
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                }
            }
            Spacer()
        }
    }

    private var descriptionSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            sectionTitle("Description")
            Text(latest.description)
                .font(AppTheme.Fonts.body)
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private var communitySection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle("Contributions")
            HStack(spacing: 10) {
                contributorPill(icon: "checkmark.seal.fill", value: confirmations, label: "confirmé·e·s", color: AppTheme.Palette.success)
                contributorPill(icon: "person.2.fill", value: stillBlocked, label: "toujours bloqué", color: AppTheme.Palette.warning)
                contributorPill(icon: "checkmark.circle.fill", value: resolvedCount, label: "ont résolu", color: AppTheme.Palette.info)
            }
            if confirmations + stillBlocked + resolvedCount == 0 {
                Text("Personne n'a encore confirmé ce signalement.")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textMuted)
            }
        }
    }

    private func contributorPill(icon: String, value: Int, label: String, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text("\(value)")
                    .font(AppTheme.Fonts.title3)
            }
            .foregroundStyle(color)
            Text(label)
                .font(AppTheme.Fonts.caption)
                .foregroundStyle(AppTheme.Palette.textSecondary)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                .stroke(color.opacity(0.3), lineWidth: 1)
        )
    }

    private func confidenceSection(label: String, explanation: String?) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            sectionTitle("Confiance")
            HStack(spacing: 8) {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(accentColor)
                Text(label)
                    .font(AppTheme.Fonts.bodyStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
            }
            if let explanation {
                Text(explanation)
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
    }

    private var sourceSection: some View {
        HStack(spacing: 8) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.system(size: 11, weight: .semibold))
            Text(latest.sourceLabel)
                .font(AppTheme.Fonts.caption)
            Spacer()
        }
        .foregroundStyle(AppTheme.Palette.textMuted)
    }

    private var actionsRow: some View {
        HStack(spacing: 10) {
            actionButton(
                label: "Toujours bloqué",
                icon: "exclamationmark.circle.fill",
                background: AppTheme.Palette.warning,
                isActive: userAction == "stillBlocked",
                action: { triggerAction(kind: "stillBlocked") }
            )
            actionButton(
                label: "Résolu",
                icon: "checkmark.circle.fill",
                background: AppTheme.Palette.success,
                isActive: userAction == "resolved",
                action: { triggerAction(kind: "resolved") }
            )
        }
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
                    Image(systemName: icon).font(.system(size: 12, weight: .semibold))
                    Text(label)
                        .font(AppTheme.Fonts.captionStrong)
                }
            }
            .foregroundStyle(.black)
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.ButtonHeight.secondary)
            .background(background.opacity(isActive ? 1 : 0.9))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmitting || userAction != nil)
        .opacity(userAction != nil && !isActive ? 0.5 : 1)
    }

    private func sectionTitle(_ text: String) -> some View {
        Text(text.uppercased())
            .font(AppTheme.Fonts.captionStrong)
            .kerning(1.1)
            .foregroundStyle(AppTheme.Palette.textMuted)
    }

    private func triggerAction(kind: String) {
        guard !isSubmitting && userAction == nil else { return }
        userAction = kind
        isSubmitting = true
        let haptic = UINotificationFeedbackGenerator()
        Task {
            do {
                let response: SignalementCommunityActionResponse
                switch kind {
                case "stillBlocked":
                    response = try await SignalementService.toujoursBloque(signalementId: latest.id)
                default:
                    response = try await SignalementService.resoudre(signalementId: latest.id)
                }
                haptic.notificationOccurred(.success)
                apply(response: response)
                feedback = kind == "resolved"
                    ? "Merci, le signalement est marqué résolu."
                    : "Merci, la communauté est alertée."
            } catch {
                haptic.notificationOccurred(.error)
                feedback = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func apply(response: SignalementCommunityActionResponse) {
        latest = SignalementDTO(
            id: latest.id,
            utilisateurId: latest.utilisateurId,
            arretId: latest.arretId,
            ligne: latest.ligne,
            typeProbleme: latest.typeProbleme,
            description: latest.description,
            photo: latest.photo,
            latitude: latest.latitude,
            longitude: latest.longitude,
            confiance: latest.confiance,
            source: latest.source,
            votesPositifs: latest.votesPositifs,
            votesNegatifs: latest.votesNegatifs,
            dateSignalement: latest.dateSignalement,
            status: response.status ?? latest.status,
            community: response.community ?? latest.community
        )
    }
}
