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
    ///
    /// En anglais on retombe sur le français : la STIB ne publie ses
    /// communiqués qu'en FR et NL, il n'existe donc AUCUNE source anglaise à
    /// servir ici. Le français est le repli le plus lisible à Bruxelles.
    var localized: String? {
        AppLocale.languageCode == "nl"
            ? (trimmedOrNil(nl) ?? trimmedOrNil(fr))
            : (trimmedOrNil(fr) ?? trimmedOrNil(nl))
    }
}

extension TransportLabelDTO: BackendLocalizedText {
    /// Celui-ci porte un vrai champ `en`. Il restait en DERNIER recours même
    /// pour un anglophone, qui lisait donc du français alors que sa langue
    /// était disponible dans la charge utile.
    var localized: String? {
        switch AppLocale.languageCode {
        case "nl": return trimmedOrNil(nl) ?? trimmedOrNil(fr) ?? trimmedOrNil(en)
        case "en": return trimmedOrNil(en) ?? trimmedOrNil(fr) ?? trimmedOrNil(nl)
        default:   return trimmedOrNil(fr) ?? trimmedOrNil(nl) ?? trimmedOrNil(en)
        }
    }
}

extension LigneDestinationDTO: BackendLocalizedText {}
extension LigneNearbyDestination: BackendLocalizedText {}
