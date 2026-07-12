import SwiftUI

struct OfflineIndicator: View {
    let isConnected: Bool
    let isConstrained: Bool
    var pendingReports: Int = 0

    var body: some View {
        if !isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text(offlineLabel)
                    .font(DS.Font.labelSmall.weight(.bold))
            }
            .foregroundStyle(DS.Color.primaryForeground)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Color.statusMajor)
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if isConstrained {
            HStack(spacing: 8) {
                Image(systemName: "wifi.exclamationmark")
                    .font(.system(size: 13, weight: .semibold))
                Text(AppLocalizer.string("Connexion limitée"))
                    .font(DS.Font.labelSmall.weight(.bold))
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Color.statusMinor.opacity(0.2))
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Color.statusMinor, lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        } else if pendingReports > 0 {
            HStack(spacing: 8) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 13, weight: .semibold))
                Text(pendingReportsLabel)
                    .font(DS.Font.labelSmall.weight(.bold))
            }
            .foregroundStyle(DS.Color.ink)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Color.paper2)
            .overlay(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .stroke(DS.Color.primary.opacity(0.3), lineWidth: 1)
            )
            .transition(.opacity.combined(with: .move(edge: .top)))
        }
    }

    private var offlineLabel: String {
        if pendingReports > 0 {
            // `.format()` applique %lld APRÈS avoir résolu la traduction —
            // contrairement à `.string()` (utilisé ici avant), qui interpolait
            // le compte dans le defaultValue AVANT le lookup : dès qu'une
            // traduction catalogue existait, le compte réel disparaissait,
            // remplacé par le texte statique du catalogue.
            return AppLocalizer.format(
                "offline_indicator.pending_queue",
                defaultValue: "Hors ligne · %lld en file",
                pendingReports
            )
        }
        return AppLocalizer.string(
            "offline_indicator.offline",
            defaultValue: "Vous êtes hors ligne"
        )
    }

    private var pendingReportsLabel: String {
        AppLocalizer.format("plural.pending_sync",
                            defaultValue: "%lld signalements en attente de sync",
                            pendingReports)
    }
}
