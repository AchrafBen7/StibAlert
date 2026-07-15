import SwiftUI

/// Tapping a departure in the gare timetable opens this sheet: the train's
/// time / line / destination, plus a favourite toggle so the user can pin a
/// recurring departure to the top of the gare's Horaires.
struct SncbDepartureSheet: View {
    let stationName: String
    let stationId: String
    let day: SNCBDayType
    let departure: SNCBDeparture
    @ObservedObject var favorites: SNCBDepartureFavorites
    /// Voie temps réel (iRail) du départ, si connue — uniquement pour les
    /// départs du jour couverts par le liveboard. nil → pas de badge.
    var platform: String? = nil
    /// iRail signale un changement de voie → badge accentué.
    var platformChanged: Bool = false
    @Environment(\.dismiss) private var dismiss

    private var favKey: String {
        SNCBDepartureFavorites.key(stationId: stationId, day: day, departure: departure)
    }
    private var isFavorite: Bool { favorites.contains(favKey) }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                // Concaténation String → « GARE SNCB » restait FR en NL.
                Text((stationName + " · " + AppLocalizer.string("Gare SNCB", defaultValue: "Gare SNCB")).uppercased())
                    .font(DS.Font.eyebrow)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
                // « Vertrek samedi » : le gabarit « Départ %@ » se traduisait,
                // mais on y interpolait le nom de jour FRANÇAIS codé en dur.
                // `day.label` est désormais localisé à la source (SNCBDayType).
                Text(AppLocalizer.format("sncb.departure_day", defaultValue: "Départ %@", day.label.lowercased()))
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
            }

            HStack(alignment: .center, spacing: 14) {
                Text(departure.time)
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(DS.Color.ink)
                    .monospacedDigit()
                if !departure.line.isEmpty {
                    Text(departure.line)
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 9)
                        .frame(height: 26)
                        .background(Color(hex: "#0055A4"))
                        .clipShape(Capsule())
                }
                // Voie temps réel — rien quand elle est inconnue (« Voie — »
                // n'existe pas) ; accent ambre si iRail signale un changement.
                if let platform {
                    HStack(spacing: 4) {
                        if platformChanged {
                            Image(systemName: "arrow.triangle.2.circlepath")
                                .font(.system(size: 10, weight: .black))
                        }
                        Text("Voie \(platform)")
                            .font(.system(size: 12, weight: .black, design: .rounded))
                    }
                    .foregroundStyle(platformChanged ? DS.Color.statusMinor : DS.Color.ink)
                    .padding(.horizontal, 9)
                    .frame(height: 26)
                    .background(
                        Capsule().fill(platformChanged ? DS.Color.statusMinor.opacity(0.16) : DS.Color.paper2)
                    )
                    .overlay(
                        Capsule().stroke(platformChanged ? DS.Color.statusMinor.opacity(0.5) : DS.Color.ink.opacity(0.14), lineWidth: 1)
                    )
                }
                Spacer(minLength: 0)
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.right")
                    .font(.system(size: 14, weight: .black))
                    .foregroundStyle(DS.Color.inkMute)
                Text(departure.destination)
                    .font(.system(size: 20, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)
            }

            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                favorites.toggle(favKey)
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: isFavorite ? "star.fill" : "star")
                        .font(.system(size: 16, weight: .black))
                    Text(isFavorite ? "Retiré des favoris" : "Ajouter aux favoris")
                        .font(DS.Font.bodyBold)
                }
                .foregroundStyle(isFavorite ? DS.Color.ink : DS.Color.primaryForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 52)
                .background(isFavorite ? DS.Color.paper : DS.Color.primary)
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
            }
            .buttonStyle(.plain)

            Text(AppLocalizer.string("Horaires théoriques (indicatifs).", defaultValue: "Horaires théoriques (indicatifs)."))
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity, alignment: .center)

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 24)
        .padding(.top, 28)
        .padding(.bottom, 20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper.ignoresSafeArea())
        .presentationDetents([.height(340)])
        .presentationDragIndicator(.visible)
        .preferredColorScheme(.light)
    }
}
