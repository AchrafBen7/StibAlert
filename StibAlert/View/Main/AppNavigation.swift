import SwiftUI

enum AppPage {
    case home
    case schedules        // "Horaires" — lines catalog + search by stop
    case signalements
    case reports          // "Infos trafic" tab (formerly "Live")
    case favorites
    case profile
}

final class AppNavigation: ObservableObject {
    @Published var currentPage: AppPage = .home
    @Published var showReportSheet = false
    @Published var showSideMenu = false
    @Published var showAuthFlow = false
    @Published var authInitialRoute: AuthRoute?
    @Published var pendingLineFocus: String?
    @Published var pendingReportFocus: String?
    @Published var pendingReportStopBackendId: String?
    @Published var pendingMapStopFocusBackendId: String?
    @Published var pendingReportsScopeRawValue: String?
}
