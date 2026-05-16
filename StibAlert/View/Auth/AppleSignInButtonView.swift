import SwiftUI
import AuthenticationServices

/// Wraps `SignInWithAppleButton` so callers receive a clean async callback
/// with the identity token + optional full name. Token verification happens
/// on the backend via /api/utilisateurs/apple-signin.
struct AppleSignInButtonView: View {
    @Environment(\.colorScheme) private var colorScheme
    let onResult: (Result<AppleSignInPayload, Error>) -> Void

    var body: some View {
        SignInWithAppleButton(
            .continue,
            onRequest: { request in
                request.requestedScopes = [.fullName, .email]
            },
            onCompletion: { result in
                switch result {
                case .success(let auth):
                    guard let credential = auth.credential as? ASAuthorizationAppleIDCredential else {
                        onResult(.failure(AppleSignInError.invalidCredential))
                        return
                    }
                    guard let tokenData = credential.identityToken,
                          let identityToken = String(data: tokenData, encoding: .utf8) else {
                        onResult(.failure(AppleSignInError.missingIdentityToken))
                        return
                    }
                    let fullName: String? = {
                        guard let nameComponents = credential.fullName else { return nil }
                        let formatter = PersonNameComponentsFormatter()
                        formatter.style = .default
                        let formatted = formatter.string(from: nameComponents).trimmingCharacters(in: .whitespacesAndNewlines)
                        return formatted.isEmpty ? nil : formatted
                    }()
                    onResult(.success(AppleSignInPayload(
                        identityToken: identityToken,
                        fullName: fullName
                    )))
                case .failure(let error):
                    onResult(.failure(error))
                }
            }
        )
        .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
        .frame(height: 48)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
    }
}

struct AppleSignInPayload {
    let identityToken: String
    let fullName: String?
}

enum AppleSignInError: LocalizedError {
    case invalidCredential
    case missingIdentityToken

    var errorDescription: String? {
        switch self {
        case .invalidCredential: return "Identifiant Apple invalide."
        case .missingIdentityToken: return "Token Apple manquant."
        }
    }
}
