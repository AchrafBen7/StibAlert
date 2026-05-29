import Foundation

/// 1 retry sur erreurs réseau "transient" pour absorber les cold start Render
/// (~10 s au réveil après inactivité, malgré le keep-warm 24/7 qui a parfois
/// des trous lors des deploys).
///
/// Spec : 1ère tentative → si timeout / connection lost → wait 2 s → 2e
/// tentative. Pas plus — on ne veut pas masquer les vraies pannes en
/// boucle infinie.
///
/// Usage :
/// ```swift
/// return try await coldStartRetry {
///     try await APIClient.shared.request(path)
/// }
/// ```
@discardableResult
func coldStartRetry<T>(
    delaySeconds: Double = 2,
    _ block: () async throws -> T
) async throws -> T {
    do {
        return try await block()
    } catch let error as URLError where Self_isColdStartError(error) {
        try? await Task.sleep(nanoseconds: UInt64(delaySeconds * 1_000_000_000))
        return try await block()
    }
}

/// Codes URLError considérés comme transitoires (typiques d'un dyno qui se
/// réveille). On EXCLUT volontairement `.cannotFindHost` ou `.badURL` qui
/// sont des vraies erreurs (DNS down, URL malformée).
private func Self_isColdStartError(_ error: URLError) -> Bool {
    switch error.code {
    case .timedOut,
         .notConnectedToInternet,
         .networkConnectionLost,
         .dataNotAllowed,
         .internationalRoamingOff:
        return true
    default:
        return false
    }
}
