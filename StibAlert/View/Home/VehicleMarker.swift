import SwiftUI

/// Véhicule temps réel sur la carte, dans l'esprit De Lijn : une PETITE caisse
/// blanche étroite, cerclée d'un trait fin sombre, posée dans un HALO doux à la
/// couleur de la ligne.
///
/// Trois essais ont été nécessaires pour arriver là, et la leçon vaut d'être
/// écrite :
///  1. une caisse blanche large avec vitres et rétroviseurs → se lisait comme
///     un TÉLÉPHONE (rectangle arrondi de ce format = écran) ;
///  2. une caisse pleine avec pictogramme par-dessus → lisible, mais l'effet
///     « temps réel » avait disparu ;
///  3. la bonne réponse : ce n'est pas le DÉTAIL du véhicule qui fait l'effet,
///     c'est sa PETITESSE + le halo lumineux. Un véhicule doit être discret sur
///     la carte ; c'est la lueur qui attire l'œil et dit « ça bouge, là,
///     maintenant ».
///
/// Le repère coloré à l'avant donne le sens de marche sans flèche ajoutée.
struct VehicleMarker: View {
    let vehicle: TransportVehicleDTO
    /// Cap VERS LE TERMINUS (0 = nord), calculé par HomeMapLayer en alignant le
    /// véhicule sur le tracé de sa ligne. nil = direction inconnue → on n'en
    /// affiche aucune plutôt que d'en inventer une.
    var bearing: Double? = nil
    /// Cap de la carte : les annotations restent alignées à l'écran, il faut
    /// donc le retrancher pour que le véhicule pointe la bonne direction RÉELLE
    /// même quand l'utilisateur fait pivoter la carte.
    var mapHeading: Double = 0

    private var mode: TransitLineMode { TransitLineMode.mode(for: vehicle.line) }

    private var lineColor: Color {
        guard let line = vehicle.line else { return DS.Color.primary }
        return TransitLinePalette.fill(for: line)
    }

    /// Assez large pour porter le PICTOGRAMME du mode, assez étroit pour rester
    /// une silhouette de véhicule. À 9 pt (version précédente) ni la flèche ni
    /// l'accent coloré n'étaient visibles : il ne restait qu'une gélule blanche
    /// illisible. Le bus reste plus court que le tram / métro.
    private var size: CGSize {
        switch mode {
        case .metro: return CGSize(width: 16, height: 27)
        case .tram:  return CGSize(width: 16, height: 26)
        case .bus:   return CGSize(width: 16, height: 22)
        }
    }

    var body: some View {
        ZStack {
            glow
            chassis
                // On retranche le cap de la carte : sinon un véhicule orienté
                // plein nord continuerait de pointer vers le haut de l'ÉCRAN
                // après une rotation de la carte, donc vers une fausse
                // direction. Sans cap connu, la caisse reste droite ET son
                // repère avant est masqué (cf. chassis).
                .rotationEffect(.degrees((bearing ?? 0) - mapHeading))
                .animation(.easeInOut(duration: 0.45), value: bearing)
                .animation(.easeInOut(duration: 0.3), value: mapHeading)
        }
        .frame(width: 46, height: 46)
        .accessibilityElement()
        .accessibilityLabel(AppLocalizer.format("a11y.vehicle_line", defaultValue: "Véhicule ligne %@", vehicle.line ?? "?"))
    }

    /// Halo doux : trois cercles concentriques flous, pas une pastille nette.
    /// C'est LUI l'effet « temps réel » — il respire lentement pour montrer que
    /// la donnée est vivante, sans agiter la carte.
    private var glow: some View {
        ZStack {
            Circle().fill(lineColor.opacity(0.16)).frame(width: 40, height: 40).blur(radius: 7)
            Circle().fill(lineColor.opacity(0.26)).frame(width: 28, height: 28).blur(radius: 5)
            Circle().fill(lineColor.opacity(0.38)).frame(width: 19, height: 19).blur(radius: 3)
        }
        .modifier(BreathingGlow())
    }

    private var chassis: some View {
        let w = size.width
        let h = size.height

        return ZStack {
            RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                .fill(Color.white)
                .frame(width: w, height: h)
                .overlay(
                    RoundedRectangle(cornerRadius: 4.5, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.85), lineWidth: 1)
                )
                .shadow(color: .black.opacity(0.22), radius: 1.5, x: 0, y: 1)

            // NEZ COLORÉ en haut = l'avant du véhicule. Une bande pleine se lit
            // mieux qu'une petite flèche flottante, qui encombrait la caisse.
            // Masqué si la direction est inconnue : on ne prétend pas savoir
            // où va le véhicule.
            if bearing != nil {
                VStack(spacing: 0) {
                    UnevenRoundedRectangle(
                        topLeadingRadius: 3.5, bottomLeadingRadius: 0,
                        bottomTrailingRadius: 0, topTrailingRadius: 3.5,
                        style: .continuous
                    )
                    .fill(lineColor)
                    .frame(width: w - 2, height: h * 0.26)
                    Spacer(minLength: 0)
                }
                .frame(width: w, height: h)
                .padding(.top, 1)
            }

            // PICTOGRAMME DU MODE, centré sous le nez : sans lui, la caisse
            // blanche se lisait comme une simple gélule. C'est ce qui dit
            // « tram » ou « bus » d'un coup d'œil.
            Image(systemName: mode.sfSymbol)
                .font(.system(size: 9.5, weight: .black))
                .foregroundStyle(DS.Color.ink)
                .offset(y: bearing != nil ? h * 0.14 : 0)
        }
        .frame(width: w, height: h)
    }
}

/// Respiration lente du halo (1,8 s) : signale une donnée vivante sans créer
/// l'agitation d'une animation rapide quand plusieurs véhicules sont visibles.
private struct BreathingGlow: ViewModifier {
    @State private var pulse = false

    func body(content: Content) -> some View {
        content
            .scaleEffect(pulse ? 1.12 : 0.92)
            .opacity(pulse ? 1 : 0.75)
            .onAppear {
                withAnimation(.easeInOut(duration: 1.8).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
    }
}
