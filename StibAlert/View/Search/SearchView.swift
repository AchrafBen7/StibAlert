import SwiftUI
import CoreLocation

struct SearchView: View {
    @EnvironmentObject private var nav: AppNavigation
    @StateObject private var locationManager = SearchLocationManager()
    @StateObject private var autocompleteManager = SearchAutocompleteManager()
    @StateObject private var viewState = SearchViewState()
    @StateObject private var coordinator = SearchCoordinator()
    @StateObject private var guidanceSession = SearchGuidanceSession()
    @StateObject private var realtimeSignalements = SignalementsRealtimeService()

    private var effectiveOrigin: SearchPlace {
        if viewState.useCurrentLocation, let current = locationManager.currentPlace {
            return current
        }

        return viewState.origin
    }

    private var visiblePlaces: [SearchPlace] {
        viewState.visiblePlaces(currentPlace: locationManager.currentPlace)
    }

    private var visibleSuggestions: [SearchPlaceSuggestion] {
        guard !viewState.query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        return autocompleteManager.suggestions
    }

    private var routeRequestKey: String {
        viewState.routeRequestKey(effectiveOrigin: effectiveOrigin)
    }

    private var guidanceRefreshKey: String {
        guard guidanceSession.guidance.isGuiding else { return "guidance-idle" }
        return "guidance-\(guidanceSession.guidance.activeAlternative?.id ?? "none")-\(routeRequestKey)"
    }

    private var stepProgressText: String? {
        guard guidanceSession.guidance.isGuiding else { return nil }
        let progress = Int((guidanceSession.guidance.stepProgress * 100).rounded())
        guard progress > 0 else { return nil }
        return "\(progress)%"
    }

    private var activeStepPath: [CLLocationCoordinate2D] {
        guard let step = guidanceSession.guidance.currentStep else { return [] }
        return (step.path ?? []).map { CLLocationCoordinate2D(latitude: $0.lat, longitude: $0.lng) }
    }

    var body: some View {
        ZStack {
            SearchTransitMapView(
                selectedScope: viewState.selectedScope,
                journey: viewState.journey,
                activeStepPath: activeStepPath,
                snappedCoordinate: guidanceSession.guidance.snappedCoordinate
            )
            .ignoresSafeArea()

            LinearGradient(
                colors: [
                    Color.black.opacity(0.14),
                    Color.black.opacity(0.03),
                    .clear
                ],
                startPoint: .top,
                endPoint: .center
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)

            VStack(spacing: 0) {
                SearchTopBar(
                    query: $viewState.query,
                    destination: viewState.destination,
                    isExpanded: viewState.activeField != .none,
                    onOpenMenu: {},
                    onOpenSearch: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.86)) {
                            viewState.openDestinationSearch()
                        }
                    },
                    onCloseSearch: {
                        withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                            viewState.clearSearchUI()
                        }
                    }
                )
                .padding(.top, 8)
                .padding(.horizontal, DesignSystem.Spacing.md)

                if viewState.activeField != .none {
                    SearchDestinationSheet(
                        title: "Ou voulez-vous aller ?",
                        query: $viewState.query,
                        selectedField: viewState.activeField,
                        suggestions: visibleSuggestions,
                        places: visiblePlaces,
                        isResolvingSuggestion: viewState.isResolvingSuggestion,
                        locationDenied: locationManager.isDenied,
                        onUseCurrentLocation: {
                            viewState.useCurrentLocation = true
                            viewState.clearSearchUI()
                        },
                        onSelectSuggestion: applySuggestion,
                        onSelect: viewState.applySelection
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .padding(.top, 14)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()
            }
        }
        .overlay(alignment: .bottom) {
            VStack(spacing: 14) {
                if guidanceSession.isRerouting {
                    SearchOffRouteStatusCard(
                        title: "Hors itinéraire détecté",
                        message: "Je recalcule une route plus cohérente avec ta position actuelle.",
                        tone: .rerouting
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let rerouteNotice = guidanceSession.guidance.rerouteNotice,
                          guidanceSession.guidance.isGuiding {
                    SearchOffRouteStatusCard(
                        title: "Itinéraire ajusté",
                        message: rerouteNotice,
                        tone: .updated
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                } else if let offRouteWarning = guidanceSession.guidance.offRouteWarning,
                          guidanceSession.guidance.isGuiding {
                    SearchOffRouteStatusCard(
                        title: "Tu quittes le corridor",
                        message: offRouteWarning,
                        tone: .warning
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let journey = viewState.journey {
                    SearchJourneySummaryCard(
                        journey: journey,
                        isLoading: viewState.isLoadingRoute,
                        routeNote: viewState.routeNote,
                        officialNotice: viewState.transportRecommendation?.officialDataStatus == "available"
                            ? nil
                            : viewState.transportRecommendation?.officialDataMessage,
                        selectedAlternativeID: guidanceSession.guidance.activeAlternative?.id,
                        isGuiding: guidanceSession.guidance.isGuiding,
                        onEditDestination: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.9)) {
                                viewState.openDestinationSearch()
                            }
                        },
                        onSelectAlternative: { alternative in
                            guidanceSession.start(
                                with: alternative,
                                locationManager: locationManager,
                                originName: viewState.journey?.origin.name ?? "",
                                destinationName: viewState.journey?.destination.name ?? ""
                            )
                        }
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                if let currentStep = guidanceSession.guidance.currentStep, guidanceSession.guidance.isGuiding {
                    CurrentStepCard(
                        routeTitle: guidanceSession.guidance.activeAlternative?.title ?? "Guidage",
                        progressText: guidanceSession.guidance.progressText,
                        stepProgressText: stepProgressText,
                        rerouteNotice: guidanceSession.guidance.rerouteNotice,
                        offRouteWarning: guidanceSession.guidance.offRouteWarning,
                        currentStep: currentStep,
                        upcomingSteps: guidanceSession.guidance.upcomingSteps,
                        onBack: {
                            guidanceSession.goBack()
                        },
                        onNext: {
                            guidanceSession.advance()
                        },
                        onStop: {
                            guidanceSession.stop(locationManager: locationManager)
                        },
                        onSpeak: {
                            guidanceSession.speechSynthesizer.speak(currentStep.instruction)
                        }
                    )
                    .padding(.horizontal, DesignSystem.Spacing.md)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }

                Button("Derniers signalements") {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.82)) {
                        nav.currentPage = .reports
                    }
                }
                    .font(DesignSystem.Typography.buttonText)
                    .foregroundStyle(DesignSystem.Colors.primaryText)
                    .frame(maxWidth: 311)
                    .frame(height: AppTheme.ButtonHeight.primary)
                    .background(DesignSystem.Colors.background)
                    .clipShape(Capsule())
                    .accessibilityHint("Ouvre la liste récente des signalements autour de vous.")
            }
            .padding(.bottom, 30)
        }
        .background(DesignSystem.Colors.background)
        .toolbar(.hidden, for: .navigationBar)
        .onAppear {
            realtimeSignalements.connect()
        }
        .onDisappear {
            realtimeSignalements.disconnect()
            coordinator.resetLiveRefreshThrottle()
            guidanceSession.stop(locationManager: locationManager)
        }
        .task(id: routeRequestKey) {
            await rebuildJourney()
        }
        .task(id: guidanceRefreshKey) {
            await coordinator.runGuidanceRefreshLoop(
                state: viewState,
                effectiveOrigin: effectiveOrigin,
                guidance: guidanceSession.guidance,
                speechSynthesizer: guidanceSession.speechSynthesizer
            )
        }
        .onReceive(realtimeSignalements.$latestSignalement.compactMap { $0 }) { signalement in
            Task {
                await coordinator.handleGuidanceSignalement(
                    signalement,
                    state: viewState,
                    guidance: guidanceSession.guidance,
                    effectiveOrigin: effectiveOrigin,
                    speechSynthesizer: guidanceSession.speechSynthesizer
                )
            }
        }
        .onChange(of: viewState.query) { _, newValue in
            autocompleteManager.updateQuery(newValue)
        }
        .onReceive(locationManager.$latestLocation.compactMap { $0 }) { location in
            guidanceSession.handleLocationUpdate(location)
        }
        .task(id: guidanceSession.rerouteRequestID) {
            guard guidanceSession.rerouteRequestID > 0 else { return }
            await rebuildJourney(showLoading: false)
            guidanceSession.consumeRerouteRequest()
        }
    }

    private func swapPlaces() {
        guard let destination = viewState.destination else { return }

        let previousOrigin = effectiveOrigin
        viewState.origin = destination
        viewState.destination = previousOrigin
        viewState.useCurrentLocation = false
    }

    private func applySuggestion(_ suggestion: SearchPlaceSuggestion) {
        coordinator.applySuggestion(
            suggestion,
            autocompleteManager: autocompleteManager,
            state: viewState
        )
    }

    private func rebuildJourney(showLoading: Bool = true) async {
        await coordinator.rebuildJourney(
            state: viewState,
            effectiveOrigin: effectiveOrigin,
            guidance: guidanceSession.guidance,
            speechSynthesizer: guidanceSession.speechSynthesizer,
            showLoading: showLoading
        )
    }
}

enum SearchScope: CaseIterable, Identifiable {
    case all
    case metro
    case tram
    case bus
    case stops

    var id: Self { self }

    var title: String {
        switch self {
        case .all: return "All"
        case .metro: return "Metro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        case .stops: return "Stops"
        }
    }
}

enum SearchField {
    case origin
    case destination
    case none
}

struct SearchPlace: Identifiable, Equatable {
    let id: String
    let name: String
    let subtitle: String
    let coordinate: TransitCoordinate
}

struct SearchJourney {
    let origin: SearchPlace
    let destination: SearchPlace
    let path: [TransitCoordinate]
    let eta: Int
    let lineSummary: String
    let isReal: Bool
    let alternatives: [SearchRouteAlternative]
    let nearbyVehicles: [SearchNearbyTransit]
}

enum SearchJourneyMockData {
    static func journey(from origin: SearchPlace, to destination: SearchPlace) -> SearchJourney {
        let path = curvedPath(from: origin.coordinate, to: destination.coordinate)
        let eta = estimatedMinutes(from: origin.coordinate, to: destination.coordinate)

        return .init(
            origin: origin,
            destination: destination,
            path: path,
            eta: eta,
            lineSummary: "",
            isReal: false,
            alternatives: [],
            nearbyVehicles: SearchTransitCorridorAnalyzer.nearbyVehicles(for: path)
        )
    }

    private static func curvedPath(from start: TransitCoordinate, to end: TransitCoordinate) -> [TransitCoordinate] {
        let midLatitude = (start.latitude + end.latitude) / 2
        let midLongitude = (start.longitude + end.longitude) / 2
        let latDelta = end.latitude - start.latitude
        let lonDelta = end.longitude - start.longitude
        let offsetScale = max(0.004, min(0.012, sqrt(latDelta * latDelta + lonDelta * lonDelta) * 0.35))
        let control = TransitCoordinate(
            latitude: midLatitude + lonDelta * offsetScale,
            longitude: midLongitude - latDelta * offsetScale
        )

        return stride(from: 0.0, through: 1.0, by: 0.1).map { value in
            quadraticPoint(start: start, control: control, end: end, t: value)
        }
    }

    private static func quadraticPoint(
        start: TransitCoordinate,
        control: TransitCoordinate,
        end: TransitCoordinate,
        t: Double
    ) -> TransitCoordinate {
        let oneMinusT = 1 - t
        let latitude = oneMinusT * oneMinusT * start.latitude
            + 2 * oneMinusT * t * control.latitude
            + t * t * end.latitude
        let longitude = oneMinusT * oneMinusT * start.longitude
            + 2 * oneMinusT * t * control.longitude
            + t * t * end.longitude
        return .init(latitude: latitude, longitude: longitude)
    }

    private static func estimatedMinutes(from start: TransitCoordinate, to end: TransitCoordinate) -> Int {
        let latScale = 111_000.0
        let lonScale = 111_000.0 * cos(((start.latitude + end.latitude) / 2.0) * .pi / 180.0)
        let dx = (end.longitude - start.longitude) * lonScale
        let dy = (end.latitude - start.latitude) * latScale
        let kilometers = sqrt(dx * dx + dy * dy) / 1_000
        return max(8, Int((kilometers / 0.55).rounded()))
    }

}
