import Foundation

/// Affichage d'un prochain passage.
///
/// Règle : en dessous d'une heure, l'attente en minutes est ce qui parle
/// (« 7 min ») ; au-delà, c'est l'heure de passage qui compte (« 04:52 »).
/// Personne ne calcule 01:05 + 238 minutes de tête — et « 238 min » était
/// exactement ce que la fiche compacte affichait la nuit, alors que la page
/// de détail, un tap plus loin, montrait déjà l'heure. Les deux écrans
/// dupliquaient la même règle ; ils partagent désormais celle-ci.
enum DepartureTimeFormat {
    /// Au-delà de ce seuil, une attente en minutes ne veut plus rien dire.
    static let farThresholdMinutes = 60

    /// Heure locale de l'appareil : on suit les réglages régionaux (24 h en
    /// Belgique, 12 h ailleurs) plutôt que d'imposer un format.
    ///
    /// Construit à chaque appel plutôt que partagé : `DateFormatter` n'est pas
    /// sûr en accès concurrent, et rien ne garantit que ce libellé ne sera
    /// jamais demandé hors du fil principal. Quelques rangées par fiche, le
    /// coût est invisible.
    private static func makeClock() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale.autoupdatingCurrent
        formatter.timeStyle = .short
        formatter.dateStyle = .none
        return formatter
    }

    /// - Parameters:
    ///   - minutes: attente annoncée par le serveur.
    ///   - absoluteDate: heure de passage exacte si le serveur la fournit
    ///     (`realtimeDepartureAt` / `scheduledDepartureAt`) ; sinon on la
    ///     reconstruit depuis l'attente.
    static func label(minutes: Int, absoluteDate: Date? = nil, now: Date = Date()) -> String {
        guard minutes > 0 else {
            return AppLocalizer.string("realtime.now", defaultValue: "maintenant")
        }
        guard minutes >= farThresholdMinutes else {
            return AppLocalizer.format("departure.in_minutes", defaultValue: "%lld min", minutes)
        }
        let date = absoluteDate ?? now.addingTimeInterval(TimeInterval(minutes) * 60)
        return makeClock().string(from: date)
    }

    /// Vrai quand le passage est si loin qu'on affiche une heure, pas une attente.
    static func isFarAway(minutes: Int) -> Bool { minutes >= farThresholdMinutes }
}

extension TransportDepartureDTO {
    /// Heure de passage annoncée par le serveur, temps réel en priorité.
    var announcedDepartureDate: Date? { realtimeDepartureAt ?? scheduledDepartureAt }

    /// Libellé prêt à afficher, selon la règle partagée.
    var departureLabel: String {
        DepartureTimeFormat.label(minutes: minutes, absoluteDate: announcedDepartureDate)
    }
}
