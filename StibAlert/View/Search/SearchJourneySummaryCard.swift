import SwiftUI

struct SearchJourneySummaryCard: View {
    let journey: SearchJourney
    let isLoading: Bool
    let routeNote: String?
    let officialNotice: String?
    let selectedAlternativeID: String?
    let isGuiding: Bool
    let onEditDestination: () -> Void
    let onSelectAlternative: (SearchRouteAlternative) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(journey.isReal ? "Real route" : "Preview route")
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(journey.isReal ? DesignSystem.Colors.success : DesignSystem.Colors.accentSand)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background((journey.isReal ? DesignSystem.Colors.success : DesignSystem.Colors.accentSand).opacity(0.12))
                            .clipShape(Capsule())

                        if isLoading {
                            ProgressView()
                                .controlSize(.small)
                        }
                    }

                    Text("\(journey.origin.name) → \(journey.destination.name)")
                        .font(DesignSystem.Typography.cardTitle)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .lineLimit(2)

                    Text("\(journey.eta) min • \(journey.lineSummary)")
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)

                    if let routeNote {
                        Text(routeNote)
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                    }

                    if let officialNotice, !officialNotice.isEmpty {
                        HStack(alignment: .top, spacing: 10) {
                            Image(systemName: "antenna.radiowaves.left.and.right.slash")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DesignSystem.Colors.warning)
                                .padding(.top, 2)

                            Text(officialNotice)
                                .font(DesignSystem.Typography.labelSemibold)
                                .foregroundStyle(DesignSystem.Colors.primaryText)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                        .padding(12)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(DesignSystem.Colors.warning.opacity(0.12))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DesignSystem.Colors.warning.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                    }

                    if let recommended = journey.alternatives.first {
                        RecommendedRouteCard(
                            alternative: recommended,
                            isSelected: selectedAlternativeID == recommended.id && isGuiding,
                            onSelect: { onSelectAlternative(recommended) }
                        )
                    }

                    if journey.alternatives.count > 1 {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("Autres options")
                                .font(DesignSystem.Typography.labelSemibold)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)

                            ForEach(Array(journey.alternatives.dropFirst())) { alternative in
                                AlternativeComparisonCard(
                                    alternative: alternative,
                                    isSelected: selectedAlternativeID == alternative.id && isGuiding,
                                    onSelect: { onSelectAlternative(alternative) }
                                )
                            }
                        }
                    }

                    if !journey.nearbyVehicles.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Nearby STIB vehicles")
                                .font(DesignSystem.Typography.labelSemibold)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)

                            ScrollView(.horizontal, showsIndicators: false) {
                                HStack(spacing: 8) {
                                    ForEach(journey.nearbyVehicles) { vehicle in
                                        HStack(spacing: 7) {
                                            Image(systemName: vehicle.icon)
                                                .font(.system(size: 12, weight: .bold))
                                                .foregroundStyle(.white)
                                                .frame(width: 22, height: 22)
                                                .background(vehicle.tint)
                                                .clipShape(Circle())

                                            Text("\(vehicle.routeCode) • \(vehicle.label)")
                                                .font(DesignSystem.Typography.labelSemibold)
                                                .foregroundStyle(DesignSystem.Colors.primaryText)
                                        }
                                        .padding(.horizontal, 10)
                                        .padding(.vertical, 8)
                                        .background(DesignSystem.Colors.cardBackground.opacity(0.88))
                                        .clipShape(Capsule())
                                    }
                                }
                            }
                        }
                    }
                }

                Spacer()
            }

            HStack(spacing: 10) {
                Button("Change destination") {
                    onEditDestination()
                }
                .buttonStyle(SecondaryButton())
                .accessibilityLabel("Modifier la destination")
                .accessibilityHint("Rouvre la recherche pour changer le trajet.")

                // E2 — Fallback texte si DeepLinkRouter.routeURL retourne nil
                // (coords haute précision rejetées, scheme indispo, etc.).
                // Avant : ShareLink absent sans explication. Désormais :
                // partage un texte descriptif avec un lien web si possible.
                let shareURL = DeepLinkRouter.routeURL(
                    fromName: journey.origin.name,
                    fromLat: journey.origin.coordinate.latitude,
                    fromLng: journey.origin.coordinate.longitude,
                    toName: journey.destination.name,
                    toLat: journey.destination.coordinate.latitude,
                    toLng: journey.destination.coordinate.longitude
                )
                let shareMessage = "\(journey.origin.name) → \(journey.destination.name) • \(journey.eta) min • \(journey.lineSummary) (via Blayse)"
                ShareLink(
                    item: shareURL ?? URL(string: "https://stib-alert-backend.onrender.com/")!,
                    subject: Text("Trajet Blayse"),
                    message: Text(shareMessage)
                ) {
                    Image(systemName: "square.and.arrow.up")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                        .frame(width: 44, height: 44)
                        .background(DesignSystem.Colors.cardBackground.opacity(0.7))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .accessibilityLabel("Partager ce trajet")
            }
        }
        .padding(18)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 26, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
    }
}
