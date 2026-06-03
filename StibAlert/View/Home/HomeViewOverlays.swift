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

        // Vehicle detail overlay (bottom) — shown when user taps a tram pin
        vehicleDetailOverlay

        // Bottom chrome (tab bar + pulse bar)
        bottomChromeOverlay
    }

    @ViewBuilder
    var vehicleDetailOverlay: some View {
        if let vehicle = selectedVehicle {
            VehicleDetailSheet(
                vehicle: vehicle,
                destinationByDirection: vehicleDestinationByDirection,
                onClose: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        selectedVehicle = nil
                    }
                }
            )
            .padding(.bottom, 100)
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zLayer(.clusterDetail)
        }
    }

    @ViewBuilder
    var reportSheetOverlay: some View {
        if nav.showReportSheet {
            QuickReportSheetView(
                isShowing: $nav.showReportSheet,
                userLatitude: locationManager.userCoordinate?.latitude,
                userLongitude: locationManager.userCoordinate?.longitude,
                activeSignalements: remoteSignalements,
                onSubmitted: { signalement in
                    mergeIncomingSignalement(signalement)
                }
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
            .zLayer(.reportSheet)
        }
    }

    @ViewBuilder
    var searchHeaderOverlay: some View {
        if shouldShowSearchHeader {
            Group {
                if let stop = selectedMapStopPreview {
                    // Mini stop card — replaces the search bar so the user can
                    // see the focused line + live vehicles on the map below.
                    HomeStopMiniHeaderCard(
                        stop: stop,
                        selectedLine: selectedStopLineNumber,
                        nextDepartures: selectedMapStopDetail?.nextDepartures ?? [],
                        isLoading: isLoadingMapStopDetail,
                        liveVehicleCount: vehicleTracker.vehicles.count,
                        liveVehicles: vehicleTracker.vehicles,
                        onClose: {
                            dismissStopPreview()
                        },
                        onSelectLine: { line in
                            selectStopLineRoute(line)
                        },
                        onFollowVehicle: { vehicle in
                            panMap(to: vehicle)
                        },
                        onShowDetail: {
                            openStopDetailFromMiniCard(for: stop)
                        }
                    )
                    .padding(.horizontal, 14)
                    .padding(.top, 10)
                    .transition(.move(edge: .top).combined(with: .opacity))
                    .zLayer(.searchHeader)
                } else {
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
                                showLegend.toggle()
                            }
                        },
                        onOpenItineraryPlanner: {
                            showRoutePlanner = true
                            activeMapFilter = .none
                        },
                        onSubmitSearch: {
                            // « zoek » dans la search bar → itinéraire direct
                            // depuis ma position vers la saisie, alternatives
                            // affichées sans passer par la page Route.
                            submitSearchToRoute()
                        },
                        onOpenFavorites: {
                            let shouldFocusFavorites = activeMapFilter != .favorites
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                activeMapFilter = shouldFocusFavorites ? .favorites : .none
                            }
                            if shouldFocusFavorites {
                                focusMapOnFavorites()
                            }
                        },
                        onOpenReports: {
                            let shouldFocusPerturbations = activeMapFilter != .perturbations
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                                activeMapFilter = shouldFocusPerturbations ? .perturbations : .none
                            }
                            if shouldFocusPerturbations {
                                focusMapOnPerturbations()
                            }
                        },
                        onSelectSuggestion: { item in
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
                }
            }
        }
    }

    /// Quick-launch du trajet quotidien (Smart Commute LITE J-7).
    /// Affichée UNIQUEMENT pendant les fenêtres d'utilité (matin + soir) et
    /// quand aucun autre overlay prioritaire (proactive alert, report sheet,
    /// route preview) ne prend la place.
    /// Bandeau persistant pendant qu'un trip est actif. Pose-le tout en haut
    /// (au-dessus de la search bar) pour qu'il soit le 1er thing visible
    /// quand l'utilisateur regarde la carte pendant son trajet.
    @ViewBuilder
    var activeTripIndicatorOverlay: some View {
        if tripTracker.isActive {
            ActiveTripIndicatorView(
                tracker: tripTracker,
                onCancel: { clearRouteSelection(keepDestination: false) }
            )
            .padding(.top, shouldShowSearchHeader ? 104 : 14)
            .zLayer(.stopPreview)
            .accessibilitySortPriority(20)
        }
    }

    @ViewBuilder
    var commuteOverlay: some View {
        // I1 — Pendant les heures de commute matin (5h-9h) ou soir (17h-23h),
        // la card Commute prime sur la Proactive Alert. Hors de ces fenêtres,
        // c'est l'inverse (la commute ne devrait même pas s'afficher car
        // CommuteQuickLaunchCard.shouldShow gère ça). Pendant un trip actif,
        // la card est masquée — l'indicateur de trip suffit.
        if let user = session.currentUser,
           !tripTracker.isActive,
           CommuteQuickLaunchCard.shouldShow(routine: user.routine, now: Date()),
           (Self.isCommutePriorityWindow(Date()) || proactiveAlertCluster == nil),
           selectedClusterIndex == nil,
           !nav.showReportSheet,
           routeOptions.isEmpty,
           let routine = user.routine {
            CommuteQuickLaunchCard(routine: routine, onLaunch: { direction in
                Task { await launchCommute(direction: direction, routine: routine) }
            })
            .padding(.horizontal, 14)
            .padding(.top, shouldShowSearchHeader ? 104 : 14)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zLayer(.stopPreview)
            .accessibilitySortPriority(15)
        } else if shouldShowCommuteSetupNudge {
            // L'infra Smart Commute reste inerte tant que la routine n'est pas
            // configurée. On invite (une fois, dismissable) un utilisateur DÉJÀ
            // engagé (au moins un favori) à activer son trajet quotidien — c'est
            // ce qui débloque le brief pré-départ + le verdict + le Plan B.
            CommuteSetupNudgeCard(
                onConfigure: {
                    commuteNudgeDismissed = true
                    nav.currentPage = .profile
                },
                onDismiss: { commuteNudgeDismissed = true }
            )
            .padding(.horizontal, 14)
            .padding(.top, shouldShowSearchHeader ? 104 : 14)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zLayer(.stopPreview)
            .accessibilitySortPriority(14)
        }
    }

    /// Nudge "configure ton trajet" : seulement pour un utilisateur engagé
    /// (≥1 favori) sans routine active, non déjà écarté, et dans les mêmes
    /// conditions de calme que la card commute (pas de trip/cluster/route).
    private var shouldShowCommuteSetupNudge: Bool {
        guard let user = session.currentUser else { return false }
        guard !commuteNudgeDismissed else { return false }
        guard !tripTracker.isActive, selectedClusterIndex == nil,
              !nav.showReportSheet, routeOptions.isEmpty,
              proactiveAlertCluster == nil else { return false }
        let hasRoutine = (user.routine?.enabled == true)
        let hasFavorites = !(user.favoriteLines ?? []).isEmpty || !favoriteStopIds.isEmpty
        return !hasRoutine && hasFavorites
    }

    /// I1 — Fenêtres où la card Commute prend visuellement le pas sur la
    /// proactive alert (heures de transit domicile-travail Bruxelles).
    static func isCommutePriorityWindow(_ date: Date) -> Bool {
        let hour = Calendar.current.component(.hour, from: date)
        return (5...8).contains(hour) || (17...22).contains(hour)
    }

    @ViewBuilder
    var proactiveAlertOverlay: some View {
        if let cluster = proactiveAlertCluster,
           !tripTracker.isActive,
           !(Self.isCommutePriorityWindow(Date())
             && (session.currentUser?.routine).map { CommuteQuickLaunchCard.shouldShow(routine: $0, now: Date()) } == true),
           selectedClusterIndex == nil,
           !nav.showReportSheet {
            HomeProactiveAlertCard(
                cluster: cluster,
                onClose: closeProactiveAlert,
                onOpenDetails: {
                    openProactiveAlertCluster(cluster)
                },
                onStillBlocked: {
                    await confirmProactiveAlertStillBlocked(cluster)
                },
                onResolved: {
                    await confirmProactiveAlertResolved(cluster)
                }
            )
            .padding(.horizontal, 14)
            .padding(.top, shouldShowSearchHeader ? 104 : 14)
            .transition(.move(edge: .top).combined(with: .opacity))
            .zLayer(.stopPreview)
            .accessibilitySortPriority(20)
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
            onOpenVoice: openVoiceFromHome,
            onOpenStibAI: openStibAIFromHome,
            onRecenter: recenterFromHome,
            onSelectTab: selectTab(_:),
            isGuest: session.isGuest,
            onCreateAccount: {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                nav.authInitialRoute = .signUp
                nav.showAuthFlow = true
            }
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
