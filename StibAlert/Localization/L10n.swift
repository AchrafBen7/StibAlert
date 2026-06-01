import Foundation

/// Catalogue typé des chaînes UI prioritaires (boutons, erreurs, empty states,
/// CTA, accessibility). Toutes les entrées passent par `AppLocalizer`
/// pour respecter le changement de langue dans l'app sans redémarrage.
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
        static var appName: String { AppLocalizer.string("common.app_name", defaultValue: "StibAlert") }
        static var continueAction: String { AppLocalizer.string("common.continue", defaultValue: "Continuer") }
        static var finishAction: String { AppLocalizer.string("common.finish", defaultValue: "Terminer") }
        static var cancel: String { AppLocalizer.string("common.cancel", defaultValue: "Annuler") }
        static var ok: String { AppLocalizer.string("common.ok", defaultValue: "OK") }
        static var close: String { AppLocalizer.string("common.close", defaultValue: "Fermer") }
        static var save: String { AppLocalizer.string("common.save", defaultValue: "Enregistrer") }
        static var edit: String { AppLocalizer.string("common.edit", defaultValue: "Modifier") }
        static var delete: String { AppLocalizer.string("common.delete", defaultValue: "Supprimer") }
        static var send: String { AppLocalizer.string("common.send", defaultValue: "Envoyer") }
        static var share: String { AppLocalizer.string("common.share", defaultValue: "Partager") }
        static var retry: String { AppLocalizer.string("common.retry", defaultValue: "Réessayer") }
        static var loading: String { AppLocalizer.string("common.loading", defaultValue: "Chargement…") }
        static var refresh: String { AppLocalizer.string("common.refresh", defaultValue: "Rafraîchir") }
        static var done: String { AppLocalizer.string("common.done", defaultValue: "Terminé") }
        static var skip: String { AppLocalizer.string("common.skip", defaultValue: "Passer") }
        static var openSettings: String { AppLocalizer.string("common.open_settings", defaultValue: "Ouvrir les réglages") }
        static var guestName: String { AppLocalizer.string("common.guest_name", defaultValue: "Invité") }
        static var authenticationTitle: String { AppLocalizer.string("common.authentication_title", defaultValue: "Authentification") }
        static var login: String { AppLocalizer.string("common.login", defaultValue: "Se connecter") }
        static var register: String { AppLocalizer.string("common.register", defaultValue: "S'inscrire") }
    }

    enum Errors {
        static var networkUnavailable: String { AppLocalizer.string("errors.network_unavailable", defaultValue: "Réseau indisponible. Vérifie ta connexion.") }
        static var unknownError: String { AppLocalizer.string("errors.unknown", defaultValue: "Une erreur est survenue. Réessaie.") }
        static var sessionExpired: String { AppLocalizer.string("errors.session_expired", defaultValue: "Ta session a expiré. Reconnecte-toi.") }
        static var loadFailed: String { AppLocalizer.string("errors.load_failed", defaultValue: "Impossible de charger les données.") }
        static var saveFailed: String { AppLocalizer.string("errors.save_failed", defaultValue: "Enregistrement impossible. Réessaie.") }
        static var permissionDenied: String { AppLocalizer.string("errors.permission_denied", defaultValue: "Permission refusée.") }
        static var locationDenied: String { AppLocalizer.string("errors.location_denied", defaultValue: "Autorise la localisation dans Réglages pour utiliser cette fonction.") }
        static var micDenied: String { AppLocalizer.string("errors.mic_denied", defaultValue: "Autorise le micro dans Réglages.") }
        static var pushDenied: String { AppLocalizer.string("errors.push_denied", defaultValue: "Autorise les notifications dans Réglages.") }
        static var emailInvalid: String { AppLocalizer.string("errors.email_invalid", defaultValue: "Format d'email invalide") }
        static var passwordTooShort: String { AppLocalizer.string("errors.password_too_short", defaultValue: "8 caractères minimum") }
        static var deleteAccountFailed: String { AppLocalizer.string("errors.delete_account_failed", defaultValue: "Suppression impossible. Réessaie dans un instant.") }
        static var connectionLimited: String { AppLocalizer.string("errors.connection_limited", defaultValue: "Connexion limitée — données en cache") }
    }

    enum EmptyStates {
        static var noResults: String { AppLocalizer.string("empty.no_results", defaultValue: "Aucun résultat") }
        static var noLineFound: String { AppLocalizer.string("empty.no_line_found", defaultValue: "Aucune ligne trouvée") }
        static var noReports: String { AppLocalizer.string("empty.no_reports", defaultValue: "Aucun signalement") }
        static var noFavorites: String { AppLocalizer.string("empty.no_favorites", defaultValue: "Aucun favori pour le moment") }
        static var noStopsNearby: String { AppLocalizer.string("empty.no_stops_nearby", defaultValue: "Aucun arrêt à proximité") }
        static var noTripPlanned: String { AppLocalizer.string("empty.no_trip_planned", defaultValue: "Aucun trajet planifié") }
        static var resetSearchHint: String { AppLocalizer.string("empty.reset_search_hint", defaultValue: "Réinitialise la recherche pour voir tous les résultats.") }
        static var seeAllLines: String { AppLocalizer.string("empty.see_all_lines", defaultValue: "Voir toutes les lignes") }
    }

    enum Onboarding {
        static var page1Title: String { AppLocalizer.string("onboarding.page1.title") }
        static var page1Subtitle: String { AppLocalizer.string("onboarding.page1.subtitle") }
        static var page2Title: String { AppLocalizer.string("onboarding.page2.title") }
        static var page2Subtitle: String { AppLocalizer.string("onboarding.page2.subtitle") }
        static var page3Title: String { AppLocalizer.string("onboarding.page3.title") }
        static var page3Subtitle: String { AppLocalizer.string("onboarding.page3.subtitle") }
        static var skipFavorites: String { AppLocalizer.string("onboarding.skip_favorites") }
        static var skipFavoritesWithFallback: String { AppLocalizer.string("onboarding.skip_favorites_with_fallback") }
        static var discoverAlone: String { AppLocalizer.string("onboarding.discover_alone") }
    }

    enum Auth {
        static var emailPlaceholder: String { AppLocalizer.string("auth.email_placeholder") }
        static var passwordPlaceholder: String { AppLocalizer.string("auth.password_placeholder") }
        static var fullNamePlaceholder: String { AppLocalizer.string("auth.full_name_placeholder") }
        static var forgotPassword: String { AppLocalizer.string("auth.forgot_password") }
        static var noAccount: String { AppLocalizer.string("auth.no_account") }
        static var alreadyAccount: String { AppLocalizer.string("auth.already_account") }
        static var loginSuccessTitle: String { AppLocalizer.string("auth.login_success_title") }
        static var otpPrompt: String { AppLocalizer.string("auth.otp_prompt") }
        static var otpPlaceholder: String { AppLocalizer.string("auth.otp_placeholder") }
        static var activateAccount: String { AppLocalizer.string("auth.activate_account") }
        static var activationTitle: String { AppLocalizer.string("auth.activation_title") }
        static var activationSentTitle: String { AppLocalizer.string("auth.activation_sent_title") }
        static func activationSentMessage(_ email: String) -> String {
            AppLocalizer.format("auth.activation_sent_message", email)
        }
        static var codeSentTitle: String { AppLocalizer.string("auth.code_sent_title") }
        static var loginSegment: String { AppLocalizer.string("auth.segment_login") }
        static var registerSegment: String { AppLocalizer.string("auth.segment_register") }
        static var optionsPickerLabel: String { AppLocalizer.string("auth.options_picker_label") }
        static var emailInvalidInline: String { AppLocalizer.string("auth.email_invalid_inline") }
        static var passwordCriteriaMinLength: String { AppLocalizer.string("auth.password_criteria_min_length") }
        static var passwordCriteriaUppercase: String { AppLocalizer.string("auth.password_criteria_uppercase") }
        static var passwordCriteriaDigit: String { AppLocalizer.string("auth.password_criteria_digit") }
        static var passwordCriteriaRecommended: String { AppLocalizer.string("auth.password_criteria_recommended") }
        static var signInInstead: String { AppLocalizer.string("auth.sign_in_instead") }
    }

    enum Home {
        static var latestReports: String { AppLocalizer.string("home.latest_reports") }
        static var noReportsToday: String { AppLocalizer.string("home.no_reports_today") }
        static var otherReports: String { AppLocalizer.string("home.other_reports") }
        static var guestModeTitle: String { AppLocalizer.string("home.guest_mode_title") }
        static var guestModeSubtitle: String { AppLocalizer.string("home.guest_mode_subtitle") }
        static var guestModeCTA: String { AppLocalizer.string("home.guest_mode_cta") }
        static func errorPrefix(_ message: String) -> String {
            AppLocalizer.format("home.error_prefix", message)
        }
        static func greeting(_ name: String) -> String {
            AppLocalizer.format("home.greeting", name)
        }
    }

    enum Reports {
        static var describeSituation: String { AppLocalizer.string("reports.describe_situation") }
        static var describeSituationBonus: String { AppLocalizer.string("reports.describe_situation_bonus") }
        static var descriptionPlaceholder: String { AppLocalizer.string("reports.description_placeholder") }
        static var descriptionOptional: String { AppLocalizer.string("reports.description_optional") }
        static var descriptionEncouragement: String { AppLocalizer.string("reports.description_encouragement") }
        static var descriptionThanks: String { AppLocalizer.string("reports.description_thanks") }
        static var submit: String { AppLocalizer.string("reports.submit") }
        static var submitted: String { AppLocalizer.string("reports.submitted") }
        static var stillBlocked: String { AppLocalizer.string("reports.vote.still_blocked") }
        static var nowResolved: String { AppLocalizer.string("reports.vote.now_resolved") }
        static var voteHintTitle: String { AppLocalizer.string("reports.vote.hint_title") }
        static var voteHintBody: String { AppLocalizer.string("reports.vote.hint_body") }
        static var dopamineTipTitle: String { AppLocalizer.string("reports.dopamine_tip.title") }
        static var dopamineTipBody: String { AppLocalizer.string("reports.dopamine_tip.body") }
    }

    enum Voice {
        static var idle: String { AppLocalizer.string("voice.idle", defaultValue: "Parle à Mobi") }
        static var listening: String { AppLocalizer.string("voice.listening", defaultValue: "Je t'écoute…") }
        static var thinking: String { AppLocalizer.string("voice.thinking", defaultValue: "Je réfléchis…") }
        static var speaking: String { AppLocalizer.string("voice.speaking", defaultValue: "Mobi") }
        static var error: String { AppLocalizer.string("voice.error", defaultValue: "Oups") }
        static var startSpeaking: String { AppLocalizer.string("voice.start_speaking", defaultValue: "Parler") }
        static var stopSpeaking: String { AppLocalizer.string("voice.stop_speaking", defaultValue: "Arrêter") }
        static var sendNow: String { AppLocalizer.string("voice.send_now", defaultValue: "Envoyer") }
        static var retry: String { AppLocalizer.string("voice.retry", defaultValue: "Réessayer") }
        static var switchToText: String { AppLocalizer.string("voice.switch_to_text", defaultValue: "Continuer en mode texte") }
        static var setupMic: String { AppLocalizer.string("voice.setup_mic", defaultValue: "Régler le micro") }
        static var micDeniedMessage: String {
            AppLocalizer.string(
                "voice.mic_denied_message",
                defaultValue: "Autorise le micro et la reconnaissance vocale dans Réglages pour parler à Mobi — ou continue en mode texte."
            )
        }
        static var seeRouteOnMap: String { AppLocalizer.string("voice.see_route_on_map", defaultValue: "Voir la route sur la carte") }
        static var goAhead: String { AppLocalizer.string("voice.go_ahead", defaultValue: "Vas-y, parle…") }
        static var askAgain: String { AppLocalizer.string("voice.ask_again", defaultValue: "Reparler") }
    }

    enum Notifications {
        static var preTripTitle: String { AppLocalizer.string("notifications.pre_trip.title") }
        static var preTripBody: String { AppLocalizer.string("notifications.pre_trip.body") }
        static var preTripExample: String { AppLocalizer.string("notifications.pre_trip.example") }
        static var communityTitle: String { AppLocalizer.string("notifications.community.title") }
        static var communityBody: String { AppLocalizer.string("notifications.community.body") }
        static var communityExample: String { AppLocalizer.string("notifications.community.example") }
        static var thanksTitle: String { AppLocalizer.string("notifications.thanks.title") }
        static var thanksBody: String { AppLocalizer.string("notifications.thanks.body") }
        static var thanksExample: String { AppLocalizer.string("notifications.thanks.example") }
        static var quietHoursTitle: String { AppLocalizer.string("notifications.quiet_hours.title") }
        static var quietHoursBody: String { AppLocalizer.string("notifications.quiet_hours.body") }
        static var quietHoursException: String { AppLocalizer.string("notifications.quiet_hours.example") }
        static var trustNoMarketing: String { AppLocalizer.string("notifications.trust_no_marketing") }
    }

    enum Schedules {
        static var title: String { AppLocalizer.string("schedules.title", defaultValue: "Horaires") }
        static var searchPlaceholder: String { AppLocalizer.string("schedules.search_placeholder", defaultValue: "Chercher une ligne") }
        static var searchStationPlaceholder: String { AppLocalizer.string("schedules.search_station_placeholder", defaultValue: "Chercher une gare") }
        static var noLineFound: String { AppLocalizer.string("schedules.no_line_found", defaultValue: "Aucune ligne trouvée") }
        static func resetSearchHint(_ operatorName: String) -> String {
            AppLocalizer.format("schedules.reset_search_hint", defaultValue: "Réinitialise la recherche pour voir toutes les lignes %@.", operatorName)
        }
        static var seeAllLines: String { AppLocalizer.string("schedules.see_all_lines", defaultValue: "Voir toutes les lignes") }
        static var loadFailed: String { AppLocalizer.string("schedules.load_failed", defaultValue: "Impossible de charger les lignes") }
        static var cacheLimitedTitle: String { AppLocalizer.string("schedules.cache_limited_title", defaultValue: "Connexion limitée") }
        static var cacheLimitedSubtitle: String { AppLocalizer.string("schedules.cache_limited_subtitle", defaultValue: "Données en cache · Tape pour réessayer") }
    }

    enum Profile {
        static var deleteAccount: String { AppLocalizer.string("profile.delete_account") }
        static var deleteAccountConfirm: String { AppLocalizer.string("profile.delete_account.confirm") }
        static var deleteAccountIrreversible: String { AppLocalizer.string("profile.delete_account.irreversible") }
        static var quietHoursWindow: String { AppLocalizer.string("profile.quiet_hours.window") }
        static var quietHoursEditAction: String { AppLocalizer.string("profile.quiet_hours.edit") }
    }

    enum Splash {
        static var accessibilityLogo: String { AppLocalizer.string("splash.logo_accessibility") }
        static var subtitle: String { AppLocalizer.string("splash.subtitle") }
    }
}
