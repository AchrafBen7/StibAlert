import MapKit
import SwiftUI

struct HomeSearchHeaderOverlay: View {
    @EnvironmentObject private var connectivity: NetworkConnectivityMonitor
    @EnvironmentObject private var offlineQueue: OfflineQueueSync
    @Binding var searchQuery: String
    let suggestions: [MKMapItem]
    let isRouting: Bool
    let hasUserCoordinate: Bool
    /// Position de l'utilisateur : sert à afficher la distance à droite de chaque
    /// suggestion (« 1,2 km »), le repère « Google Maps » qui manquait.
    var userCoordinate: CLLocationCoordinate2D? = nil
    let favoriteLineCount: Int
    let totalActiveSignalementsCount: Int
    let isFavoritesFilterActive: Bool
    let isPerturbationsFilterActive: Bool
    let onShowLegend: () -> Void
    let onOpenItineraryPlanner: () -> Void
    /// Validation clavier (« zoek ») dans la search bar : calcule directement
    /// un itinéraire DEPUIS ma position vers ce qui est tapé et montre les
    /// alternatives — sans passer par la page Route (≠ onOpenItineraryPlanner,
    /// réservé au bouton « Itinéraires » du filtre, qui lui laisse choisir
    /// départ + arrivée).
    let onSubmitSearch: () -> Void
    let onOpenFavorites: () -> Void
    let onOpenReports: () -> Void
    let onSelectSuggestion: (MKMapItem) -> Void
    /// Tap sur la barre → ouvre la page de recherche plein écran.
    var onActivateSearch: () -> Void = {}

    var body: some View {
        VStack(spacing: 10) {
            if offlineQueue.pendingCount > 0 {
                OfflineIndicator(
                    isConnected: connectivity.isConnected,
                    isConstrained: connectivity.isConstrained,
                    pendingReports: offlineQueue.pendingCount
                )
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                HomeEditorialSearchField(query: $searchQuery, onActivate: onActivateSearch)

                Button(action: onShowLegend) {
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(DS.Color.paper.opacity(0.96))
                        .frame(width: 48, height: 48)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                        )
                        .overlay(
                            Image(systemName: "slider.horizontal.3")
                                .font(.system(size: 18, weight: .semibold))
                                .foregroundStyle(DS.Color.ink)
                        )
                        .shadow(DS.Shadow.floating)
                }
                .buttonStyle(.plain)
                .coachMarkAnchor(.legendButton)
            }
            .padding(.horizontal, 18)

            // La saisie + les résultats vivent désormais dans MapSearchPage
            // (plein écran). La barre ci-dessus n'est qu'un déclencheur, donc on
            // affiche toujours les raccourcis d'action sous elle.
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    HomeEditorialActionChip(
                        icon: "arrow.triangle.turn.up.right.diamond.fill",
                        title: AppLocalizer.string("home.action.itineraries", defaultValue: "Itinéraires"),
                        count: nil,
                        isActive: isRouting,
                        action: onOpenItineraryPlanner
                    )

                    HomeEditorialActionChip(
                        icon: "star.fill",
                        title: AppLocalizer.string("home.action.favorites", defaultValue: "Favoris"),
                        count: favoriteLineCount,
                        isActive: isFavoritesFilterActive,
                        action: onOpenFavorites
                    )

                    HomeEditorialActionChip(
                        icon: "exclamationmark.triangle.fill",
                        title: AppLocalizer.string("home.action.disruptions", defaultValue: "Perturbations"),
                        count: totalActiveSignalementsCount,
                        isActive: isPerturbationsFilterActive,
                        action: onOpenReports
                    )
                }
                .padding(.horizontal, 18)
            }
        }
    }
}

/// Barre de recherche de la carte. N'édite plus en place : un tap ouvre la page
/// de recherche plein écran (`MapSearchPage`), façon Google Maps. Elle affiche
/// juste le lieu courant (ou le placeholder) et un bouton effacer.
private struct HomeEditorialSearchField: View {
    @Binding var query: String
    /// Tap sur la barre → ouvre la page de recherche plein écran.
    let onActivate: () -> Void

    var body: some View {
        Button(action: onActivate) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Color.inkSoft)

                Text(query.isEmpty ? AppLocalizer.string("search.where_to", defaultValue: "Où vas-tu ?") : query)
                    .font(DS.Font.body)
                    .foregroundStyle(query.isEmpty ? DS.Color.inkSoft : DS.Color.ink)
                    .lineLimit(1)

                Spacer(minLength: 0)

                if !query.isEmpty {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.Color.inkMute)
                        .onTapGesture { query = "" }
                        .accessibilityLabel(AppLocalizer.string("search.clear", defaultValue: "Effacer la recherche"))
                }
            }
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(DS.Color.paper.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(AppLocalizer.string("search.open", defaultValue: "Ouvrir la recherche"))
    }
}

private struct HomeEditorialActionChip: View {
    let icon: String
    let title: String
    let count: Int?
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            action()
        }) {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                Text(title)
                    .font(DS.Font.bodyBold)
                    .tracking(1.0)
                    .textCase(.uppercase)
                if let count {
                    Text("\(count)")
                        .font(DS.Font.label)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            RoundedRectangle(cornerRadius: DS.Radius.sm, style: .continuous)
                                .fill((isActive ? DS.Color.ink : DS.Color.paper2).opacity(0.14))
                        )
                }
            }
            .foregroundStyle(isActive ? DS.Color.ink : DS.Color.inkSoft)
            .padding(.horizontal, 14)
            .frame(height: 42)
            .background(DS.Color.paper.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .shadow(DS.Shadow.raised)
        }
        .buttonStyle(.plain)
    }
}

