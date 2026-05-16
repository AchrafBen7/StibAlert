import SwiftUI
import PassKit

/// SwiftUI wrapper around PassKit's PKAddPassesViewController so we can
/// present a `.pkpass` blob downloaded from the backend as a regular sheet.
/// Calls back with success/failure when the user dismisses the add-flow.
struct AddPassToWalletSheet: UIViewControllerRepresentable {
    let passData: Data
    let onFinish: (Result<Void, Error>) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onFinish: onFinish)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        do {
            let pass = try PKPass(data: passData)
            guard let controller = PKAddPassesViewController(pass: pass) else {
                let placeholder = UIViewController()
                DispatchQueue.main.async {
                    onFinish(.failure(WalletPresentationError.cannotPresent))
                }
                return placeholder
            }
            controller.delegate = context.coordinator
            return controller
        } catch {
            let placeholder = UIViewController()
            DispatchQueue.main.async {
                onFinish(.failure(error))
            }
            return placeholder
        }
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    final class Coordinator: NSObject, PKAddPassesViewControllerDelegate {
        let onFinish: (Result<Void, Error>) -> Void
        init(onFinish: @escaping (Result<Void, Error>) -> Void) {
            self.onFinish = onFinish
        }

        func addPassesViewControllerDidFinish(_ controller: PKAddPassesViewController) {
            onFinish(.success(()))
        }
    }
}

enum WalletPresentationError: LocalizedError {
    case cannotPresent
    var errorDescription: String? {
        switch self {
        case .cannotPresent: return "Apple Wallet n'est pas disponible sur cet appareil."
        }
    }
}
