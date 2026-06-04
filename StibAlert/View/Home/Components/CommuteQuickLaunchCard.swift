import SwiftUI

/// Quick-launch card pour le trajet quotidien (routine) configuré pendant
/// l'onboarding. Apparaît dans HomeView quand toutes ces conditions sont OK :
///
///   1. `session.currentUser?.routine?.enabled == true`
///   2. `routine.homeStopId` ET `routine.workStopId` non nuls
///   3. L'heure courante est dans une fenêtre d'utilité (matin pour aller
///      au travail ±90 min autour de `departureTime`, ou après-midi/soir
///      16h-20h pour le retour)
///
/// Au tap → délégue à HomeView via le callback `onLaunch(_:)` qui résout
/// stopId → coords puis pipe sur `buildRoute` (existant). Pas de nouveau
/// code routing.
///
/// LITE J-7 — pas de push pre-trip, pas d'in-trip alert. Juste le quick-
/// launch visible aux bonnes heures.
struct CommuteQuickLaunchCard: View {
    enum Direction {
        case toWork
        case toHome
    }

    let routine: CommuteRoutineDTO
    /// Asked when the user taps a direction. HomeView résout la routine
    /// (stopId → coords via TransportService.stop) et lance buildRoute.
    let onLaunch: (Direction) -> Void

    var body: some View {
        TimelineView(.everyMinute) { context in
            // Réévalué chaque minute pour que la direction "primary" passe
            // automatiquement de toWork (matin) à toHome (après-midi) sans
            // que le user ait à recharger la vue.
            cardContent(at: context.date)
        }
    }

    @ViewBuilder
    private func cardContent(at date: Date) -> some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(DS.Color.primary.opacity(0.15))
                Image(systemName: "tram.fill")
                    .font(.system(size: 18, weight: .black))
                    .foregroundStyle(DS.Color.primary)
            }
            .frame(width: 44, height: 44)

            VStack(alignment: .leading, spacing: 2) {
                Text("TON TRAJET QUOTIDIEN")
                    .font(.system(size: 9.5, weight: .black, design: .monospaced))
                    .tracking(1.8)
                    .foregroundStyle(DS.Color.inkMute)
                Text(headlineText(at: date))
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
            }
            Spacer(minLength: 4)

            // Bouton primary aligné sur la direction "logique" courante.
            primaryButton(at: date)
            // Bouton secondary pour l'autre sens, plus discret.
            secondaryButton(at: date)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(
            LinearGradient(
                colors: [DS.Color.paper, DS.Color.paper2.opacity(0.6)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        .shadow(color: DS.Color.ink.opacity(0.06), radius: 6, y: 2)
    }

    // MARK: - Direction logic

    /// Direction mise en avant selon l'heure du jour.
    private func primaryDirection(at date: Date) -> Direction {
        // Si on est entre 14h et 23h59 → priorité retour maison.
        // Sinon → priorité aller travail (matin + tôt après-midi).
        let hour = Calendar(identifier: .gregorian).component(.hour, from: date)
        return hour >= 14 ? .toHome : .toWork
    }

    private func headlineText(at date: Date) -> String {
        let dir = primaryDirection(at: date)
        let label = dir == .toWork ? routine.workLabel : routine.homeLabel
        let prefix = dir == .toWork ? L10n.Routing.goTo : L10n.Routing.returnTo
        return "\(prefix) \(label) · \(routine.departureTime)"
    }

    @ViewBuilder
    private func primaryButton(at date: Date) -> some View {
        let dir = primaryDirection(at: date)
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            onLaunch(dir)
        } label: {
            Text(dir == .toWork ? L10n.Routing.workPlace : L10n.Routing.homePlace)
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Color.primaryForeground)
                .padding(.horizontal, 12)
                .frame(height: 32)
                .background(DS.Color.primary)
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(dir == .toWork ? "Lancer le trajet vers le travail" : "Lancer le trajet vers la maison")
    }

    @ViewBuilder
    private func secondaryButton(at date: Date) -> some View {
        let otherDir: Direction = primaryDirection(at: date) == .toWork ? .toHome : .toWork
        Button {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onLaunch(otherDir)
        } label: {
            Image(systemName: otherDir == .toWork ? "briefcase.fill" : "house.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 32, height: 32)
                .background(DS.Color.paper2.opacity(0.7))
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .accessibilityLabel(otherDir == .toWork ? "Aller au travail" : "Retour à la maison")
    }
}

extension CommuteQuickLaunchCard {
    /// Critère d'affichage. Le card n'apparaît QUE pendant les fenêtres
    /// d'utilité (matin commute + retour soir), pour ne pas polluer la
    /// home le reste de la journée.
    static func shouldShow(routine: CommuteRoutineDTO?, now: Date) -> Bool {
        guard let routine, routine.enabled else { return false }
        guard routine.homeStopId != nil, routine.workStopId != nil else { return false }

        let hour = Calendar(identifier: .gregorian).component(.hour, from: now)
        // Fenêtre matin (5h-12h) ou après-midi/soir (14h-23h).
        return (5...12).contains(hour) || (14...23).contains(hour)
    }
}
