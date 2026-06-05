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
                    .font(DS.Font.monoSmall.weight(.bold))
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
                    .font(DS.Font.monoSmall.weight(.bold))
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
                    .font(DS.Font.monoSmall.weight(.bold))
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
            return AppLocalizer.string(
                "offline_indicator.pending_queue",
                defaultValue: "Hors ligne · \(pendingReports) en file"
            )
        }
        return AppLocalizer.string(
            "offline_indicator.offline",
            defaultValue: "Vous êtes hors ligne"
        )
    }

    private var pendingReportsLabel: String {
        AppLocalizer.format(
            "%lld signalement%@ en attente de sync",
            defaultValue: "%lld signalement%@ en attente de sync",
            pendingReports,
            pendingReports > 1 ? "s" : ""
        )
    }
}
