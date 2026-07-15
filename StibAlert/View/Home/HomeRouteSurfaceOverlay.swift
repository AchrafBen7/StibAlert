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
    var backendUnreachable: Bool = false
    let selectedRouteDetail: HomeRouteOption?
    let shouldShowRouteSheet: Bool
    let shouldShowRouteDetail: Bool
    let onSelect: (HomeRouteOption) -> Void
    let onCloseRouteSheet: () -> Void
    let onBackFromRouteDetail: () -> Void
    let onCloseRouteDetail: () -> Void
    let onShowRouteMap: () -> Void
    /// Replanifier depuis un autre départ tapé dans le détail (comme Google Maps).
    var onSelectDeparture: (Date) -> Void = { _ in }

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
                    backendUnreachable: backendUnreachable,
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
        // Une seule injection pour les deux feuilles (sheet compact + détail) : taper
        // un « autre départ » recalcule le trajet depuis cette heure.
        .environment(\.routeReplan, onSelectDeparture)
    }
}
