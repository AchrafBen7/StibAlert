import Foundation

/// Persiste les recherches **récentes** + les raccourcis **Domicile / Travail**
/// (comme Google Maps). Tout est local (UserDefaults, JSON) — aucune donnée
/// serveur. Alimente l'état « découverte » de la recherche quand le champ est vide.
final class SearchQuickAccessStore: ObservableObject {
    enum SavedSlot { case home, work }

    @Published private(set) var recents: [SearchPlace] = []
    @Published private(set) var home: SearchPlace?
    @Published private(set) var work: SearchPlace?

    /// Quand l'utilisateur veut définir Domicile/Travail, la prochaine sélection
    /// est enregistrée dans ce slot au lieu de lancer un trajet.
    @Published var pendingSaveSlot: SavedSlot?

    private let recentsKey = "search.recents.v1"
    private let homeKey = "search.home.v1"
    private let workKey = "search.work.v1"
    private let maxRecents = 8

    init() {
        recents = Self.load([SearchPlace].self, key: recentsKey) ?? []
        home = Self.load(SearchPlace.self, key: homeKey)
        work = Self.load(SearchPlace.self, key: workKey)
    }

    func addRecent(_ place: SearchPlace) {
        // Déduplique (par nom + coordonnée), plus récent en tête, borné.
        var updated = recents.filter {
            $0.name != place.name || $0.coordinate != place.coordinate
        }
        updated.insert(place, at: 0)
        if updated.count > maxRecents {
            updated = Array(updated.prefix(maxRecents))
        }
        recents = updated
        Self.persist(recents, key: recentsKey)
    }

    func clearRecents() {
        recents = []
        UserDefaults.standard.removeObject(forKey: recentsKey)
    }

    func save(_ place: SearchPlace, to slot: SavedSlot) {
        switch slot {
        case .home:
            home = place
            Self.persist(place, key: homeKey)
        case .work:
            work = place
            Self.persist(place, key: workKey)
        }
    }

    func place(for slot: SavedSlot) -> SearchPlace? {
        slot == .home ? home : work
    }

    // MARK: - Persistence

    private static func persist<T: Encodable>(_ value: T, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
        }
    }

    private static func load<T: Decodable>(_ type: T.Type, key: String) -> T? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(T.self, from: data)
    }
}
