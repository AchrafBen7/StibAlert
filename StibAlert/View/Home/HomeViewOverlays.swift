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
    var reportSheetOverlay: some View {
        if nav.showReportSheet {
            QuickReportSheetView(
                isShowing: $nav.showReportSheet,
                userLatitude: locationManager.userCoordinate?.latitude,
                userLongitude: locationManager.userCoordinate?.longitude,
                activeSignalements: remoteSignalements
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zLayer(.reportSheet)
        }
    }

    @ViewBuilder
    var searchHeaderOverlay: some View {
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
                    // Route every search through the trip-mode DecisionView so users see
                    // their best option in light of current disruptions before launching it.
                    let coord = item.placemark.coordinate
                    tripDestination = HomeView.TripDestination(
                        coordinate: coord,
                        label: item.name ?? item.placemark.title
                    )
                }
            )
            .padding(.top, 10)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zLayer(.searchHeader)
            .homeFeatureTip(.verdict)
        }
    }

    @ViewBuilder
    var signalementPreviewOverlay: some View {
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
            .zLayer(.stopPreview)
        }
    }

    @ViewBuilder
    var bottomChromeOverlay: some View {
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
            .zLayer(.clusterDetail)
        }
    }

    @ViewBuilder
    var allClearChipOverlay: some View {
        if shouldShowAllClearChip {
            HStack(spacing: 8) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(DS.Color.statusOK)
                Text("Tout est fluide près de toi")
                    .font(DS.Font.bodySmall.weight(.semibold))
                    .foregroundStyle(DS.Color.ink)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(DS.Color.paper)
            .overlay(
                Capsule().stroke(DS.Color.statusOK.opacity(0.45), lineWidth: 1)
            )
            .clipShape(Capsule())
            .shadow(color: DS.Color.ink.opacity(0.08), radius: 6, y: 2)
            .padding(.top, 92)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zLayer(.allClearChip)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Aucun incident signalé à proximité")
        }
    }

}
