import SwiftUI

enum AppPage {
    case home
    case signalements
    case reports
    case favorites
    case profile
    case profileMain
}

final class AppNavigation: ObservableObject {
    @Published var currentPage: AppPage = .home
    @Published var showReportSheet = false
    @Published var showSideMenu = false
    @Published var showAuthFlow = false
    @Published var pendingLineFocus: String?
    @Published var pendingReportFocus: String?
    @Published var pendingReportStopBackendId: String?
    @Published var pendingMapStopFocusBackendId: String?
    @Published var pendingReportsScopeRawValue: String?
}
