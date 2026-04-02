import SwiftUI

enum AppPage {
    case home
    case signalements
    case favorites
    case profile
}

final class AppNavigation: ObservableObject {
    @Published var currentPage: AppPage = .home
    @Published var showReportSheet = false
}
