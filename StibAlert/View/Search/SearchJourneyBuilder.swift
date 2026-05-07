import Foundation

struct SearchJourneyBuildResult {
    let journey: SearchJourney
    let recommendation: TransportRecommendationDTO?
    let routeNote: String
}

enum SearchJourneyBuilder {
    static func build(
        origin: SearchPlace,
        destination: SearchPlace
    ) async -> SearchJourneyBuildResult {
        do {
            let calculated = try await SearchRouteCalculator.calculate(
                from: origin,
                to: destination
            )
            let recommendation = try? await TransportService.recommendRoute(
                depart: origin.name,
                destination: destination.name
            )
            let merged = mergeJourney(calculated, with: recommendation)
            return SearchJourneyBuildResult(
                journey: merged,
                recommendation: recommendation,
                routeNote: buildRouteNote(
                    recommendation: recommendation,
                    fallback: "Real route via Apple Maps"
                )
            )
        } catch {
            let fallback = SearchJourneyMockData.journey(from: origin, to: destination)
            let recommendation = try? await TransportService.recommendRoute(
                depart: origin.name,
                destination: destination.name
            )
            let merged = mergeJourney(fallback, with: recommendation)
            return SearchJourneyBuildResult(
                journey: merged,
                recommendation: recommendation,
                routeNote: buildRouteNote(
                    recommendation: recommendation,
                    fallback: "Fallback preview used"
                )
            )
        }
    }

    private static func mergeJourney(_ journey: SearchJourney, with recommendation: TransportRecommendationDTO?) -> SearchJourney {
        guard let recommendation else { return journey }

        let alternatives = TransportViewAdapters.routeAlternatives(from: recommendation)
        return SearchJourney(
            origin: journey.origin,
            destination: journey.destination,
            path: journey.path,
            eta: alternatives.first?.eta ?? journey.eta,
            lineSummary: alternatives.first?.lineSummary ?? journey.lineSummary,
            isReal: journey.isReal,
            alternatives: alternatives.isEmpty ? journey.alternatives : alternatives,
            nearbyVehicles: journey.nearbyVehicles
        )
    }

    private static func buildRouteNote(
        recommendation: TransportRecommendationDTO?,
        fallback: String
    ) -> String {
        recommendation.map {
            let reliability = TransportViewAdapters.reliabilityText(from: $0)
            let explanation = TransportViewAdapters.routeNote(from: $0) ?? "Alternative calculée avec les données STIB."
            return "\(reliability) • \(explanation)"
        }
        ?? fallback
    }
}
