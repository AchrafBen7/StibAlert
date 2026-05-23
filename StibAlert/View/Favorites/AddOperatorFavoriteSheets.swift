import CoreLocation
import SwiftUI

/// Add-favourite sheet for SNCB — pick a gare from the same directory used in
/// Horaires; tapping pins it (local SNCBGareFavorites) and closes.
struct AddSncbFavoriteSheet: View {
    let onClose: () -> Void
    @ObservedObject private var favorites = SNCBGareFavorites.shared
    @State private var searchQuery = ""

    var body: some View {
        VStack(spacing: 0) {
            AddFavoriteSheetHeader(title: "Épingler une gare", onClose: onClose)
            ScrollView(showsIndicators: false) {
                SncbGareDirectory(
                    searchQuery: $searchQuery,
                    showsSearchField: true,
                    onSelect: { station in
                        if !favorites.contains(station.id) { favorites.toggle(station.id) }
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        onClose()
                    }
                )
                .padding(.horizontal, 18)
                .padding(.top, 8)
                .padding(.bottom, 24)
            }
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
    }
}

/// Add-favourite sheet for De Lijn / TEC — nearby stops (viewport around the
/// user); tapping pins it (local OperatorStopFavorites) and closes.
struct AddOperatorFavoriteSheet: View {
    let op: TransitOperator
    let onClose: () -> Void

    @ObservedObject private var favorites = OperatorStopFavorites.shared
    @StateObject private var locator = OneShotLocationManager()
    @State private var stops: [OperatorMapStop] = []
    @State private var isLoading = true
    @State private var searchQuery = ""

    private var filteredStops: [OperatorMapStop] {
        let query = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return stops }

        return stops.filter {
            $0.name.localizedCaseInsensitiveContains(query)
            || $0.id.localizedCaseInsensitiveContains(query)
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            AddFavoriteSheetHeader(title: "Épingler un arrêt \(op.mapLabel)", onClose: onClose)
            FavoritePickerSearchField(
                placeholder: "Chercher un arrêt \(op.mapLabel)",
                text: $searchQuery
            )
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 6)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 0) {
                    if isLoading && stops.isEmpty {
                        ProgressView().tint(DS.Color.ink).frame(maxWidth: .infinity).padding(.vertical, 48)
                    } else if stops.isEmpty {
                        Text("Aucun arrêt \(op.mapLabel) à proximité.")
                            .font(DS.Font.bodySmall).foregroundStyle(DS.Color.inkMute)
                            .padding(.horizontal, 20).padding(.top, 24)
                    } else if filteredStops.isEmpty {
                        Text("Aucun arrêt trouvé pour « \(searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)) ».")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkMute)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 20)
                            .padding(.top, 24)
                    } else {
                        VStack(spacing: 0) {
                            ForEach(filteredStops) { stopRow($0) }
                        }
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                        .padding(.horizontal, 20)
                        .padding(.top, 8)
                    }
                }
                .padding(.bottom, 24)
            }
        }
        .background(DS.Color.paper.ignoresSafeArea())
        .preferredColorScheme(.light)
        .task { await load() }
    }

    private func stopRow(_ stop: OperatorMapStop) -> some View {
        let isFav = favorites.contains(stop.id)
        return Button {
            let fav = FavoriteOperatorStop(op: op.rawValue, stopId: stop.id, name: stop.name, lat: stop.lat, lng: stop.lng)
            if !isFav { favorites.toggle(fav) }
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
            onClose()
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(op.brandColor).frame(width: 30, height: 30)
                    Image(systemName: "bus.fill").font(.system(size: 11, weight: .black)).foregroundStyle(op.brandTextColor)
                }
                Text(stop.name)
                    .font(DS.Font.bodyBold).foregroundStyle(DS.Color.ink).lineLimit(1)
                Spacer()
                Image(systemName: isFav ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(isFav ? DS.Color.statusOK : DS.Color.inkMute)
            }
            .padding(.vertical, 12).padding(.horizontal, 12)
            .background(DS.Color.paper)
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.08)).frame(height: 1), alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func load() async {
        isLoading = true
        defer { isLoading = false }
        let loc = await locator.getCurrentLocation()
        let origin = CLLocationCoordinate2D(latitude: loc.latitude, longitude: loc.longitude)
        func fetch(_ d: Double) async -> [OperatorMapStop] {
            await OperatorStopService.stops(
                operator: op,
                minLat: origin.latitude - d, maxLat: origin.latitude + d,
                minLng: origin.longitude - d, maxLng: origin.longitude + d,
                limit: 80
            )
        }
        var found = await fetch(0.03)
        if found.isEmpty { found = await fetch(0.09) }
        let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
        stops = found
            .sorted {
                originLoc.distance(from: CLLocation(latitude: $0.lat, longitude: $0.lng))
                    < originLoc.distance(from: CLLocation(latitude: $1.lat, longitude: $1.lng))
            }
            .prefix(40)
            .map { $0 }
    }
}

/// Shared header for the add-favourite sheets (title + close).
struct AddFavoriteSheetHeader: View {
    let title: String
    let onClose: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 20, weight: .bold))
                .foregroundStyle(DS.Color.ink)
            Spacer(minLength: 12)
            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(DS.Color.ink.opacity(0.2), lineWidth: 1.5))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 20)
        .padding(.top, 22)
        .padding(.bottom, 8)
    }
}

/// Search bar shared by the add-favourite flows.
struct FavoritePickerSearchField: View {
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)

            TextField(placeholder, text: $text)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)

            if !text.isEmpty {
                Button { text = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(DS.Color.paper2.opacity(0.72))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }
}
