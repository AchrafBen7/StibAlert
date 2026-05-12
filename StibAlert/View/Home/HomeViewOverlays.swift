import SwiftUI

// MARK: - HomeView Overlay Extensions

extension HomeView {
    @ViewBuilder
    var mainBodyOverlays: some View {
        // Report sheet overlay (bottom)
        reportSheetOverlay

        // Search header overlay (top)
        searchHeaderOverlay

        // Signalement preview card overlay (bottom)
        signalementPreviewOverlay

        // Bottom chrome (tab bar + pulse bar)
        bottomChromeOverlay
    }

    @ViewBuilder
    private var reportSheetOverlay: some View {
        if nav.showReportSheet {
            QuickReportSheetView(
                isShowing: $nav.showReportSheet,
                userLatitude: locationManager.userCoordinate?.latitude,
                userLongitude: locationManager.userCoordinate?.longitude,
                activeSignalements: remoteSignalements
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(5)
        }
    }

    @ViewBuilder
    private var searchHeaderOverlay: some View {
        if shouldShowSearchHeader {
            HomeSearchHeaderOverlay(
                searchQuery: $searchQuery,
                suggestions: searchSuggestions,
                isRouting: isRouting,
                hasUserCoordinate: locationManager.userCoordinate != nil,
                favoriteLineCount: favoriteLineCount,
                totalActiveSignalementsCount: totalActiveSignalementsCount,
                isFavoritesFilterActive: activeMapFilter == .favorites,
                isPerturbationsFilterActive: activeMapFilter == .perturbations,
                onShowLegend: {
                    withAnimation(transitionSpring) {
                        showLegend = true
                    }
                },
                onOpenItineraryPlanner: {
                    showRoutePlanner = true
                    activeMapFilter = .none
                },
                onOpenFavorites: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        activeMapFilter = activeMapFilter == .favorites ? .none : .favorites
                    }
                },
                onOpenReports: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                        activeMapFilter = activeMapFilter == .perturbations ? .none : .perturbations
                    }
                },
                onSelectSuggestion: { item in
                    Task { await buildRoute(to: item) }
                }
            )
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zIndex(3)
        }
    }

    @ViewBuilder
    private var signalementPreviewOverlay: some View {
        if let preview = selectedSignalementPreview,
           shouldShowSignalementPreview {
            SignalementMiniCard(
                signalement: preview,
                arretName: arretName(for: preview),
                onClose: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selectedSignalementPreview = nil
                    }
                },
                onStillBlocked: {
                    await reportStillBlocked(id: preview.id)
                },
                onResolved: {
                    await reportResolved(id: preview.id)
                }
            )
            .padding(.horizontal, 18)
            .padding(.bottom, 154)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(7)
        }
    }

    @ViewBuilder
    private var bottomChromeOverlay: some View {
        HomeBottomChromeOverlay(
            currentPage: nav.currentPage,
            shouldShowPulseBar: shouldShowPulseBar,
            shouldShowTabBar: shouldShowTabBar,
            totalActiveSignalementsCount: totalActiveSignalementsCount,
            favoriteAffectedCount: favoriteAffectedCount,
            highlightedEventCount: highlightedEventCount,
            refreshedAt: lastHomeRefreshAt,
            onOpenReports: openReportsFromHome,
            onOpenReportSheet: openQuickReportFromHome,
            onSelectTab: selectTab(_:)
        )
    }

    @ViewBuilder
    var clusterDetailOverlay: some View {
        if let clusterIndex = selectedClusterIndex {
            ClusterDetailSheet(
                clusterIndex: clusterIndex,
                onClose: {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        selectedClusterIndex = nil
                    }
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zIndex(11)
        }
    }
}
