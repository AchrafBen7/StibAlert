import Foundation

enum AppConfig {
    static let isBackendEnabled = true
    static let backendBaseURL = "https://stib-alert-backend.onrender.com"

    static let teamID = "SLUL8PUP37"
    static let bundleID = "com.ehb.StibAlert"
    static let appGroupID = "group.com.ehb.StibAlert"

    /// URL partagée par "Inviter un ami". Tant que l'App Store ID n'est pas
    /// attribué (post-submission), on partage la page support publique
    /// (lien stable et utile au destinataire). Dès qu'on a l'ID, remplacer
    /// par `https://apps.apple.com/app/id<ID>`.
    static let shareAppURL = URL(string: "\(backendBaseURL)/support")!
}
