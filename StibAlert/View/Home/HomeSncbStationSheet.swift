import SwiftUI

struct HomeSncbStationSheet: View {
    let station: SNCBStation
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image("operator-sncb")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 38, height: 38)
                    .frame(width: 54, height: 54)
                    .background(DS.Color.paper2.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                    )

                VStack(alignment: .leading, spacing: 4) {
                    Text("GARE SNCB")
                        .font(DS.Font.eyebrow)
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(station.displayName)
                        .font(.system(size: 24, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                    Text(String(format: "%.4f, %.4f", station.lat, station.lng))
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                }
            }

            Text("Cette gare est issue de la base SNCB locale. Les signalements SNCB apparaîtront dans la carte et dans Infos trafic avec le filtre SNCB.")
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            Button(action: onReport) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .black))
                    Text("Signaler cette gare")
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
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .background(DS.Color.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}
