import Foundation

struct LigneEtatDTO: Decodable, Identifiable {
    var id: String { lineid }
    let lineid: String
    let nom: String?
    let nomRetour: String?
    let typeTransport: String?
    let couleur: String?
    let direction: String?
    let destination: LigneDestinationDTO?
    let incidents: Int
    let statut: String

    enum CodingKeys: String, CodingKey {
        case lineid, nom, nomRetour, typeTransport, couleur, direction, destination, incidents, statut
    }
}

struct LigneCatalogDTO: Decodable, Identifiable {
    var id: String { lineid }
    let lineid: String
    let nomComplet: String?
    let nomCompletRetour: String?
    let typeTransport: String?
    let couleur: String?
    let direction: String?
}

struct LigneDestinationDTO: Decodable, Equatable {
    let fr: String?
    let nl: String?
}

/// Cache mémoire + déduplication pour les endpoints « lignes », très sollicités
/// au lancement : Favoris, Signalements et Reports les chargent chacun de leur
/// côté. Le `RequestCoalescer` d'APIClient ne fusionne que les requêtes
/// EXACTEMENT simultanées ; or au cold start ces appels sont espacés de 2-3 s
/// (la 1re répond avant que la 3e parte) → on observait /api/lignes ×3 et
/// /etat-lignes ×2 en quelques secondes. Ce cache TTL absorbe la cascade :
/// 1 seul aller-retour réseau couvre toutes les vues du launch.
private actor LigneCache {
    static let shared = LigneCache()

    private var catalog: (value: [LigneCatalogDTO], at: Date)?
    private var catalogTask: Task<[LigneCatalogDTO], Error>?

    private var states: (value: [LigneEtatDTO], at: Date)?
    private var statesTask: Task<[LigneEtatDTO], Error>?

    // Catalogue quasi-immuable (noms/couleurs des lignes) → TTL long.
    private let catalogTTL: TimeInterval = 300
    // États (incidents/statut) → TTL court, suffisant pour couvrir la cascade
    // de chargement du launch sans masquer une évolution réelle trop longtemps.
    private let statesTTL: TimeInterval = 30

    func catalog(forceRefresh: Bool) async throws -> [LigneCatalogDTO] {
        if !forceRefresh, let cached = catalog, Date().timeIntervalSince(cached.at) < catalogTTL {
            return cached.value
        }
        // Une requête déjà en vol : tous les appelants partagent son résultat.
        if let task = catalogTask {
            return try await task.value
        }
        let task = Task<[LigneCatalogDTO], Error> {
            try await APIClient.shared.request("/api/lignes")
        }
        catalogTask = task
        defer { catalogTask = nil }
        let value = try await task.value
        catalog = (value, Date())
        return value
    }

    func states(forceRefresh: Bool) async throws -> [LigneEtatDTO] {
        if !forceRefresh, let cached = states, Date().timeIntervalSince(cached.at) < statesTTL {
            return cached.value
        }
        if let task = statesTask {
            return try await task.value
        }
        let task = Task<[LigneEtatDTO], Error> {
            try await APIClient.shared.request("/api/lignes/etat-lignes")
        }
        statesTask = task
        defer { statesTask = nil }
        let value = try await task.value
        states = (value, Date())
        return value
    }

    func invalidate() {
        catalog = nil
        states = nil
    }
}

enum LigneService {
    /// État live des lignes (incidents, statut). `forceRefresh: true` pour un
    /// pull-to-refresh manuel qui doit court-circuiter le cache.
    static func etatLignes(forceRefresh: Bool = false) async throws -> [LigneEtatDTO] {
        try await LigneCache.shared.states(forceRefresh: forceRefresh)
    }

    /// Catalogue complet des lignes (noms, couleurs) — quasi-statique.
    static func toutesLesLignes(forceRefresh: Bool = false) async throws -> [LigneCatalogDTO] {
        try await LigneCache.shared.catalog(forceRefresh: forceRefresh)
    }

    /// À appeler après une action qui change l'état (ex : nouveau signalement)
    /// pour forcer le prochain chargement à repartir du réseau.
    static func invalidateCache() async {
        await LigneCache.shared.invalidate()
    }
}
