import SwiftUI

/// Lightweight sheet shown when tapping a De Lijn / TEC stop on the map.
/// Schedules / infos trafic per stop come later (these networks are line-based
/// for now); for now it names the stop and lets the user report a problem.
struct HomeOperatorStopSheet: View {
    let stop: OperatorMapStop
    let onReport: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 12) {
                Image(stop.op.assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 30, height: 30)
                    .frame(width: 50, height: 50)
                    .background(DS.Color.paper2.opacity(0.8))
                    .clipShape(RoundedRectangle(cornerRadius: 15, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                    )
                VStack(alignment: .leading, spacing: 4) {
                    Text("ARRÊT \(stop.op.mapLabel.uppercased())")
                        .font(DS.Font.eyebrow)
                        .tracking(2)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(stop.name)
                        .font(.system(size: 22, weight: .black))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(2)
                }
                Spacer(minLength: 0)
            }

            Text("Horaires et infos trafic \(stop.op.mapLabel) arrivent bientôt pour cet arrêt.")
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)

            Button(action: onReport) {
                HStack(spacing: 10) {
                    Image(systemName: "plus")
                        .font(.system(size: 16, weight: .black))
                    Text("Signaler cet arrêt")
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

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper.ignoresSafeArea())
        .presentationDetents([.height(250)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }
}
