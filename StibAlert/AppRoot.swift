import SwiftUI

struct AppRoot: View {
    @StateObject private var nav = AppNavigation()

    var body: some View {
        HomeView()
            .environmentObject(nav)
    }
}
