import SwiftUI

enum AppPage {
    case home
    case signalements
    case favorites
    case profile
    case profileMain
}

final class AppNavigation: ObservableObject {
    @Published var currentPage: AppPage = .home
    @Published var showReportSheet = false
    @Published var showSideMenu = false
    @Published var showAuthFlow = false
}
