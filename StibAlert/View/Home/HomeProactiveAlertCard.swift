import SwiftUI

struct HomeProactiveAlertCard: View {
    let cluster: ClusterDTO
    let onClose: () -> Void
    let onOpenDetails: () -> Void
    let onStillBlocked: () async -> Void
    let onResolved: () async -> Void

    @State private var isSubmittingBlocked = false
    @State private var isSubmittingResolved = false

    private var accent: Color {
        cluster.isOfficial ? DS.Color.danger : SignalVisuals.communityColor(for: cluster)
    }

    private var sourceLabel: String {
        cluster.isOfficial ? "Source officielle" : "Communauté"
    }

    private var title: String {
        if cluster.isOfficial {
            return "Perturbation sur ta ligne"
        }
        if cluster.reportCount >= 3 {
            return "Signalement confirmé"
        }
        return "Alerte autour de toi"
    }

    private var summary: String {
        var parts: [String] = []
        parts.append("Ligne \(cluster.ligne)")
        parts.append(cluster.typeProbleme)
        if cluster.reportCount > 1 {
            parts.append("\(cluster.reportCount) retours")
        }
        return parts.joined(separator: " · ")
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                LineBadge(line: cluster.ligne, size: .lg)

                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        Image(systemName: SignalVisuals.icon(forType: cluster.typeProbleme))
                            .font(.system(size: 12, weight: .black))
                            .foregroundStyle(accent)
                        Text(verbatim: sourceLabel.uppercased())
                            .font(DS.Font.monoSmall.weight(.heavy))
                            .tracking(1.5)
                            .foregroundStyle(DS.Color.inkMute)
                    }

                    Text(verbatim: title)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)

                    Text(verbatim: summary)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .lineLimit(2)
                }

                Spacer(minLength: 8)

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 13, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 34, height: 34)
                        .background(DS.Color.paper2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Fermer l'alerte")
            }

            HStack(spacing: 8) {
                actionButton(
                    title: "Toujours bloqué",
                    icon: "exclamationmark.circle.fill",
                    isLoading: isSubmittingBlocked,
                    foreground: DS.Color.ink,
                    background: DS.Color.warning.opacity(0.18),
                    border: DS.Color.warning.opacity(0.45)
                ) {
                    guard !isSubmittingBlocked else { return }
                    isSubmittingBlocked = true
                    await onStillBlocked()
                    isSubmittingBlocked = false
                }

                actionButton(
                    title: "Résolu",
                    icon: "checkmark.circle.fill",
                    isLoading: isSubmittingResolved,
                    foreground: DS.Color.ink,
                    background: DS.Color.success.opacity(0.16),
                    border: DS.Color.success.opacity(0.42)
                ) {
                    guard !isSubmittingResolved else { return }
                    isSubmittingResolved = true
                    await onResolved()
                    isSubmittingResolved = false
                }
            }

            Button(action: onOpenDetails) {
                HStack(spacing: 8) {
                    Image(systemName: "map.fill")
                        .font(.system(size: 12, weight: .bold))
                    Text(verbatim: "Voir l’alerte sur la carte")
                        .font(DS.Font.monoSmall.weight(.heavy))
                        .tracking(1)
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .black))
                }
                .foregroundStyle(DS.Color.primary)
                .padding(.top, 2)
            }
            .buttonStyle(.plain)
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 3)
                .fill(accent)
                .frame(width: 4)
                .padding(.vertical, 10)
        }
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .shadow(DS.Shadow.floating)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(title), \(summary)")
    }

    private func actionButton(
        title: String,
        icon: String,
        isLoading: Bool,
        foreground: Color,
        background: Color,
        border: Color,
        action: @escaping () async -> Void
    ) -> some View {
        Button {
            Task { await action() }
        } label: {
            HStack(spacing: 7) {
                if isLoading {
                    ProgressView()
                        .scaleEffect(0.74)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 12, weight: .black))
                }
                Text(verbatim: title)
                    .font(DS.Font.bodySmall.weight(.heavy))
                    .lineLimit(1)
            }
            .foregroundStyle(foreground)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 10)
            .background(background)
            .overlay(
                RoundedRectangle(cornerRadius: 13, style: .continuous)
                    .stroke(border, lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 13, style: .continuous))
        }
        .buttonStyle(.plain)
        .disabled(isSubmittingBlocked || isSubmittingResolved)
    }
}
