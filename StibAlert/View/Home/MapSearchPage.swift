import MapKit
import SwiftUI

/// Page de recherche plein écran (façon Google Maps, au design system Blayse).
/// S'ouvre quand on tape la barre de recherche de la carte. Champ focalisé en
/// haut, accès rapides (Domicile/Travail déjà enregistrés), et en dessous :
/// les RÉCENTS quand le champ est vide, les RÉSULTATS live quand on tape.
/// Réutilise les stores du planificateur d'itinéraire (récents + lieux sauvés).
struct MapSearchPage: View {
    @Binding var query: String
    let suggestions: [MKMapItem]
    let isRouting: Bool
    let userCoordinate: CLLocationCoordinate2D?
    /// Un lieu a été choisi (suggestion, récent ou lieu sauvé) → on le pose comme
    /// destination. Le parent (HomeView) enclenche l'itinéraire, comme avant.
    let onSelect: (MKMapItem) -> Void
    /// Validation clavier sans choisir de résultat → itinéraire direct.
    let onSubmit: () -> Void
    let onDismiss: () -> Void

    @FocusState private var isFocused: Bool
    @State private var localText = ""
    @State private var debounceTask: Task<Void, Never>?
    @State private var recents: [HomeRouteRecentPlace] = HomeRouteRecentStore.load()
    private let saved: [HomeRouteSavedPlaceKind: HomeRouteRecentPlace] = HomeRouteSavedPlaceStore.load()

    private var isSearching: Bool {
        !localText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider().overlay(DS.Color.ink.opacity(0.08))

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if isSearching {
                        resultsSection
                    } else {
                        quickAccessRow
                        recentsSection
                    }
                }
                .padding(.bottom, 24)
            }
            .scrollDismissesKeyboard(.immediately)
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .onAppear {
            localText = query
            // Petit délai : laisse la transition se poser avant d'ouvrir le clavier
            // → l'entrée reste fluide (~0,3 s) au lieu de saccader.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.28) { isFocused = true }
        }
    }

    // MARK: - Header (retour + champ + effacer)

    private var header: some View {
        HStack(spacing: 10) {
            Button(action: dismiss) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 40, height: 40)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalizer.string("common.back", defaultValue: "Retour"))

            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Color.inkSoft)

                TextField(AppLocalizer.string("search.where_to", defaultValue: "Où vas-tu ?"), text: $localText)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.ink)
                    .focused($isFocused)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .submitLabel(.search)
                    .onSubmit {
                        guard isSearching else { return }
                        query = localText
                        onSubmit()
                        onDismiss()
                    }
                    .onChange(of: localText) { _, newValue in
                        debounceTask?.cancel()
                        debounceTask = Task {
                            try? await Task.sleep(nanoseconds: 150_000_000)
                            if Task.isCancelled { return }
                            if query != newValue { query = newValue }
                        }
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
            .frame(height: 46)
            .background(DS.Color.paper2.opacity(0.7))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 10)
    }

    // MARK: - Accès rapides (Domicile / Travail déjà enregistrés)

    @ViewBuilder
    private var quickAccessRow: some View {
        let places = HomeRouteSavedPlaceKind.allCases.compactMap { kind in
            saved[kind].map { (kind, $0) }
        }
        if !places.isEmpty {
            HStack(spacing: 10) {
                ForEach(places, id: \.0) { kind, place in
                    Button { select(place.mapItem) } label: {
                        HStack(spacing: 10) {
                            Image(systemName: kind == .home ? "house.fill" : "briefcase.fill")
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(DS.Color.ink)
                            VStack(alignment: .leading, spacing: 1) {
                                Text(kind.label)
                                    .font(.system(size: 13, weight: .bold))
                                    .foregroundStyle(DS.Color.ink)
                                Text(place.subtitle)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Color.inkMute)
                                    .lineLimit(1)
                            }
                            Spacer(minLength: 0)
                        }
                        .padding(.horizontal, 12)
                        .frame(height: 48)
                        .frame(maxWidth: .infinity)
                        .background(DS.Color.paper2.opacity(0.6))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 18)
            .padding(.top, 6)
            .padding(.bottom, 14)
        }
    }

    // MARK: - Récents

    @ViewBuilder
    private var recentsSection: some View {
        if recents.isEmpty {
            emptyState
        } else {
            HStack {
                Text(AppLocalizer.string("search.recents", defaultValue: "Récents").uppercased())
                    .font(DS.Font.eyebrow).tracking(1.6)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Button {
                    withAnimation(.easeInOut(duration: 0.2)) {
                        recents = []
                        HomeRouteRecentStore.save([])
                    }
                } label: {
                    Text(AppLocalizer.string("search.clear_recents", defaultValue: "Effacer"))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)
            .padding(.bottom, 4)

            ForEach(recents) { place in
                row(icon: place.kind == .stop ? "signpost.right.fill" : "clock.arrow.circlepath",
                    title: place.title, subtitle: place.subtitle, trailing: nil) {
                    select(place.mapItem)
                }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 26))
                .foregroundStyle(DS.Color.inkMute.opacity(0.6))
            Text(AppLocalizer.string("search.empty_hint", defaultValue: "Cherche un arrêt, une gare ou une adresse dans Bruxelles."))
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkMute)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 60)
        .padding(.horizontal, 40)
    }

    // MARK: - Résultats live

    @ViewBuilder
    private var resultsSection: some View {
        if suggestions.isEmpty {
            HStack {
                if isRouting {
                    ProgressView().tint(DS.Color.ink)
                    Text(AppLocalizer.string("search.searching", defaultValue: "Recherche…"))
                        .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
                }
                Spacer()
            }
            .padding(.horizontal, 18).padding(.top, 16)
        } else {
            ForEach(suggestions, id: \.self) { item in
                row(icon: symbol(for: item),
                    title: item.name ?? AppLocalizer.string("Lieu", defaultValue: "Lieu"),
                    subtitle: primaryLocationLine(for: item),
                    trailing: distanceText(for: item)) {
                    select(item)
                }
            }
        }
    }

    // MARK: - Rangée générique

    private func row(icon: String, title: String, subtitle: String, trailing: String?, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(width: 40, height: 40)
                    .background(DS.Color.paper2)
                    .clipShape(Circle())

                VStack(alignment: .leading, spacing: 2) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    if !subtitle.isEmpty {
                        Text(subtitle)
                            .font(.system(size: 13))
                            .foregroundStyle(DS.Color.inkMute)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 8)

                if let trailing {
                    Text(trailing)
                        .font(.system(size: 12, weight: .semibold))
                        .monospacedDigit()
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 11)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottom) {
            Rectangle().fill(DS.Color.ink.opacity(0.06)).frame(height: 1).padding(.leading, 70)
        }
    }

    // MARK: - Actions

    private func select(_ item: MKMapItem) {
        // Mémorise le choix en récent (remonte en tête, dédupliqué).
        let place = HomeRouteRecentPlace(item: item)
        HomeRouteRecentStore.save(HomeRouteRecentStore.prepending(place, to: recents))
        onSelect(item)
        onDismiss()
    }

    private func dismiss() {
        isFocused = false
        onDismiss()
    }

    // MARK: - Helpers d'affichage (repris du dropdown précédent)

    private func distanceText(for item: MKMapItem) -> String? {
        guard let userCoordinate, let location = item.placemark.location else { return nil }
        let meters = CLLocation(latitude: userCoordinate.latitude, longitude: userCoordinate.longitude)
            .distance(from: location)
        return meters.distanceLabel
    }

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
        let pieces: [String] = [placemark.thoroughfare, placemark.locality, placemark.country]
            .compactMap { ($0?.isEmpty == false) ? $0 : nil }
        return pieces.isEmpty ? (placemark.title ?? "") : pieces.joined(separator: ", ")
    }
}
