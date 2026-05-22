import SwiftUI

/// Builds the human-readable text shared when a user wants to warn relatives
/// about a problem — used by the detail view's share button and the
/// post-creation "avertir vos proches" prompt. Self-contained text (no link),
/// so it reads correctly in any messaging app even before the app ships.
enum SignalementShare {
    static func message(for s: SignalementDTO) -> String {
        let isSncb = s.ligne.uppercased() == "SNCB"
        var out = "⚠️ \(s.displayTypeProbleme)"

        if isSncb {
            out += "\n🚉 \(arretName(s) ?? "Gare") · SNCB"
        } else {
            var loc = "Ligne \(s.ligne)"
            if let arret = arretName(s) { loc += " · \(arret)" }
            out += "\n🚊 \(loc)"
        }

        let desc = s.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if !desc.isEmpty, desc != s.displayTypeProbleme {
            out += "\n\(desc)"
        }

        out += "\n\nSignalé \(s.freshnessLabel) via StibAlert."
        return out
    }

    static func arretName(_ s: SignalementDTO) -> String? {
        if case .populated(let arret) = s.arretId { return arret.nom }
        return nil
    }
}

/// Shown right after a report is published: a friendly nudge to warn the
/// people who take the same line. Primary action is a system share sheet
/// pre-filled with the warning text; "Terminé" just closes.
struct ReportSharePromptSheet: View {
    let signalement: SignalementDTO
    var onFinish: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            ZStack {
                Circle()
                    .fill(DS.Color.statusOK.opacity(0.15))
                    .frame(width: 64, height: 64)
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 30, weight: .black))
                    .foregroundStyle(DS.Color.statusOK)
            }
            .padding(.top, 6)

            VStack(spacing: 6) {
                Text("Signalement publié")
                    .font(.system(size: 20, weight: .black))
                    .foregroundStyle(DS.Color.ink)
                Text("Prévenez vos proches qui empruntent cette ligne — partagez l'info en un geste.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
            }

            ShareLink(item: SignalementShare.message(for: signalement)) {
                HStack(spacing: 10) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 16, weight: .black))
                    Text("Avertir mes proches")
                        .font(DS.Font.bodyBold)
                }
                .foregroundStyle(DS.Color.primaryForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(DS.Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)
            .simultaneousGesture(TapGesture().onEnded {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
            })

            Button(action: onFinish) {
                Text("Terminé")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(maxWidth: .infinity)
                    .frame(height: 44)
            }
            .buttonStyle(.plain)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 24)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity)
        .background(DS.Color.paper.ignoresSafeArea())
        .presentationDetents([.height(360)])
        .presentationDragIndicator(.visible)
        .interactiveDismissDisabled(false)
        .preferredColorScheme(.light)
    }
}
