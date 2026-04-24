import Foundation

@MainActor
final class SearchViewState: ObservableObject {
    @Published var selectedScope: SearchScope = .all
    @Published var origin = SearchJourneyMockData.defaultOrigin
    @Published var destination: SearchPlace?
    @Published var activeField: SearchField = .none
    @Published var query = ""
    @Published var journey: SearchJourney?
    @Published var isLoadingRoute = false
    @Published var routeNote: String?
    @Published var useCurrentLocation = true
    @Published var isResolvingSuggestion = false
    @Published var transportRecommendation: TransportRecommendationDTO?
    @Published var stibiRouteBrief: AssistantBriefDTO?

    func clearSearchUI() {
        activeField = .none
        query = ""
    }

    func openDestinationSearch() {
        activeField = .destination
    }

    func routeRequestKey(effectiveOrigin: SearchPlace) -> String {
        let originToken = "\(effectiveOrigin.id)-\(effectiveOrigin.coordinate.latitude)-\(effectiveOrigin.coordinate.longitude)"
        let destinationToken = destination.map {
            "\($0.id)-\($0.coordinate.latitude)-\($0.coordinate.longitude)"
        } ?? "none"
        return "\(originToken)|\(destinationToken)|\(selectedScope.title)"
    }

    func visiblePlaces(currentPlace: SearchPlace?) -> [SearchPlace] {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        var base = SearchJourneyMockData.places

        if activeField == .origin, let currentPlace {
            base.removeAll { $0.id == currentPlace.id }
            base.insert(currentPlace, at: 0)
        }

        guard !trimmed.isEmpty else { return base }

        return base.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
        }
    }

    func resetJourneyState() {
        journey = nil
        isLoadingRoute = false
        routeNote = nil
        transportRecommendation = nil
        stibiRouteBrief = nil
    }

    func applyBuildResult(_ result: SearchJourneyBuildResult) {
        journey = result.journey
        transportRecommendation = result.recommendation
        stibiRouteBrief = result.assistantBrief
        isLoadingRoute = false
        routeNote = result.routeNote
    }

    func applySelection(_ place: SearchPlace) {
        switch activeField {
        case .origin:
            if place.id == SearchLocationManager.currentLocationID {
                useCurrentLocation = true
            } else {
                useCurrentLocation = false
                origin = place
            }
        case .destination:
            destination = place
        case .none:
            break
        }

        clearSearchUI()
    }
}
