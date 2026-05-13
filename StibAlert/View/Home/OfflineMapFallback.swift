import SwiftUI

/// Rendered above MapKit when the user is offline and tiles are blank.
/// Shows the cached snapshot + a clear "données hors-ligne" banner so the
/// user knows the pins on top are not necessarily up to date.
struct OfflineMapFallback: View {
    let isConnected: Bool

    @State private var cachedImage: UIImage? = nil
    @State private var snapshotAge: TimeInterval? = nil

    var body: some View {
        if !isConnected, let cachedImage {
            ZStack(alignment: .top) {
                Image(uiImage: cachedImage)
                    .resizable()
                    .scaledToFill()
                    .ignoresSafeArea()
                    .overlay(Color.black.opacity(0.12))
                    .accessibilityLabel("Carte hors-ligne, dernière vue connue")

                banner
                    .padding(.top, 50)
                    .padding(.horizontal, 16)
            }
            .transition(.opacity)
            .onAppear { reloadIfNeeded() }
        }
    }

    private var banner: some View {
        HStack(spacing: 10) {
            Image(systemName: "wifi.slash")
                .font(.system(size: 14, weight: .heavy))
            VStack(alignment: .leading, spacing: 2) {
                Text("CARTE HORS-LIGNE")
                    .font(DS.Font.monoSmall.weight(.heavy))
                    .tracking(2)
                Text(ageLabel)
                    .font(DS.Font.monoSmall)
            }
            Spacer()
        }
        .foregroundStyle(DS.Color.primaryForeground)
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Color.statusMajor)
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
    }

    private var ageLabel: String {
        guard let age = snapshotAge else { return "Dernière vue connue" }
        let mins = max(1, Int(age / 60))
        if mins < 60 { return "Capturée il y a \(mins) min" }
        let hours = mins / 60
        if hours < 24 { return "Capturée il y a \(hours)h" }
        return "Capturée il y a \(hours / 24)j"
    }

    private func reloadIfNeeded() {
        if cachedImage == nil {
            cachedImage = MapTileCache.loadSnapshot()
        }
        if let meta = MapTileCache.snapshotMetadata() {
            snapshotAge = Date().timeIntervalSince(meta.createdAt)
        }
    }
}
