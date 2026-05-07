import Foundation

enum DeepLink: Equatable {
    case home
    case signalements
    case favorites
    case profile
    case report(signalementId: String?)
    case line(number: String)
    case signalementDetail(id: String)
    case route(fromName: String, fromLat: Double, fromLng: Double, toName: String, toLat: Double, toLng: Double)
}

enum DeepLinkRouter {
    static let scheme = "stibalert"

    static func parse(_ url: URL) -> DeepLink? {
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
