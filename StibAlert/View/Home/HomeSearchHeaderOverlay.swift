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

    private var isSearching: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

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
                        userCoordinate: userCoordinate,
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
                        Button(AppLocalizer.string("Terminé")) {
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

/// Autocomplétion de la barre de recherche, façon Google Maps / Waze.
///
/// L'ancienne version était « anti-Google Maps » : un en-tête « DESTINATIONS » en
/// monospace, TROIS lignes par résultat (nom + adresse + un tag « ADRESSE »/« LIEU »
/// en majuscules colorées), et une icône « sparkles » orange dans un carré. Trop
/// de choses pour un simple « où vas-tu ? ».
///
/// Ici : pas d'en-tête, deux lignes (nom + adresse), une icône monochrome choisie
/// selon la catégorie du lieu, et — le repère qui manquait — la DISTANCE à droite.
private struct SearchSuggestionsDropdown: View {
    let suggestions: [MKMapItem]
    let isRouting: Bool
    var userCoordinate: CLLocationCoordinate2D? = nil
    let onSelect: (MKMapItem) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(suggestions, id: \.self) { item in
                Button {
                    onSelect(item)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: symbol(for: item))
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DS.Color.inkMute)
                            .frame(width: 38, height: 38)
                            .background(DS.Color.paper2)
                            .clipShape(Circle())

                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name ?? AppLocalizer.string("Lieu", defaultValue: "Lieu"))
                                .font(.system(size: 15, weight: .semibold))
                                .foregroundStyle(DS.Color.ink)
                                .lineLimit(1)
                            Text(primaryLocationLine(for: item))
                                .font(.system(size: 13))
                                .foregroundStyle(DS.Color.inkMute)
                                .lineLimit(1)
                        }

                        Spacer(minLength: 8)

                        if isRouting {
                            ProgressView()
                                .tint(DS.Color.ink)
                                .scaleEffect(0.8)
                        } else if let distance = distanceText(for: item) {
                            Text(distance)
                                .font(.system(size: 12, weight: .semibold))
                                .monospacedDigit()
                                .foregroundStyle(DS.Color.inkMute)
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                if item != suggestions.last {
                    Divider()
                        .overlay(DS.Color.ink.opacity(0.07))
                        .padding(.leading, 64)
                }
            }
        }
        .padding(.vertical, 4)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shadow(DS.Shadow.floating)
    }

    private func distanceText(for item: MKMapItem) -> String? {
        guard let userCoordinate, let location = item.placemark.location else { return nil }
        let meters = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: location)
        return meters.distanceLabel
    }

    /// Icône monochrome selon la catégorie du POI (comme la liste de Google Maps),
    /// sinon un simple repère pour une adresse.
    private func symbol(for item: MKMapItem) -> String {
        switch item.pointOfInterestCategory {
        case .some(.restaurant), .some(.cafe), .some(.bakery): return "fork.knife"
        case .some(.store), .some(.foodMarket): return "bag"
        case .some(.hospital), .some(.pharmacy): return "cross.case"
        case .some(.school), .some(.university), .some(.library): return "graduationcap"
        case .some(.park), .some(.nationalPark): return "tree"
        case .some(.museum), .some(.theater): return "building.columns"
        case .some(.hotel): return "bed.double"
        case .some(.airport): return "airplane"
        case .some(.publicTransport): return "tram.fill"
        case .some(.stadium), .some(.fitnessCenter): return "sportscourt"
        case .some: return "mappin.circle"
        case .none: return "mappin"
        }
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
}
