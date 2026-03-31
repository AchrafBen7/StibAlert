import SwiftUI

final class MainTabSelection: ObservableObject {
    @Published var currentTab: MainTabView.Tab = .map
}
