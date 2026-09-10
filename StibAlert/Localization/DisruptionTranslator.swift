import Foundation
import SwiftUI

/// Traduction À LA DEMANDE du texte qui vient des opérateurs.
///
/// Le problème : la STIB ne publie ses communiqués qu'en FR et NL. Un
/// anglophone voit donc une interface anglaise et un texte de perturbation
/// français. Aucune source anglaise n'existe — il faut traduire nous-mêmes.
///
/// Choix : le framework `Translation` d'Apple, SUR L'APPAREIL. Gratuit, sans
/// clé d'API, sans un octet envoyé à un serveur — ce qui préserve la promesse
/// « pas de tracking » de l'app. L'alternative (traduire côté serveur avec un
/// modèle payant) coûterait un abonnement et chargerait une instance déjà
/// juste en mémoire, pour un résultat identique.
///
/// ⚠️ La première traduction déclenche le téléchargement d'un pack de langue
/// par iOS (plusieurs centaines de Mo). C'est pour ça que RIEN n'est traduit
/// automatiquement au départ : l'utilisateur appuie sur « Translate » une
/// première fois, en connaissance de cause. Une fois qu'il a accepté, on
/// bascule en automatique — même geste que Safari.
@MainActor
final class DisruptionTranslator: ObservableObject {
    static let shared = DisruptionTranslator()

    /// Vrai dès que l'utilisateur a traduit une première fois avec succès.
    /// À partir de là, le reste se traduit sans lui redemander.
    @Published private(set) var autoTranslate: Bool

    /// Texte source -> texte traduit. La clé est le texte lui-même : un même
    /// communiqué revient sur plusieurs écrans (carte, alertes, détail) et ne
    /// doit être traduit qu'une fois.
    @Published private(set) var translations: [String: String] = [:]

    /// Textes en cours de traduction, pour ne pas relancer la même demande
    /// quand deux vues affichent le même communiqué au même instant.
    private var inFlight: Set<String> = []

    private static let autoKey = "disruptionAutoTranslate"

    private init() {
        autoTranslate = UserDefaults.standard.bool(forKey: Self.autoKey)
        translations = Self.loadFromDisk()
    }

    // MARK: - Disponibilité

    /// On ne propose la traduction QUE si l'app est en anglais.
    ///
    /// Un francophone lit déjà le texte d'origine, et un néerlandophone reçoit
    /// presque toujours la version NL publiée par la STIB : leur proposer un
    /// bouton serait du bruit. iOS 18 est exigé par `TranslationSession`.
    var isOffered: Bool {
        guard #available(iOS 18.0, *) else { return false }
        return AppLocale.languageCode == "en"
    }

    /// Langue vers laquelle traduire, au format BCP-47.
    var targetLanguage: String { AppLocale.languageCode }

    // MARK: - Cache

    func translation(for source: String) -> String? {
        translations[Self.normalize(source)]
    }

    /// Le texte à AFFICHER : la traduction si elle existe, l'original sinon.
    ///
    /// Réservé aux endroits où l'on ne peut pas insérer une vue — typiquement
    /// deux `Text` concaténés par `+`, qui doivent rester des `Text` et non
    /// devenir un conteneur. Ces endroits n'ont pas de bouton : ils profitent
    /// des traductions faites ailleurs, puisque le cache est partagé.
    func display(_ source: String) -> String {
        translation(for: source) ?? source
    }

    func isTranslating(_ source: String) -> Bool {
        inFlight.contains(Self.normalize(source))
    }

    func markInFlight(_ source: String) {
        inFlight.insert(Self.normalize(source))
    }

    func store(source: String, translated: String) {
        let key = Self.normalize(source)
        inFlight.remove(key)
        let clean = translated.trimmingCharacters(in: .whitespacesAndNewlines)
        // Une traduction vide, ou identique à la source, n'apporte rien et
        // ferait clignoter l'interface entre deux textes équivalents.
        guard !clean.isEmpty, clean != source else { return }
        translations[key] = clean
        Self.saveToDisk(translations)
    }

    func failed(_ source: String) {
        inFlight.remove(Self.normalize(source))
    }

    /// Bascule en automatique après le premier succès explicite.
    func enableAuto() {
        guard !autoTranslate else { return }
        autoTranslate = true
        UserDefaults.standard.set(true, forKey: Self.autoKey)
    }

    func disableAuto() {
        autoTranslate = false
        UserDefaults.standard.set(false, forKey: Self.autoKey)
        translations = [:]
        Self.saveToDisk([:])
    }

    /// Les communiqués arrivent avec des espaces et retours à la ligne
    /// capricieux : sans normalisation, le même texte occuperait deux entrées
    /// de cache et serait traduit deux fois.
    private static func normalize(_ text: String) -> String {
        text.trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
    }

    // MARK: - Persistance

    /// Plafond volontaire : un cache de traductions n'a aucune raison de
    /// grossir sans fin, et il vit dans Caches — que le système peut purger.
    private static let maxEntries = 400

    private static var fileURL: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        return caches.appendingPathComponent("disruption-translations.json")
    }

    private static func loadFromDisk() -> [String: String] {
        guard let url = fileURL, let data = try? Data(contentsOf: url) else { return [:] }
        return (try? JSONDecoder().decode([String: String].self, from: data)) ?? [:]
    }

    private static func saveToDisk(_ map: [String: String]) {
        guard let url = fileURL else { return }
        var trimmed = map
        if trimmed.count > maxEntries {
            // Pas d'ordre d'insertion dans un dictionnaire : on repart d'un
            // sous-ensemble plutôt que de laisser le fichier enfler.
            trimmed = Dictionary(uniqueKeysWithValues: Array(trimmed.prefix(maxEntries)))
        }
        guard let data = try? JSONEncoder().encode(trimmed) else { return }
        try? data.write(to: url, options: .atomic)
    }
}
