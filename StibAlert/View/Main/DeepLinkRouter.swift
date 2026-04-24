import Foundation

enum DeepLink: Equatable {
    case home
    case signalements
    case favorites
    case profile
    case report(signalementId: String?)
    case line(number: String)
    case signalementDetail(id: String)
    case stibiCommute
    case stibi
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
        case "stibi":
            if segments.first == "commute" { return .stibiCommute }
            return .stibi
        default:
            return nil
        }
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
