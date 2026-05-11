import SwiftUI

struct OfflineIndicator: View {
    let isConnected: Bool
    let isConstrained: Bool

    var body: some View {
        if !isConnected {
            HStack(spacing: 8) {
                Image(systemName: "wifi.slash")
                    .font(.system(size: 13, weight: .semibold))
                Text("Vous êtes hors ligne")
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
                Text("Connexion limitée")
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
        }
    }
}
