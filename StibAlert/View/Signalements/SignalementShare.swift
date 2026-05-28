import SwiftUI

/// Builds the human-readable text shared when a user wants to warn relatives
/// about a problem — used by the detail view's share button and the
/// post-creation prompt. Self-contained text (no link required), so it reads
/// correctly in any messaging app even before the app ships.
enum SignalementShare {
    static func message(for s: SignalementDTO) -> String {
        let isSncb = s.ligne.uppercased() == "SNCB"
        let stop = arretName(s)
        let kind = s.displayTypeProbleme.uppercased()

        var out = ""

        // Ligne 1 — type + ligne en gros (titre visuel)
        if isSncb {
            out += "⚠️ \(kind) — SNCB\n"
        } else {
            out += "⚠️ \(kind) — Ligne \(s.ligne)\n"
        }

        // Ligne 2 — arrêt
        if let stop {
            out += "📍 \(stop)\n"
        }

        // Ligne 3 — fraîcheur
        out += "⏱️ Signalé \(s.freshnessLabel)\n"

        // Bloc description si distinct du type
        let desc = s.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty, desc.lowercased() != s.displayTypeProbleme.lowercased() {
            out += "\n💬 « \(desc) »\n"
        }

        // Confiance / multi-confirmation si on a les votes
        if let positives = s.votesPositifs, positives >= 2 {
            out += "\n✅ Confirmé par \(positives) personne\(positives > 1 ? "s" : "") dans la communauté.\n"
        }

        // Call to action
        out += "\nÉvite la zone ou prends une alternative."

        // Lien deep pour ouvrir l'app si installée. Les apps de messagerie
        // n'affichent pas de preview riche pour les schemes custom, mais
        // le texte reste lisible et le tap ouvre StibAlert si installée.
        out += "\n\n📲 StibAlert (app indépendante) — stibalert://signalement/\(s.id)"

        return out
    }

    static func arretName(_ s: SignalementDTO) -> String? {
        if case .populated(let arret) = s.arretId { return arret.nom }
        return nil
    }
}

/// Shown right after a report is published. Big "success" badge + impact
/// stats + share CTA. Le ton : "merci pour ta contribution", pas "tu peux
/// partager si tu veux".
struct ReportSharePromptSheet: View {
    let signalement: SignalementDTO
    var onFinish: () -> Void

    @State private var badgeScale: CGFloat = 0.6
    @State private var badgePulse = false

    var body: some View {
        VStack(spacing: 18) {
            // Badge succès animé (scale-in à l'apparition + pulse continu)
            ZStack {
                Circle()
                    .fill(DS.Color.statusOK.opacity(0.08))
                    .frame(width: 100, height: 100)
                    .scaleEffect(badgePulse ? 1.05 : 0.95)
                Circle()
                    .fill(DS.Color.statusOK.opacity(0.18))
                    .frame(width: 76, height: 76)
                    .scaleEffect(badgePulse ? 1.06 : 1.0)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 36, weight: .black))
                    .foregroundStyle(DS.Color.statusOK)
            }
            .scaleEffect(badgeScale)
            .padding(.top, 10)
            .animation(.spring(response: 0.45, dampingFraction: 0.7).delay(0.05), value: badgeScale)
            .animation(.easeInOut(duration: 1.4).repeatForever(autoreverses: true), value: badgePulse)
            .onAppear {
                badgeScale = 1.0
                badgePulse = true
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }

            VStack(spacing: 8) {
                Text("Signalement publié")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(DS.Color.ink)
                Text("Merci — ton signalement aide la communauté à anticiper les perturbations en temps réel.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }

            // Petite stat-card de réassurance (effet "tu n'es pas seul")
            HStack(spacing: 12) {
                statBadge(icon: "person.3.fill", value: "Communauté", subtitle: "alertée live")
                statBadge(icon: "bell.badge.fill", value: "Push", subtitle: "envoyés auto")
            }
            .padding(.horizontal, 4)

            // CTA partage
            ShareLink(item: SignalementShare.message(for: signalement)) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .black))
                    Text("Avertir tes proches")
                        .font(DS.Font.bodyBold)
                }
                .foregroundStyle(DS.Color.primaryForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 54)
                .background(
                    LinearGradient(
                        colors: [DS.Color.primary, DS.Color.primary.opacity(0.85)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .shadow(color: DS.Color.primary.opacity(0.25), radius: 8, y: 3)
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            })

            Button(action: onFinish) {
                Text("Terminer")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .frame(height: 40)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 22)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(DS.Color.paper.ignoresSafeArea())
        .presentationDetents([.height(440)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .preferredColorScheme(.light)
    }

    @ViewBuilder
    private func statBadge(icon: String, value: String, subtitle: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .bold))
                .foregroundStyle(DS.Color.primary)
                .frame(width: 28, height: 28)
                .background(DS.Color.primary.opacity(0.12))
                .clipShape(Circle())
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 11.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(subtitle)
                    .font(.system(size: 10))
                    .foregroundStyle(DS.Color.inkMute)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(DS.Color.paper2.opacity(0.7))
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }
}
