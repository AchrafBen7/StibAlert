import SwiftUI

/// Bandeau « grève » affiché quand le backend signale une grève active
/// (`GET /api/strike`) : titre + message + lignes qui ne roulent pas.
/// Fermable quand `onClose` est fourni. Réutilisé sur la Home (overlay) et
/// en tête de Verkeersinfo (section).
struct StrikeBanner: View {
    let strike: StrikeState
    var onClose: (() -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "exclamationmark.octagon.fill")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(.white)
                    .padding(.top, 1)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Grève en cours")
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(.white)
                    if !strike.localizedMessage.isEmpty {
                        Text(strike.localizedMessage)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(.white.opacity(0.92))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer(minLength: 0)
                if let onClose {
                    Button(action: onClose) {
                        Image(systemName: "xmark")
                            .font(.system(size: 12, weight: .bold))
                            .foregroundStyle(.white)
                            .frame(width: 28, height: 28)
                            .background(Color.white.opacity(0.18))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Fermer"))
                }
            }
            if !strike.affectedLines.isEmpty {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Lignes à l'arrêt")
                        .font(.system(size: 10, weight: .bold))
                        .tracking(1.0)
                        .foregroundStyle(.white.opacity(0.8))
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(strike.affectedLines, id: \.self) { line in
                                Text(line)
                                    .font(.system(size: 12, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 9)
                                    .frame(height: 24)
                                    .background(Color.white.opacity(0.20))
                                    .clipShape(Capsule())
                            }
                        }
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.danger)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
