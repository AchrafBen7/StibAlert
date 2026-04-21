import SwiftUI

enum AuthRoute: Hashable {
    case signUp
    case activation
}

struct AuthFlowView: View {
    @EnvironmentObject private var session: AuthSession
    @State private var path: [AuthRoute] = []

    var body: some View {
        NavigationStack(path: $path) {
            LoginView(onGoToSignUp: { path.append(.signUp) })
                .navigationDestination(for: AuthRoute.self) { route in
                    switch route {
                    case .signUp:
                        SignUpView(onRequireActivation: { path.append(.activation) })
                    case .activation:
                        ActivationView()
                    }
                }
        }
    }
}
