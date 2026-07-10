import Foundation

/// Le backend renvoie certains textes déjà traduits (`{ "fr": …, "nl": … }`) :
/// libellés d'état de ligne, destinations, statuts d'arrêt.
///
/// Le client lisait **toujours `.fr`**, quelle que soit la langue de l'app : un
/// utilisateur en néerlandais voyait « Trafic perturbé » au milieu d'une interface
/// néerlandaise. Ce n'était pas un texte gelé dans le code — il venait du serveur.
///
/// `localized` choisit la langue CHOISIE DANS L'APP (Profil → Langues), avec un
/// repli sur l'autre langue puis l'anglais : mieux vaut un texte dans la mauvaise
/// langue que pas de texte du tout.
protocol BackendLocalizedText {
    var fr: String? { get }
    var nl: String? { get }
}

/// Un texte vide côté serveur doit se comporter comme un texte absent, sinon le
/// repli sur l'autre langue ne se déclenche jamais.
private func trimmedOrNil(_ value: String?) -> String? {
    guard let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines),
          !trimmed.isEmpty else { return nil }
    return trimmed
}

extension BackendLocalizedText {
    /// Texte dans la langue de l'app, avec repli sur l'autre langue.
    var localized: String? {
        AppLocale.languageCode == "nl"
            ? (trimmedOrNil(nl) ?? trimmedOrNil(fr))
            : (trimmedOrNil(fr) ?? trimmedOrNil(nl))
    }
}

extension TransportLabelDTO: BackendLocalizedText {
    /// `TransportLabelDTO` porte aussi un `en` : dernier recours seulement.
    var localized: String? {
        AppLocale.languageCode == "nl"
            ? (trimmedOrNil(nl) ?? trimmedOrNil(fr) ?? trimmedOrNil(en))
            : (trimmedOrNil(fr) ?? trimmedOrNil(nl) ?? trimmedOrNil(en))
    }
}

extension LigneDestinationDTO: BackendLocalizedText {}
extension LigneNearbyDestination: BackendLocalizedText {}
