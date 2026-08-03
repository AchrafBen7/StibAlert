import SwiftUI

/// Visite guidée "coach marks" : l'écran s'assombrit, un trou lumineux met en
/// valeur un VRAI élément de l'interface, et une bulle explique à quoi il sert.
///
/// Remplace l'ancienne visite plein écran, désormais supprimée : elle recouvrait
/// la carte de cartons abstraits, donc l'utilisateur apprenait sur des
/// illustrations puis devait retrouver les boutons tout seul. Son contenu était
/// en plus codé en dur en français, ce qui donnait un écran entier en français
/// aux néerlandophones. Ici l'utilisateur regarde son propre écran, à sa place.
///
/// Volontairement SANS icône ni tiret cadratin dans les textes.

// MARK: - Cibles

enum CoachMarkTarget: String, CaseIterable {
    case reportButton
    case tabBar
    case legendButton
}

/// Rectangles publiés par les vues cibles, collectés à la racine.
struct CoachMarkAnchorKey: PreferenceKey {
    static var defaultValue: [CoachMarkTarget: Anchor<CGRect>] = [:]
    static func reduce(
        value: inout [CoachMarkTarget: Anchor<CGRect>],
        nextValue: () -> [CoachMarkTarget: Anchor<CGRect>]
    ) {
        value.merge(nextValue()) { _, new in new }
    }
}

extension View {
    /// Marque une vue comme cible d'une étape de la visite.
    func coachMarkAnchor(_ target: CoachMarkTarget) -> some View {
        anchorPreference(key: CoachMarkAnchorKey.self, value: .bounds) { [target: $0] }
    }
}

// MARK: - Étapes

struct CoachMarkStep {
    let target: CoachMarkTarget?   // nil = pas d'élément précis, on éclaire la carte
    let title: String
    let body: String
    /// Coins arrondis du trou lumineux, pour épouser la forme de l'élément.
    var cornerRadius: CGFloat = 16
}

enum CoachMarkTour {
    /// `isGuest` change deux textes : sans compte, on explique ce que la
    /// connexion débloque plutôt que de décrire des écrans vides.
    static func steps(isGuest: Bool) -> [CoachMarkStep] {
        [
            CoachMarkStep(
                target: .reportButton,
                title: AppLocalizer.string("coach.report.title", defaultValue: "Signaler ce que tu vois"),
                body: isGuest
                    ? AppLocalizer.string(
                        "coach.report.body.guest",
                        defaultValue: "Tram bloqué, bus bondé, contrôle : préviens les autres voyageurs en deux taps. Pas besoin de compte pour signaler."
                      )
                    : AppLocalizer.string(
                        "coach.report.body",
                        defaultValue: "Tram bloqué, bus bondé, contrôle : préviens les autres voyageurs en deux taps. Plus il y a de signalements, plus le réseau devient lisible."
                      ),
                cornerRadius: 30
            ),
            CoachMarkStep(
                target: .tabBar,
                title: AppLocalizer.string("coach.tabs.title", defaultValue: "Tes cinq espaces"),
                body: AppLocalizer.string(
                    "coach.tabs.body",
                    defaultValue: "Carte pour voir autour de toi, Lignes pour les horaires, Alertes pour les perturbations en cours, Favoris pour tes arrêts épinglés, Profil pour tes réglages."
                ),
                cornerRadius: 26
            ),
            CoachMarkStep(
                target: nil,
                title: AppLocalizer.string("coach.map.title", defaultValue: "Arrêts et signalements"),
                body: AppLocalizer.string(
                    "coach.map.body",
                    defaultValue: "Chaque pastille colorée est un arrêt avec ses prochains passages. Les pastilles bleues sont les signalements de la communauté, les rouges les perturbations officielles. Touche un arrêt pour voir le détail."
                )
            ),
            CoachMarkStep(
                target: .legendButton,
                title: AppLocalizer.string("coach.legend.title", defaultValue: "Choisir ce qui s'affiche"),
                body: isGuest
                    ? AppLocalizer.string(
                        "coach.legend.body.guest",
                        defaultValue: "Affiche ou masque la STIB, la SNCB, De Lijn, le TEC et les signalements. Crée un compte pour retrouver tes favoris sur tous tes appareils."
                      )
                    : AppLocalizer.string(
                        "coach.legend.body",
                        defaultValue: "Affiche ou masque la STIB, la SNCB, De Lijn, le TEC, les vélos partagés et les signalements. À toi de garder seulement ce qui te sert."
                      ),
                cornerRadius: 14
            ),
        ]
    }
}

// MARK: - Calque

struct CoachMarksOverlay: View {
    let steps: [CoachMarkStep]
    let anchors: [CoachMarkTarget: Anchor<CGRect>]
    let proxy: GeometryProxy
    @Binding var index: Int
    let onFinish: () -> Void

    private var step: CoachMarkStep? { steps.indices.contains(index) ? steps[index] : nil }
    private var isLast: Bool { index >= steps.count - 1 }

    /// Rectangle à éclairer. Sans cible (ou si la vue n'est pas rendue), on
    /// éclaire une zone centrale de la carte plutôt que de ne rien montrer.
    private var spotlight: CGRect {
        if let target = step?.target, let anchor = anchors[target] {
            return proxy[anchor].insetBy(dx: -10, dy: -10)
        }
        let size = proxy.size
        return CGRect(
            x: size.width * 0.12,
            y: size.height * 0.34,
            width: size.width * 0.76,
            height: size.height * 0.26
        )
    }

    /// La bulle se place au-dessus du trou s'il est en bas de l'écran, en
    /// dessous sinon : elle ne recouvre jamais l'élément qu'elle décrit.
    private var bubbleBelowSpotlight: Bool {
        spotlight.midY < proxy.size.height * 0.5
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            dimming
            spotlightRing
            bubble
        }
        // ⚠️ PAS de `.ignoresSafeArea()` ici. Les rectangles viennent de
        // `proxy[anchor]`, donc de l'espace du GeometryReader ; dessiner dans un
        // calque qui ignore la zone sûre décalait tout vers le haut de la
        // hauteur de l'encoche : le projecteur visait le bouton de recentrage au
        // lieu de « signaler », la bannière invité au lieu des onglets, et le
        // vide au-dessus de la légende. C'est le GeometryReader lui-même qui
        // ignore désormais la zone sûre (cf. HomeView), pour que le calcul et le
        // dessin partagent le même repère.
        .transition(.opacity)
        .animation(.easeInOut(duration: 0.28), value: index)
    }

    /// Voile sombre percé au niveau de l'élément mis en valeur.
    private var dimming: some View {
        Rectangle()
            .fill(Color.black.opacity(0.72))
            .reverseMask {
                RoundedRectangle(cornerRadius: step?.cornerRadius ?? 16, style: .continuous)
                    .frame(width: spotlight.width, height: spotlight.height)
                    .position(x: spotlight.midX, y: spotlight.midY)
            }
            .contentShape(Rectangle())
            .onTapGesture { advance() }
    }

    private var spotlightRing: some View {
        RoundedRectangle(cornerRadius: step?.cornerRadius ?? 16, style: .continuous)
            .stroke(Color.white.opacity(0.9), lineWidth: 2)
            .frame(width: spotlight.width, height: spotlight.height)
            .position(x: spotlight.midX, y: spotlight.midY)
            .allowsHitTesting(false)
    }

    @ViewBuilder
    private var bubble: some View {
        if let step {
            VStack(alignment: .leading, spacing: 10) {
                Text(step.title)
                    .font(.system(size: 19, weight: .bold))
                    .foregroundStyle(DS.Color.ink)

                Text(step.body)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    // Progression sous forme de points : on sait combien il reste.
                    HStack(spacing: 5) {
                        ForEach(steps.indices, id: \.self) { i in
                            Capsule()
                                .fill(i == index ? DS.Color.primary : DS.Color.ink.opacity(0.18))
                                .frame(width: i == index ? 16 : 6, height: 6)
                        }
                    }

                    Spacer(minLength: 0)

                    Button(action: onFinish) {
                        Text(AppLocalizer.string("coach.skip", defaultValue: "Passer"))
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    .buttonStyle(.plain)

                    Button(action: advance) {
                        Text(isLast
                             ? AppLocalizer.string("coach.done", defaultValue: "C'est parti")
                             : AppLocalizer.string("coach.next", defaultValue: "Suivant"))
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DS.Color.primaryForeground)
                            .padding(.horizontal, 18)
                            .frame(height: 38)
                            .background(DS.Color.primary)
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
                .padding(.top, 2)
            }
            .padding(16)
            .frame(maxWidth: 340, alignment: .leading)
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .shadow(color: .black.opacity(0.28), radius: 18, y: 8)
            .padding(.horizontal, 18)
            .position(
                x: proxy.size.width / 2,
                y: bubbleBelowSpotlight
                    ? min(spotlight.maxY + 130, proxy.size.height - 130)
                    : max(spotlight.minY - 130, 150)
            )
        }
    }

    private func advance() {
        if isLast {
            onFinish()
        } else {
            withAnimation(.easeInOut(duration: 0.28)) { index += 1 }
        }
    }
}

// MARK: - Découpe inversée

private extension View {
    /// Perce un trou dans la vue à l'endroit du masque fourni.
    func reverseMask<Mask: View>(@ViewBuilder _ mask: () -> Mask) -> some View {
        self.mask(
            ZStack {
                Rectangle()
                mask()
                    .blendMode(.destinationOut)
            }
            .compositingGroup()
        )
    }
}
