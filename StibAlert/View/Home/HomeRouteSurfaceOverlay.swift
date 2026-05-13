import SwiftUI

struct HomeRouteSurfaceOverlay: View {
    let options: [HomeRouteOption]
    let modeSummaries: [RouteModeSummary]
    @Binding var selectedRouteID: UUID?
    @Binding var isRouteSheetExpanded: Bool
    let selectedRouteDetail: HomeRouteOption?
    let selectedARRoute: HomeRouteOption?
    let shouldShowRouteSheet: Bool
    let shouldShowRouteDetail: Bool
    let shouldShowAR: Bool
    let onSelect: (HomeRouteOption) -> Void
    let onCloseRouteSheet: () -> Void
    let onBackFromRouteDetail: () -> Void
    let onCloseRouteDetail: () -> Void
    let onShowRouteMap: () -> Void
    let onStartAR: (HomeRouteOption) -> Void
    let onCloseAR: () -> Void

    var body: some View {
        Group {
            if shouldShowRouteSheet {
                RouteRecommendationsSheet(
                    options: options,
                    modeSummaries: modeSummaries,
                    selectedRouteID: $selectedRouteID,
                    isExpanded: $isRouteSheetExpanded,
                    onSelect: onSelect,
                    onClose: onCloseRouteSheet
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(8)
            }

            if shouldShowRouteDetail, let selectedRouteDetail {
                RouteItineraryDetailsView(
                    option: selectedRouteDetail,
                    onBack: onBackFromRouteDetail,
                    onClose: onCloseRouteDetail,
                    onShowMap: onShowRouteMap,
                    onStartAR: {
                        onStartAR(selectedRouteDetail)
                    }
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(9)
            }

            if shouldShowAR, let selectedARRoute {
                RouteARNavigationView(
                    option: selectedARRoute,
                    onClose: onCloseAR
                )
                .transition(.opacity)
                .zIndex(11)
            }
        }
    }
}
