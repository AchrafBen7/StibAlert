import SwiftUI

struct SearchJourneySummaryCard: View {
    let journey: SearchJourney
    let isLoading: Bool
    let routeNote: String?
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

            Button("Change destination") {
                onEditDestination()
            }
            .buttonStyle(SecondaryButton())
            .accessibilityLabel("Modifier la destination")
            .accessibilityHint("Rouvre la recherche pour changer le trajet.")
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
