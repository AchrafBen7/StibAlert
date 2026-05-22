import SwiftUI

struct HomeSncbStationSheet: View {
    let station: SNCBStation
    let onReport: () -> Void

    @State private var departures: [SNCBDeparture] = []
    @State private var isLoadingDepartures = true

    var body: some View {
        ScrollView(showsIndicators: false) {
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
                        Text(station.displayProvince.uppercased() + " · GARE SNCB")
                            .font(DS.Font.eyebrow)
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)
                        Text(station.displayName)
                            .font(.system(size: 24, weight: .black))
                            .foregroundStyle(DS.Color.ink)
                    }
                    Spacer(minLength: 0)
                }

                departuresSection

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
            .padding(.bottom, 24)
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task {
            departures = await SNCBStationService.departures(stationId: station.id, limit: 8)
            isLoadingDepartures = false
        }
    }

    private var departuresSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("PROCHAINS DÉPARTS")
                .font(DS.Font.eyebrow)
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)

            if isLoadingDepartures {
                HStack { ProgressView().tint(DS.Color.ink); Spacer() }
                    .padding(.vertical, 8)
            } else if departures.isEmpty {
                Text("Aucun départ à venir pour le moment (horaires théoriques).")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            } else {
                VStack(spacing: 0) {
                    ForEach(departures) { departureRow($0) }
                }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

                Text("Horaires théoriques · temps réel bientôt")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
        }
    }

    private func departureRow(_ dep: SNCBDeparture) -> some View {
        HStack(spacing: 12) {
            Text(dep.time)
                .font(DS.Font.monoLarge)
                .foregroundStyle(DS.Color.ink)
                .frame(width: 52, alignment: .leading)

            if !dep.line.isEmpty {
                Text(dep.line)
                    .font(.system(size: 10, weight: .black, design: .rounded))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(Color(hex: "#0055A4"))
                    .clipShape(Capsule())
            }

            Text(dep.destination)
                .font(DS.Font.bodyBold)
                .foregroundStyle(DS.Color.ink)
                .lineLimit(1)

            Spacer(minLength: 0)
        }
        .padding(.vertical, 11)
        .padding(.horizontal, 12)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1)
        }
    }
}
