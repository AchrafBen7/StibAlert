import MapKit
import SwiftUI

struct HomeSearchHeaderOverlay: View {
    @EnvironmentObject private var connectivity: NetworkConnectivityMonitor
    @EnvironmentObject private var offlineQueue: OfflineQueueSync
    @Binding var searchQuery: String
    let suggestions: [MKMapItem]
    let isRouting: Bool
    let hasUserCoordinate: Bool
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

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 10) {
            if !connectivity.isConnected || connectivity.isConstrained || offlineQueue.pendingCount > 0 {
                OfflineIndicator(
                    isConnected: connectivity.isConnected,
                    isConstrained: connectivity.isConstrained,
                    pendingReports: offlineQueue.pendingCount
                )
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            HStack(spacing: 10) {
                HomeEditorialSearchField(query: $searchQuery, onSubmit: onSubmitSearch)

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
            }
            .padding(.horizontal, 18)

            if isSearching {
                if !suggestions.isEmpty {
                    SearchSuggestionsDropdown(
                        suggestions: suggestions,
                        isRouting: isRouting,
                        onSelect: onSelectSuggestion
                    )
                    .padding(.horizontal, 18)
                }
            } else {
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
}

private struct HomeEditorialSearchField: View {
    @Binding var query: String
    /// Called when the user presses search/enter on the keyboard *after*
    /// typing something. Hands off to the full route planner.
    let onSubmit: () -> Void

    @FocusState private var isFocused: Bool
    /// État LOCAL du champ. Avant TextField était bound à `$query`
    /// (= @State de HomeView, 3700 lignes) → chaque caractère invalidait
    /// tout HomeView.body. Maintenant le local absorbe la frappe sans
    /// solliciter le parent, et on synchronise via debounce 150 ms (assez
    /// rapide pour que les suggestions de recherche se mettent à jour
    /// fluidement, assez lent pour que la frappe soit naturelle).
    @State private var localText: String = ""
    @State private var debounceTask: Task<Void, Never>?

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.inkSoft)

            TextField("Où vas-tu ?", text: $localText)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .focused($isFocused)
                .autocorrectionDisabled()
                .submitLabel(.search)
                // Bouton "Terminé" au-dessus du clavier : seul moyen fiable de
                // fermer le clavier quand on tape une adresse sans valider (le
                // tap sur la carte ne le fermait pas). Standard iOS.
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button(String(localized: "Terminé")) {
                            isFocused = false
                        }
                        .fontWeight(.semibold)
                    }
                }
                .onSubmit {
                    guard !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
                    // Sync immédiat avant submit pour que le parent ait la
                    // valeur finale avant d'ouvrir le planner.
                    query = localText
                    isFocused = false
                    onSubmit()
                }
                .onChange(of: localText) { _, newValue in
                    debounceTask?.cancel()
                    debounceTask = Task {
                        try? await Task.sleep(nanoseconds: 150_000_000)
                        if Task.isCancelled { return }
                        if query != newValue { query = newValue }
                    }
                }
                .onAppear { localText = query }
                .onChange(of: query) { _, newValue in
                    // Reset externe (HomeView set query = "" ou
                    // = destination.name après sélection) → on rapatrie.
                    if newValue != localText { localText = newValue }
                }

            if !localText.isEmpty {
                Button {
                    localText = ""
                    query = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 17))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(AppLocalizer.string("search.clear", defaultValue: "Effacer la recherche"))
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(DS.Color.paper.opacity(0.96))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(
                    isFocused ? DS.Color.ink.opacity(0.36) : DS.Color.ink.opacity(0.16),
                    lineWidth: 1
                )
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        .shadow(DS.Shadow.floating)
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
                        .font(DS.Font.mono)
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

private struct SearchSuggestionsDropdown: View {
    let suggestions: [MKMapItem]
    let isRouting: Bool
    let onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header discret : juste un petit label, sans la grosse ligne
            // pleine qui donnait un aspect « carré lourd » derrière les
            // résultats. La liste respire davantage.
            Text("DESTINATIONS")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute.opacity(0.8))
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 6)

            ForEach(suggestions, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(alignment: .top, spacing: 12) {
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(DS.Color.paper2)
                            .frame(width: 34, height: 34)
                            .overlay(
                                Image(systemName: symbol(for: item))
                                    .font(.system(size: 14, weight: .semibold))
                                    .foregroundStyle(DS.Color.primary)
                            )

                        VStack(alignment: .leading, spacing: 5) {
                            Text(item.name ?? "Lieu")
                                .font(.system(size: 15, weight: .bold))
                                .foregroundStyle(DS.Color.ink)
                            Text(primaryLocationLine(for: item))
                                .font(DS.Font.caption)
                                .foregroundStyle(DS.Color.inkMute)
                                .lineLimit(1)
                            Text(categoryLabel(for: item))
                                .font(DS.Font.monoSmall.weight(.bold))
                                .tracking(1.4)
                                .foregroundStyle(DS.Color.community)
                        }

                        Spacer()

                        if isRouting {
                            ProgressView()
                                .tint(DS.Color.ink)
                                .scaleEffect(0.85)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 13)
                }
                .buttonStyle(.plain)

                if item != suggestions.last {
                    Divider()
                        .overlay(DS.Color.ink.opacity(0.08))
                        .padding(.leading, 60)
                }
            }
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(DS.Shadow.raised)
    }

    private func symbol(for item: MKMapItem) -> String {
        if item.pointOfInterestCategory != nil {
            return "sparkles"
        }
        return "mappin"
    }

    private func primaryLocationLine(for item: MKMapItem) -> String {
        let placemark = item.placemark
        let pieces: [String] = [
            placemark.thoroughfare,
            placemark.locality,
            placemark.country
        ].compactMap { value in
            guard let value, !value.isEmpty else { return nil }
            return value
        }
        return pieces.isEmpty ? (placemark.title ?? "") : pieces.joined(separator: ", ")
    }

    private func categoryLabel(for item: MKMapItem) -> String {
        if item.pointOfInterestCategory != nil {
            return "LIEU"
        }
        return "ADRESSE"
    }
}
