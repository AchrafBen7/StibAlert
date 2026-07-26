import Foundation

enum AppConfig {
    static let isBackendEnabled = true
    static let backendBaseURL = "https://stib-alert-backend.onrender.com"

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
