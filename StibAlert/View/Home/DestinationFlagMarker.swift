import SwiftUI

/// Marqueur d'ARRIVÉE : un vrai drapeau à damier planté sur un mât, avec son
/// point d'ancrage au sol — au lieu de la punaise générique `mappin.circle`,
/// qui ressemblait aux dizaines d'autres pins de la carte. Le damier dit
/// « ligne d'arrivée » sans un mot, dans toutes les langues.
struct DestinationFlagMarker: View {
    /// Taille d'une case du damier (points). 3 colonnes × 4 rangées.
    private let cell: CGFloat = 5
    private let columns = 3
    private let rows = 4

    private var flagWidth: CGFloat { cell * CGFloat(columns) }
    private var flagHeight: CGFloat { cell * CGFloat(rows) }

    var body: some View {
        VStack(spacing: 0) {
            // Drapeau : damier noir & blanc, accroché à droite du mât.
            HStack(spacing: 0) {
                Rectangle()
                    .fill(DS.Color.ink)
                    .frame(width: 2.5, height: flagHeight + 10)

                checkerboard
                    .overlay(
                        Rectangle().stroke(DS.Color.ink.opacity(0.35), lineWidth: 0.5)
                    )
                    .offset(y: -5)   // le drapeau flotte en haut du mât
            }

            // Socle : ancre le drapeau AU SOL, sinon il semble flotter au-dessus
            // de la carte et on ne sait pas quel point il désigne exactement.
            Circle()
                .fill(DS.Color.ink)
                .frame(width: 7, height: 7)
                .overlay(Circle().stroke(DS.Color.paper, lineWidth: 1.5))
                .offset(y: -1)
        }
        .shadow(color: .black.opacity(0.3), radius: 3, x: 0, y: 2)
        .accessibilityElement()
        .accessibilityLabel(AppLocalizer.string("a11y.destination", defaultValue: "Destination"))
    }

    /// Damier construit case par case (pas d'image à embarquer, net à toutes
    /// les densités d'écran).
    private var checkerboard: some View {
        VStack(spacing: 0) {
            ForEach(0..<rows, id: \.self) { row in
                HStack(spacing: 0) {
                    ForEach(0..<columns, id: \.self) { column in
                        Rectangle()
                            .fill((row + column).isMultiple(of: 2) ? DS.Color.ink : Color.white)
                            .frame(width: cell, height: cell)
                    }
                }
            }
        }
        .frame(width: flagWidth, height: flagHeight)
    }
}
