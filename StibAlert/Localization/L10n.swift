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
        static var appName: String { AppLocalizer.string("common.app_name", defaultValue: "Blayse") }
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

    enum Routing {
        static var transport: String { AppLocalizer.string("routing.transport", defaultValue: "Transport") }
        static var bike: String { AppLocalizer.string("routing.bike", defaultValue: "Vélo") }
        static var walk: String { AppLocalizer.string("routing.walk", defaultValue: "À pied") }
        static var walking: String { AppLocalizer.string("routing.walking", defaultValue: "Marche") }
        static var routeStep: String { AppLocalizer.string("routing.step", defaultValue: "Étape") }
        static var connection: String { AppLocalizer.string("routing.connection", defaultValue: "Correspondance") }
        static var destination: String { AppLocalizer.string("routing.destination", defaultValue: "destination") }
        static var direct: String { AppLocalizer.string("routing.direct", defaultValue: "direct") }
        static var line: String { AppLocalizer.string("routing.line", defaultValue: "Ligne") }
        static var bus: String { AppLocalizer.string("routing.bus", defaultValue: "Bus") }
        static var metro: String { AppLocalizer.string("routing.metro", defaultValue: "Métro") }
        static var tram: String { AppLocalizer.string("routing.tram", defaultValue: "Tram") }
        static var now: String { AppLocalizer.string("routing.now", defaultValue: "Maintenant") }
        static var realtime: String { AppLocalizer.string("routing.realtime", defaultValue: "Temps réel") }
        static var scheduled: String { AppLocalizer.string("routing.scheduled", defaultValue: "Horaire prévu") }
        static var departure: String { AppLocalizer.string("routing.departure", defaultValue: "Départ") }
        static var arrival: String { AppLocalizer.string("routing.arrival", defaultValue: "Arrivée") }
        static var recommendedTrip: String { AppLocalizer.string("routing.recommended_trip", defaultValue: "Trajet recommandé") }
        static var to: String { AppLocalizer.string("routing.to", defaultValue: "Vers") }
        static var seeOnMap: String { AppLocalizer.string("routing.see_on_map", defaultValue: "Voir sur la carte") }
        static var detailedItinerary: String { AppLocalizer.string("routing.detailed_itinerary", defaultValue: "Itinéraire détaillé") }
        static var otherItineraries: String { AppLocalizer.string("routing.other_itineraries", defaultValue: "Autres itinéraires") }
        static var next: String { AppLocalizer.string("routing.next", defaultValue: "Prochain") }
        static var nextDeparture: String { AppLocalizer.string("routing.next_departure", defaultValue: "Prochain passage") }
        static var fastest: String { AppLocalizer.string("routing.fastest", defaultValue: "Rapide") }
        static var itinerary: String { AppLocalizer.string("routing.itinerary", defaultValue: "Itinéraire") }
        static var homePlace: String { AppLocalizer.string("routing.home_place", defaultValue: "Domicile") }
        static var workPlace: String { AppLocalizer.string("routing.work_place", defaultValue: "Travail") }
        static var addPlace: String { AppLocalizer.string("routing.add_place", defaultValue: "Ajouter") }
        static var more: String { AppLocalizer.string("routing.more", defaultValue: "Plus") }
        static var addresses: String { AppLocalizer.string("routing.addresses", defaultValue: "Adresses") }
        static var departureAddress: String { AppLocalizer.string("routing.departure_address", defaultValue: "Adresse de départ") }
        static var currentPosition: String { AppLocalizer.string("routing.current_position", defaultValue: "Votre position") }
        static var noItineraryTitle: String { AppLocalizer.string("routing.empty.title", defaultValue: "Aucun itinéraire calculé") }
        static var noItineraryBody: String {
            AppLocalizer.string(
                "routing.empty.body",
                defaultValue: "Active la localisation pour qu'on puisse calculer un trajet depuis ta position, ou choisis un point de départ dans la barre de recherche."
            )
        }
        static var chooseArrivalFromResults: String {
            AppLocalizer.string(
                "routing.choose_arrival_from_results",
                defaultValue: "Choisis une adresse dans les résultats pour éviter un mauvais itinéraire."
            )
        }
        static var currentPositionUnavailable: String {
            AppLocalizer.string("routing.current_position_unavailable", defaultValue: "Position actuelle indisponible.")
        }
        static var chooseDepartureFromResults: String {
            AppLocalizer.string("routing.choose_departure_from_results", defaultValue: "Choisis une adresse de départ dans les résultats.")
        }
        static var recalculatedTitle: String { AppLocalizer.string("routing.recalculated.title", defaultValue: "Itinéraire recalculé") }
        static var avoids: String { AppLocalizer.string("routing.avoids", defaultValue: "évite") }
        static var transitUnavailableTitle: String { AppLocalizer.string("routing.transit_unavailable.title", defaultValue: "Transport en commun indisponible") }
        static var transitUnavailableSubtitle: String { AppLocalizer.string("routing.transit_unavailable.subtitle", defaultValue: "Aucun itinéraire en transport en commun trouvé pour ce trajet. Voici les options à pied et à vélo.") }
        static var followItinerary: String { AppLocalizer.string("routing.follow_itinerary", defaultValue: "Suivre l’itinéraire") }
        static var takeNextTransport: String { AppLocalizer.string("routing.take_next_transport", defaultValue: "Prendre le transport suivant") }
        static var transportStep: String { AppLocalizer.string("routing.transport_step", defaultValue: "Étape transport") }
        static var bikeStep: String { AppLocalizer.string("routing.bike_step", defaultValue: "Étape à vélo") }
        static var walkStep: String { AppLocalizer.string("routing.walk_step", defaultValue: "Étape à pied") }
        static var transportInProgress: String { AppLocalizer.string("routing.transport_in_progress", defaultValue: "Transport en cours") }
        static var walkInProgress: String { AppLocalizer.string("routing.walk_in_progress", defaultValue: "Marche en cours") }
        static var bikeToNextStep: String { AppLocalizer.string("routing.bike_to_next_step", defaultValue: "Pédalez vers la prochaine étape") }
        static var duration: String { AppLocalizer.string("routing.duration", defaultValue: "Durée") }
        static var transfers: String { AppLocalizer.string("routing.transfers", defaultValue: "Transferts") }
        static var involvedLines: String { AppLocalizer.string("routing.involved_lines", defaultValue: "Lignes impliquées") }
        static var alternativeReason: String { AppLocalizer.string("routing.alternative_reason", defaultValue: "Pourquoi cette alternative") }
        static var choiceReading: String { AppLocalizer.string("routing.choice_reading", defaultValue: "Lecture du choix") }
        static var steps: String { AppLocalizer.string("routing.steps", defaultValue: "Étapes") }
        static var state: String { AppLocalizer.string("routing.state", defaultValue: "État") }
        static var reports: String { AppLocalizer.string("routing.reports", defaultValue: "Signalements") }
        static var goTo: String { AppLocalizer.string("routing.go_to", defaultValue: "Aller à") }
        static var returnTo: String { AppLocalizer.string("routing.return_to", defaultValue: "Retour à") }
        static var results: String { AppLocalizer.string("routing.results", defaultValue: "Résultats") }
        static var recent: String { AppLocalizer.string("routing.recent", defaultValue: "Récent") }
        static var address: String { AppLocalizer.string("routing.address", defaultValue: "Adresse") }
        static var brussels: String { AppLocalizer.string("routing.brussels", defaultValue: "Bruxelles") }
        static var noRecentSearch: String { AppLocalizer.string("routing.no_recent_search", defaultValue: "Aucune recherche récente") }
        static var recentTripsHint: String { AppLocalizer.string("routing.recent_trips_hint", defaultValue: "Tes derniers itinéraires apparaîtront ici.") }
        static var seeItineraries: String { AppLocalizer.string("routing.see_itineraries", defaultValue: "Voir les itinéraires") }
        static var useCurrentPosition: String { AppLocalizer.string("routing.use_current_position", defaultValue: "Utiliser ma position") }
        static var locationAccessDenied: String { AppLocalizer.string("routing.location_access_denied", defaultValue: "L'accès à la localisation est refusé.") }
        static var useCurrentPositionHint: String { AppLocalizer.string("routing.use_current_position_hint", defaultValue: "Utilisez votre position actuelle comme départ.") }
        static var searchDeparture: String { AppLocalizer.string("routing.search_departure", defaultValue: "Rechercher un départ") }
        static var searchDestination: String { AppLocalizer.string("routing.search_destination", defaultValue: "Rechercher une destination") }
        static var suggestions: String { AppLocalizer.string("routing.suggestions", defaultValue: "Suggestions") }
        static var nextThen: String { AppLocalizer.string("routing.then", defaultValue: "Ensuite") }
        static var stopGuidance: String { AppLocalizer.string("routing.stop_guidance", defaultValue: "Arrêter le guidage") }
        static var stopGuidanceHint: String { AppLocalizer.string("routing.stop_guidance_hint", defaultValue: "Quitte le guidage actif pour ce trajet.") }
        static var speakAgain: String { AppLocalizer.string("routing.speak_again", defaultValue: "Reparler") }
        static var previous: String { AppLocalizer.string("routing.previous", defaultValue: "Précédent") }
        static var nextAction: String { AppLocalizer.string("routing.next_action", defaultValue: "Suivant") }
        static var currentLocationPlace: String { AppLocalizer.string("routing.current_location_place", defaultValue: "Lieu position actuelle") }

        static func arrivalAt(_ time: String) -> String {
            AppLocalizer.format("routing.arrival_at", defaultValue: "Arrivée %@", time)
        }

        static func lateBy(_ minutes: Int) -> String {
            AppLocalizer.format("routing.late_by", defaultValue: "+ %d min vs prévu", minutes)
        }

        static func walkingMinutes(_ minutes: Int) -> String {
            AppLocalizer.format("routing.walking_minutes", defaultValue: "%d min à pied", minutes)
        }

        static func transportCount(_ count: Int) -> String {
            AppLocalizer.format("routing.transport_count", defaultValue: "%d transport", count)
        }

        static func transferCount(_ count: Int) -> String {
            AppLocalizer.format("routing.transfer_count", defaultValue: "%d corresp.", count)
        }

        static func stopCount(_ count: Int) -> String {
            count == 1
                ? AppLocalizer.string("routing.one_stop", defaultValue: "1 arrêt")
                : AppLocalizer.format("routing.stops_count", defaultValue: "%d arrêts", count)
        }

        static func line(_ code: String) -> String {
            AppLocalizer.format("routing.line_code", defaultValue: "Ligne %@", code)
        }

        static func walkTo(_ destination: String) -> String {
            AppLocalizer.format("routing.walk_to", defaultValue: "Marcher vers %@", destination)
        }

        static func waitTransfer(_ minutes: Int) -> String {
            AppLocalizer.format("routing.wait_transfer", defaultValue: "Attente %d min · correspondance", minutes)
        }

        static func suggestionLabel(_ title: String) -> String {
            AppLocalizer.format("routing.suggestion_label", defaultValue: "Suggestion %@", title)
        }

        static func placeLabel(_ name: String) -> String {
            AppLocalizer.format("routing.place_label", defaultValue: "Lieu %@", name)
        }

        static func bikeTo(_ destination: String) -> String {
            AppLocalizer.format("routing.bike_to", defaultValue: "Vélo vers %@", destination)
        }

        static func toward(_ destination: String) -> String {
            AppLocalizer.format("routing.toward", defaultValue: "Vers %@", destination)
        }

        static func direction(_ destination: String) -> String {
            AppLocalizer.format("routing.direction", defaultValue: "Direction %@", destination)
        }

        static func inMinutes(_ minutes: Int) -> String {
            minutes == 1
                ? AppLocalizer.string("routing.in_one_minute", defaultValue: "Dans 1 min")
                : AppLocalizer.format("routing.in_minutes", defaultValue: "Dans %d min", minutes)
        }

        static func atTime(_ time: String) -> String {
            AppLocalizer.format("routing.at_time", defaultValue: "À %@", time)
        }

        static func departingAt(_ time: String) -> String {
            AppLocalizer.format("routing.departing_at", defaultValue: "DÉP. %@", time)
        }

        static func scheduledAt(_ time: String) -> String {
            AppLocalizer.format("routing.scheduled_at", defaultValue: "PRÉVU %@", time)
        }

        static func timingDetail(_ source: String, departure: String, arrival: String) -> String {
            AppLocalizer.format("routing.timing_detail", defaultValue: "%@ · %@ → %@", source, departure, arrival)
        }

        static func departureDetail(_ source: String, departure: String) -> String {
            AppLocalizer.format("routing.departure_detail", defaultValue: "%@ · départ %@", source, departure)
        }

        static func transitSummary(_ count: Int) -> String {
            count == 1
                ? AppLocalizer.string("routing.one_line_summary", defaultValue: "1 ligne")
                : AppLocalizer.format("routing.lines_summary", defaultValue: "%d lignes", count)
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

    enum StopDetail {
        static var realtime: String { AppLocalizer.string("stop_detail.realtime", defaultValue: "Temps réel") }
        static var schedules: String { AppLocalizer.string("stop_detail.schedules", defaultValue: "Horaires") }
        static var around: String { AppLocalizer.string("stop_detail.around", defaultValue: "Autour") }
        static var report: String { AppLocalizer.string("stop_detail.report", defaultValue: "Signaler") }
        static func lines(_ count: Int) -> String {
            AppLocalizer.format("stop_detail.lines_count", defaultValue: "Lignes · %d", count)
        }
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
