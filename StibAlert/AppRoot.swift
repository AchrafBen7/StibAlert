import SwiftUI

struct AppRoot: View {
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = AuthSession()

    var body: some View {
        Group {
            switch session.state {
            case .unknown:
                ZStack {
                    AppTheme.Colors.onboardingBackground.ignoresSafeArea()
                    ProgressView().tint(.white)
                }
            case .signedOut:
                if AppConfig.isBackendEnabled {
                    AuthFlowView()
                } else {
                    HomeView()
                }
            case .signedIn:
                HomeView()
            }
        }
        .environmentObject(nav)
        .environmentObject(session)
        .task { await session.bootstrap() }
    }
}
