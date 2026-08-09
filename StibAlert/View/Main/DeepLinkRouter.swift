import Foundation

enum DeepLink: Equatable {
    case home
    case signalements
    case favorites
    case profile
    case report(signalementId: String?)
    case line(number: String)
    case signalementDetail(id: String)
    /// BUG #3 — push communityClusterAlertService envoyait
    /// `stibalert://clusters/{clusterIndex}` mais cette case n'existait pas
    /// → fallback nil → AppRoot ne routait pas → tap push atterrissait sur
    /// Home sans contexte.
    case clusterDetail(clusterIndex: String)
    case route(fromName: String, fromLat: Double, fromLng: Double, toName: String, toLat: Double, toLng: Double)
}

enum DeepLinkRouter {
    static let scheme = "stibalert"

    /// Domaine des liens partageables — voir `webLink(forSignalement:)`.
    static let webHost = "blayse.app"

    static func parse(_ url: URL) -> DeepLink? {
        // Un lien HTTPS partagé arrive par le MÊME `onOpenURL` que le schéma
        // interne. Sans cette branche, le `guard` ci-dessous rejetait
        // silencieusement toute ouverture depuis une conversation.
        if let webLink = parseWebLink(url) { return webLink }

        guard url.scheme?.lowercased() == scheme else { return nil }
        let host = url.host?.lowercased() ?? ""
        let segments = url.path
            .split(separator: "/")
            .map { $0.lowercased() }

        switch host {
        case "home", "map":
            return .home
        case "signalements", "lines":
            return .signalements
        case "favorites", "favoris":
            return .favorites
        case "profile", "profil":
            return .profile
        case "report":
            return .report(signalementId: segments.first)
        case "line":
            guard let number = segments.first else { return nil }
            return .line(number: number)
        case "signalement":
            guard let id = segments.first else { return nil }
            return .signalementDetail(id: id)
        case "clusters", "cluster":
            // BUG #3 — Routing nouveau pour les push community cluster.
            // Accepte "clusters" (envoyé par backend) ET "cluster" (cas où
            // un futur callsite oublierait le pluriel).
            guard let clusterIndex = segments.first else { return nil }
            return .clusterDetail(clusterIndex: clusterIndex)
        case "route":
            let comps = URLComponents(url: url, resolvingAgainstBaseURL: false)
            let qis = comps?.queryItems ?? []
            func q(_ key: String) -> String? { qis.first(where: { $0.name == key })?.value }
            guard let fromName = q("fromName"),
                  let fromLat = q("fromLat").flatMap(Double.init),
                  let fromLng = q("fromLng").flatMap(Double.init),
                  let toName = q("toName"),
                  let toLat = q("toLat").flatMap(Double.init),
                  let toLng = q("toLng").flatMap(Double.init) else { return .home }
            return .route(fromName: fromName, fromLat: fromLat, fromLng: fromLng, toName: toName, toLat: toLat, toLng: toLng)
        default:
            return nil
        }
    }

    /// Le lien qu'on met dans un message partagé.
    ///
    /// L'ancien `stibalert://signalement/{id}` était du **texte mort** pour qui
    /// n'a pas l'app : un schéma privé, qu'aucune messagerie ni navigateur ne
    /// sait ouvrir. Or c'est précisément aux non-utilisateurs que ce message
    /// s'adresse. Une URL HTTPS ouvre l'app si elle est installée (Universal
    /// Link) et, sinon, une page qui montre la perturbation et propose l'App
    /// Store — et elle affiche un aperçu riche dans la conversation.
    static func webLink(forSignalement id: String) -> URL? {
        URL(string: "https://\(webHost)/s/\(id)")
    }

    /// Chemins déclarés dans l'`apple-app-site-association` du domaine. Y
    /// ajouter un chemin ici SANS l'ajouter au fichier servi ne produit rien :
    /// iOS ne consulte que le fichier.
    private static func parseWebLink(_ url: URL) -> DeepLink? {
        guard url.scheme?.lowercased() == "https",
              let host = url.host?.lowercased(),
              host == webHost || host == "www.\(webHost)"
        else { return nil }

        let segments = url.path.split(separator: "/").map(String.init)
        guard segments.count >= 2 else { return nil }

        switch segments[0].lowercased() {
        case "s", "signalement":
            // ⚠️ Pas de `lowercased()` sur l'identifiant : un ObjectId Mongo est
            // hexadécimal, mais un identifiant externe ne l'est pas forcément.
            // Abaisser la casse ici casserait la recherche côté serveur.
            return .signalementDetail(id: segments[1])
        default:
            return nil
        }
    }

    static func routeURL(fromName: String, fromLat: Double, fromLng: Double, toName: String, toLat: Double, toLng: Double) -> URL? {
        var comps = URLComponents()
        comps.scheme = scheme
        comps.host = "route"
        comps.queryItems = [
            .init(name: "fromName", value: fromName),
            .init(name: "fromLat", value: String(fromLat)),
            .init(name: "fromLng", value: String(fromLng)),
            .init(name: "toName", value: toName),
            .init(name: "toLat", value: String(toLat)),
            .init(name: "toLng", value: String(toLng))
        ]
        return comps.url
    }

    static func parse(_ raw: String?) -> DeepLink? {
        guard let raw, let url = URL(string: raw) else { return nil }
        return parse(url)
    }

    /// Extracts a deep_link payload from a OneSignal / APNs push userInfo dictionary.
    static func extractRawDeepLink(from userInfo: [AnyHashable: Any]?) -> String? {
        if let raw = userInfo?["deep_link"] as? String { return raw }
        if let custom = userInfo?["custom"] as? [String: Any],
           let raw = custom["deep_link"] as? String { return raw }
        return nil
    }
}
