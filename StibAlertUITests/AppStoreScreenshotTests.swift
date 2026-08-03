import XCTest

/// Captures des écrans de la fiche App Store, en français et en néerlandais.
///
///     xcodebuild test -scheme StibAlert \
///       -destination 'platform=iOS Simulator,name=iPhone 17 Pro Max' \
///       -only-testing:StibAlertUITests/AppStoreScreenshotTests \
///       SCREENSHOT_LANG=fr
///
/// Les captures sortent en pièces jointes du `.xcresult`.
final class AppStoreScreenshotTests: XCTestCase {

    /// Libellés des onglets par langue : on tape un VRAI bouton plutôt qu'une
    /// coordonnée. Taper à l'aveugle donnait des captures identiques, le doigt
    /// tombant à côté.
    private static let tabs: [String: [String]] = [
        "fr": ["Carte", "Lignes", "Alertes", "Favoris", "Profil"],
        "nl": ["Kaart", "Lijnen", "Meldingen", "Favorieten", "Profiel"],
    ]

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testCaptureAppStoreScreens() throws {
        let language = ProcessInfo.processInfo.environment["SCREENSHOT_LANG"] ?? "fr"
        let labels = Self.tabs[language] ?? Self.tabs["fr"]!

        let app = XCUIApplication()
        // DEUX réglages, pas un seul. `appLanguageOverride` ne couvre que les
        // textes passant par `AppLocalizer` ; la majorité de l'interface est
        // faite de littéraux SwiftUI, résolus par `Bundle.main` selon la langue
        // SYSTÈME. Sans `-AppleLanguages`, la capture « nl » sortait
        // entièrement en français.
        app.launchArguments += [
            "-AppleLanguages", "(\(language))",
            "-AppleLocale", language == "nl" ? "nl_BE" : "fr_BE",
            "-appLanguageOverride", language,
            "-hasSeenOnboarding", "YES",
            "-hasLaunchedBefore", "YES",
            "-hasAcceptedPrivacyConsent", "YES",
            "-hasSeenHomeCoachMarks", "YES",
            "-hasSeenFeatureTour", "YES",
        ]
        app.launch()

        // La carte charge fond de plan, arrêts proches, véhicules et incidents.
        sleep(14)
        capture(app, "1_map")

        // Pas de tap sur une pastille d'arrêt : interroger les éléments de la
        // carte fait expirer la requête (des centaines d'annotations), et taper
        // une coordonnée à l'aveugle rendait une capture identique à la carte.
        // La fiche d'arrêt sera photographiée à la main si besoin.

        // 3 — Liste des lignes.
        if tapTab(app, labels[1]) {
            sleep(6)
            capture(app, "3_lines")

            // 4 — Détail d'une ligne (première rangée de la liste).
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.42)).tap()
            sleep(7)
            capture(app, "4_line_detail")
        }

        // 5 — Alertes.
        if tapTab(app, labels[2]) {
            sleep(6)
            capture(app, "5_alerts")
        }

        // 6 — Favoris.
        if tapTab(app, labels[3]) {
            sleep(5)
            capture(app, "6_favorites")
        }
    }

    // MARK: - Outils

    private func capture(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Tape un onglet par son libellé, en essayant bouton puis texte : la barre
    /// est un composant SwiftUI maison, son exposition varie.
    @discardableResult
    private func tapTab(_ app: XCUIApplication, _ label: String) -> Bool {
        let button = app.buttons[label]
        if button.waitForExistence(timeout: 4), button.isHittable {
            button.tap()
            return true
        }
        let text = app.staticTexts[label]
        if text.waitForExistence(timeout: 2), text.isHittable {
            text.tap()
            return true
        }
        return false
    }

}
