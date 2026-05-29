import Foundation

/// Catalogue typé des chaînes UI prioritaires (boutons, erreurs, empty states,
/// CTA, accessibility). Toutes les entrées passent par `String(localized:)`
/// pour être auto-extraites par Xcode dans `Localizable.xcstrings`.
///
/// Migration progressive :
/// - `Text("Hello")` est déjà auto-localisé par SwiftUI ; ne pas le remplacer.
/// - `String` assignée à un `@State` (errors, status messages) → wrap avec
///   `L10n.Errors.networkUnavailable` ou ajouter la clé ici.
/// - Pour interpoler : `L10n.Auth.activationSentMessage("alice@ex.com")`.
///
/// Conventions de naming :
/// - `Group.descriptiveAction` (lowerCamelCase pour le membre)
/// - clé String dans `Localizable.xcstrings` : `group.snake_case`
/// - clés courantes regroupées dans `Common` ; spécifiques par feature.
enum L10n {
    enum Common {
        static var appName: String { String(localized: "common.app_name", defaultValue: "StibAlert") }
        static var continueAction: String { String(localized: "common.continue", defaultValue: "Continuer") }
        static var finishAction: String { String(localized: "common.finish", defaultValue: "Terminer") }
        static var cancel: String { String(localized: "common.cancel", defaultValue: "Annuler") }
        static var ok: String { String(localized: "common.ok", defaultValue: "OK") }
        static var close: String { String(localized: "common.close", defaultValue: "Fermer") }
        static var save: String { String(localized: "common.save", defaultValue: "Enregistrer") }
        static var edit: String { String(localized: "common.edit", defaultValue: "Modifier") }
        static var delete: String { String(localized: "common.delete", defaultValue: "Supprimer") }
        static var send: String { String(localized: "common.send", defaultValue: "Envoyer") }
        static var share: String { String(localized: "common.share", defaultValue: "Partager") }
        static var retry: String { String(localized: "common.retry", defaultValue: "Réessayer") }
        static var loading: String { String(localized: "common.loading", defaultValue: "Chargement…") }
        static var refresh: String { String(localized: "common.refresh", defaultValue: "Rafraîchir") }
        static var done: String { String(localized: "common.done", defaultValue: "Terminé") }
        static var skip: String { String(localized: "common.skip", defaultValue: "Passer") }
        static var openSettings: String { String(localized: "common.open_settings", defaultValue: "Ouvrir les réglages") }
        static var guestName: String { String(localized: "common.guest_name", defaultValue: "Invité") }
        static var authenticationTitle: String { String(localized: "common.authentication_title", defaultValue: "Authentification") }
        static var login: String { String(localized: "common.login", defaultValue: "Se connecter") }
        static var register: String { String(localized: "common.register", defaultValue: "S'inscrire") }
    }

    enum Errors {
        static var networkUnavailable: String { String(localized: "errors.network_unavailable", defaultValue: "Réseau indisponible. Vérifie ta connexion.") }
        static var unknownError: String { String(localized: "errors.unknown", defaultValue: "Une erreur est survenue. Réessaie.") }
        static var sessionExpired: String { String(localized: "errors.session_expired", defaultValue: "Ta session a expiré. Reconnecte-toi.") }
        static var loadFailed: String { String(localized: "errors.load_failed", defaultValue: "Impossible de charger les données.") }
        static var saveFailed: String { String(localized: "errors.save_failed", defaultValue: "Enregistrement impossible. Réessaie.") }
        static var permissionDenied: String { String(localized: "errors.permission_denied", defaultValue: "Permission refusée.") }
        static var locationDenied: String { String(localized: "errors.location_denied", defaultValue: "Autorise la localisation dans Réglages pour utiliser cette fonction.") }
        static var micDenied: String { String(localized: "errors.mic_denied", defaultValue: "Autorise le micro dans Réglages.") }
        static var pushDenied: String { String(localized: "errors.push_denied", defaultValue: "Autorise les notifications dans Réglages.") }
        static var emailInvalid: String { String(localized: "errors.email_invalid", defaultValue: "Format d'email invalide") }
        static var passwordTooShort: String { String(localized: "errors.password_too_short", defaultValue: "8 caractères minimum") }
        static var deleteAccountFailed: String { String(localized: "errors.delete_account_failed", defaultValue: "Suppression impossible. Réessaie dans un instant.") }
        static var connectionLimited: String { String(localized: "errors.connection_limited", defaultValue: "Connexion limitée — données en cache") }
    }

    enum EmptyStates {
        static var noResults: String { String(localized: "empty.no_results", defaultValue: "Aucun résultat") }
        static var noLineFound: String { String(localized: "empty.no_line_found", defaultValue: "Aucune ligne trouvée") }
        static var noReports: String { String(localized: "empty.no_reports", defaultValue: "Aucun signalement") }
        static var noFavorites: String { String(localized: "empty.no_favorites", defaultValue: "Aucun favori pour le moment") }
        static var noStopsNearby: String { String(localized: "empty.no_stops_nearby", defaultValue: "Aucun arrêt à proximité") }
        static var noTripPlanned: String { String(localized: "empty.no_trip_planned", defaultValue: "Aucun trajet planifié") }
        static var resetSearchHint: String { String(localized: "empty.reset_search_hint", defaultValue: "Réinitialise la recherche pour voir tous les résultats.") }
        static var seeAllLines: String { String(localized: "empty.see_all_lines", defaultValue: "Voir toutes les lignes") }
    }

    enum Onboarding {
        static var page1Title: String { String(localized: "onboarding.page1.title") }
        static var page1Subtitle: String { String(localized: "onboarding.page1.subtitle") }
        static var page2Title: String { String(localized: "onboarding.page2.title") }
        static var page2Subtitle: String { String(localized: "onboarding.page2.subtitle") }
        static var page3Title: String { String(localized: "onboarding.page3.title") }
        static var page3Subtitle: String { String(localized: "onboarding.page3.subtitle") }
        static var skipFavorites: String { String(localized: "onboarding.skip_favorites") }
        static var skipFavoritesWithFallback: String { String(localized: "onboarding.skip_favorites_with_fallback") }
        static var discoverAlone: String { String(localized: "onboarding.discover_alone") }
    }

    enum Auth {
        static var emailPlaceholder: String { String(localized: "auth.email_placeholder") }
        static var passwordPlaceholder: String { String(localized: "auth.password_placeholder") }
        static var fullNamePlaceholder: String { String(localized: "auth.full_name_placeholder") }
        static var forgotPassword: String { String(localized: "auth.forgot_password") }
        static var noAccount: String { String(localized: "auth.no_account") }
        static var alreadyAccount: String { String(localized: "auth.already_account") }
        static var loginSuccessTitle: String { String(localized: "auth.login_success_title") }
        static var otpPrompt: String { String(localized: "auth.otp_prompt") }
        static var otpPlaceholder: String { String(localized: "auth.otp_placeholder") }
        static var activateAccount: String { String(localized: "auth.activate_account") }
        static var activationTitle: String { String(localized: "auth.activation_title") }
        static var activationSentTitle: String { String(localized: "auth.activation_sent_title") }
        static func activationSentMessage(_ email: String) -> String {
            String(format: String(localized: "auth.activation_sent_message"), email)
        }
        static var codeSentTitle: String { String(localized: "auth.code_sent_title") }
        static var loginSegment: String { String(localized: "auth.segment_login") }
        static var registerSegment: String { String(localized: "auth.segment_register") }
        static var optionsPickerLabel: String { String(localized: "auth.options_picker_label") }
        static var emailInvalidInline: String { String(localized: "auth.email_invalid_inline") }
        static var passwordCriteriaMinLength: String { String(localized: "auth.password_criteria_min_length") }
        static var passwordCriteriaUppercase: String { String(localized: "auth.password_criteria_uppercase") }
        static var passwordCriteriaDigit: String { String(localized: "auth.password_criteria_digit") }
        static var passwordCriteriaRecommended: String { String(localized: "auth.password_criteria_recommended") }
        static var signInInstead: String { String(localized: "auth.sign_in_instead") }
    }

    enum Home {
        static var latestReports: String { String(localized: "home.latest_reports") }
        static var noReportsToday: String { String(localized: "home.no_reports_today") }
        static var otherReports: String { String(localized: "home.other_reports") }
        static var guestModeTitle: String { String(localized: "home.guest_mode_title") }
        static var guestModeSubtitle: String { String(localized: "home.guest_mode_subtitle") }
        static var guestModeCTA: String { String(localized: "home.guest_mode_cta") }
        static func errorPrefix(_ message: String) -> String {
            String(format: String(localized: "home.error_prefix"), message)
        }
        static func greeting(_ name: String) -> String {
            String(format: String(localized: "home.greeting"), name)
        }
    }

    enum Reports {
        static var describeSituation: String { String(localized: "reports.describe_situation") }
        static var describeSituationBonus: String { String(localized: "reports.describe_situation_bonus") }
        static var descriptionPlaceholder: String { String(localized: "reports.description_placeholder") }
        static var descriptionOptional: String { String(localized: "reports.description_optional") }
        static var descriptionEncouragement: String { String(localized: "reports.description_encouragement") }
        static var descriptionThanks: String { String(localized: "reports.description_thanks") }
        static var submit: String { String(localized: "reports.submit") }
        static var submitted: String { String(localized: "reports.submitted") }
        static var stillBlocked: String { String(localized: "reports.vote.still_blocked") }
        static var nowResolved: String { String(localized: "reports.vote.now_resolved") }
        static var voteHintTitle: String { String(localized: "reports.vote.hint_title") }
        static var voteHintBody: String { String(localized: "reports.vote.hint_body") }
        static var dopamineTipTitle: String { String(localized: "reports.dopamine_tip.title") }
        static var dopamineTipBody: String { String(localized: "reports.dopamine_tip.body") }
    }

    enum Voice {
        static var idle: String { String(localized: "voice.idle", defaultValue: "Parle à Mobi") }
        static var listening: String { String(localized: "voice.listening", defaultValue: "Je t'écoute…") }
        static var thinking: String { String(localized: "voice.thinking", defaultValue: "Je réfléchis…") }
        static var speaking: String { String(localized: "voice.speaking", defaultValue: "Mobi") }
        static var error: String { String(localized: "voice.error", defaultValue: "Oups") }
        static var startSpeaking: String { String(localized: "voice.start_speaking", defaultValue: "Parler") }
        static var stopSpeaking: String { String(localized: "voice.stop_speaking", defaultValue: "Arrêter") }
        static var sendNow: String { String(localized: "voice.send_now", defaultValue: "Envoyer") }
        static var retry: String { String(localized: "voice.retry", defaultValue: "Réessayer") }
        static var switchToText: String { String(localized: "voice.switch_to_text", defaultValue: "Continuer en mode texte") }
        static var setupMic: String { String(localized: "voice.setup_mic", defaultValue: "Régler le micro") }
        static var micDeniedMessage: String {
            String(
                localized: "voice.mic_denied_message",
                defaultValue: "Autorise le micro et la reconnaissance vocale dans Réglages pour parler à Mobi — ou continue en mode texte."
            )
        }
        static var seeRouteOnMap: String { String(localized: "voice.see_route_on_map", defaultValue: "Voir la route sur la carte") }
        static var goAhead: String { String(localized: "voice.go_ahead", defaultValue: "Vas-y, parle…") }
        static var askAgain: String { String(localized: "voice.ask_again", defaultValue: "Reparler") }
    }

    enum Notifications {
        static var preTripTitle: String { String(localized: "notifications.pre_trip.title") }
        static var preTripBody: String { String(localized: "notifications.pre_trip.body") }
        static var preTripExample: String { String(localized: "notifications.pre_trip.example") }
        static var communityTitle: String { String(localized: "notifications.community.title") }
        static var communityBody: String { String(localized: "notifications.community.body") }
        static var communityExample: String { String(localized: "notifications.community.example") }
        static var thanksTitle: String { String(localized: "notifications.thanks.title") }
        static var thanksBody: String { String(localized: "notifications.thanks.body") }
        static var thanksExample: String { String(localized: "notifications.thanks.example") }
        static var quietHoursTitle: String { String(localized: "notifications.quiet_hours.title") }
        static var quietHoursBody: String { String(localized: "notifications.quiet_hours.body") }
        static var quietHoursException: String { String(localized: "notifications.quiet_hours.example") }
        static var trustNoMarketing: String { String(localized: "notifications.trust_no_marketing") }
    }

    enum Schedules {
        static var title: String { String(localized: "schedules.title", defaultValue: "Horaires") }
        static var searchPlaceholder: String { String(localized: "schedules.search_placeholder", defaultValue: "Chercher une ligne") }
        static var searchStationPlaceholder: String { String(localized: "schedules.search_station_placeholder", defaultValue: "Chercher une gare") }
        static var noLineFound: String { String(localized: "schedules.no_line_found", defaultValue: "Aucune ligne trouvée") }
        static func resetSearchHint(_ operatorName: String) -> String {
            String(format: String(localized: "schedules.reset_search_hint", defaultValue: "Réinitialise la recherche pour voir toutes les lignes %@."), operatorName)
        }
        static var seeAllLines: String { String(localized: "schedules.see_all_lines", defaultValue: "Voir toutes les lignes") }
        static var loadFailed: String { String(localized: "schedules.load_failed", defaultValue: "Impossible de charger les lignes") }
        static var cacheLimitedTitle: String { String(localized: "schedules.cache_limited_title", defaultValue: "Connexion limitée") }
        static var cacheLimitedSubtitle: String { String(localized: "schedules.cache_limited_subtitle", defaultValue: "Données en cache · Tape pour réessayer") }
    }

    enum Profile {
        static var deleteAccount: String { String(localized: "profile.delete_account") }
        static var deleteAccountConfirm: String { String(localized: "profile.delete_account.confirm") }
        static var deleteAccountIrreversible: String { String(localized: "profile.delete_account.irreversible") }
        static var quietHoursWindow: String { String(localized: "profile.quiet_hours.window") }
        static var quietHoursEditAction: String { String(localized: "profile.quiet_hours.edit") }
    }

    enum Splash {
        static var accessibilityLogo: String { String(localized: "splash.logo_accessibility") }
        static var subtitle: String { String(localized: "splash.subtitle") }
    }
}
