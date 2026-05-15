import SwiftUI

/// Z-index hierarchy for all overlays.
///
/// Values reflect existing rendering order — preview cards sit ABOVE the tab bar
/// (controls remain reachable around them), full detail sheets sit ABOVE the
/// tab bar AND hide it via `shouldShowTabBar`.
enum ZLayer: Double {
    case map = 0
    case mapPins = 1
    case backgroundPage = 1.1
    case controls = 2
    case searchHeader = 3
    case allClearChip = 3.1
    case reportSheet = 5
    case pageOverlay = 6
    case stopPreview = 7
    case bottomChrome = 8
    case mapLegend = 9
    case routeDetail = 9.1
    case stopDetail = 10
    case clusterDetail = 11
    case authGate = 100
    case modalDropdown = 1000
}

extension View {
    /// Apply a semantic z-index from the unified hierarchy.
    func zLayer(_ layer: ZLayer) -> some View {
        zIndex(layer.rawValue)
    }
}
