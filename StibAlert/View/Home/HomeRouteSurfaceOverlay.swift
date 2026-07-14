import SwiftUI

struct HomeRouteSurfaceOverlay: View {
    let options: [HomeRouteOption]
    let modeSummaries: [RouteModeSummary]
    var blockedLines: [String] = []
    @Binding var selectedRouteID: UUID?
    @Binding var isRouteSheetExpanded: Bool
    @Binding var preferredOperator: String?
    @Binding var departureTime: Date?
    @Binding var transitModes: Set<RouteTransitMode>
    var isRouting: Bool = false
    var onFiltersChange: () -> Void = {}
    let selectedRouteDetail: HomeRouteOption?
    let shouldShowRouteSheet: Bool
    let shouldShowRouteDetail: Bool
    let onSelect: (HomeRouteOption) -> Void
    let onCloseRouteSheet: () -> Void
    let onBackFromRouteDetail: () -> Void
    let onCloseRouteDetail: () -> Void
    let onShowRouteMap: () -> Void

    var body: some View {
        Group {
            if shouldShowRouteSheet {
                RouteRecommendationsSheet(
                    options: options,
                    modeSummaries: modeSummaries,
                    blockedLines: blockedLines,
                    selectedRouteID: $selectedRouteID,
                    isExpanded: $isRouteSheetExpanded,
                    preferredOperator: $preferredOperator,
                    departureTime: $departureTime,
                    transitModes: $transitModes,
                    isRouting: isRouting,
                    onFiltersChange: onFiltersChange,
                    onSelect: onSelect,
                    onClose: onCloseRouteSheet
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zLayer(.bottomChrome)
            }

            if shouldShowRouteDetail, let selectedRouteDetail {
                RouteItineraryDetailsView(
                    option: selectedRouteDetail,
                    onBack: onBackFromRouteDetail,
                    onClose: onCloseRouteDetail,
                    onShowMap: onShowRouteMap
                )
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zLayer(.routeDetail)
            }
        }
    }
}
