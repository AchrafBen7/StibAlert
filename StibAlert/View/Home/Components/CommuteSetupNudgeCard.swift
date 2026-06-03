import SwiftUI

/// Invitation discrète à configurer le trajet quotidien, affichée sur la Home
/// à un utilisateur déjà engagé (≥1 favori) qui n'a pas encore de routine
/// active. Sans ce nudge, l'infra Smart Commute (CommuteQuickLaunchCard,
/// brief pré-départ, verdict, Plan B) reste inerte car personne ne va la
/// configurer spontanément dans Profil. Style aligné sur CommuteQuickLaunchCard.
struct CommuteSetupNudgeCard: View {
    let onConfigure: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        Button(action: onConfigure) {
            HStack(spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .fill(DS.Color.primary.opacity(0.15))
                    Image(systemName: "calendar.badge.clock")
                        .font(.system(size: 18, weight: .black))
                        .foregroundStyle(DS.Color.primary)
                }
                .frame(width: 44, height: 44)

                VStack(alignment: .leading, spacing: 2) {
                    Text("TON TRAJET QUOTIDIEN")
                        .font(.system(size: 9.5, weight: .black, design: .monospaced))
                        .tracking(1.8)
                        .foregroundStyle(DS.Color.inkMute)
                    Text("Configure-le pour un brief avant ton départ")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(2)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 4)

                Image(systemName: "chevron.right")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.primary)

                Button(action: onDismiss) {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                        .frame(width: 26, height: 26)
                        .background(DS.Color.paper2.opacity(0.6))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Ignorer")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(
                LinearGradient(
                    colors: [DS.Color.paper, DS.Color.paper2.opacity(0.6)],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .shadow(color: DS.Color.ink.opacity(0.06), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityHint("Ouvre les réglages pour activer ton trajet quotidien")
    }
}
