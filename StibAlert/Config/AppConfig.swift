import Foundation

enum AppConfig {
    static let isBackendEnabled = true
    /// Domaine À NOUS devant le backend (CNAME api → Render). L'app ne connaît
    /// plus l'hébergeur : on peut changer de région (ex. Oregon → Frankfurt) ou
    /// d'hébergeur en re-pointant ce seul CNAME, SANS republier l'app — y
    /// compris pour les versions déjà installées. Avant, l'URL Render était en
    /// dur : toute migration aurait cassé les apps existantes.
    static let backendBaseURL = "https://api.blayse.app"

    static let teamID = "SLUL8PUP37"
    static let bundleID = "com.ehb.StibAlert"
    static let appGroupID = "group.com.ehb.StibAlert"

    /// URL partagée par "Inviter un ami" → la fiche App Store (ID attribué le
    /// 2026-07-22 à l'approbation). Avant, on partageait `<backend>/support` :
    /// un ami recevait l'URL TECHNIQUE de l'API sur une page d'aide, au lieu
    /// d'un lien pour installer l'app. Le backend ne doit jamais être exposé
    /// aux utilisateurs — le site public, c'est blayse.app.
    static let shareAppURL = URL(string: "https://apps.apple.com/app/id6772360018")!
}
