import CoreLocation
import SwiftUI

/// Shared SNCB gare browser used by both the Horaires tab and the Infos trafic
/// (SNCB) tab so the two read identically: the nearest gares pinned on top,
/// a search field across all of Belgium, then a province → gares drill-down.
///
/// The component is navigation-agnostic — every gare row is a plain button that
/// calls `onSelect`. The host decides what a tap does (push the schedule page
/// in Horaires, present the gare's Infos trafic page in Reports).
struct SncbGareDirectory: View {
    @Binding var searchQuery: String
    /// When true the component renders its own search field (Infos trafic).
    /// Horaires passes false because its header already owns the search bar.
    var showsSearchField: Bool = false
    var userCoordinate: CLLocationCoordinate2D?
    /// Number of active community reports on a gare — drives the small red
    /// warning badge in the Infos trafic context. Defaults to none (Horaires).
    var badgeCount: (SNCBStation) -> Int = { _ in 0 }
    var onSelect: (SNCBStation) -> Void

    @State private var expandedProvinces: Set<String> = []

    private var trimmedQuery: String {
        searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: DS.Spacing.lg) {
            if showsSearchField {
                searchField
            }

            if trimmedQuery.isEmpty {
                let nearest = nearestStations
                if !nearest.isEmpty {
                    gareListContainer {
                        ForEach(Array(nearest.enumerated()), id: \.element.id) { index, item in
                            gareRow(item.station, subtitle: "\(formattedDistance(item.distanceMeters)) · Gare SNCB", proximityLabel: proximityLabel(index))
                        }
                    }
                }

                ForEach(SNCBStationService.stationsByProvince, id: \.province) { group in
                    provinceSection(group)
                }
            } else {
                let results = filteredStations
                VStack(alignment: .leading, spacing: 10) {
                    sectionHeader(icon: "magnifyingglass", title: "Résultats", count: results.count, expanded: true)
                    if results.isEmpty {
                        Text("Aucune gare trouvée")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkMute)
                            .padding(.vertical, 8)
                    } else {
                        gareListContainer {
                            ForEach(results) { station in
                                gareRow(station, subtitle: "\(station.displayProvince) · Gare SNCB", proximityLabel: nil)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Search field (Infos trafic only)

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
            TextField("Chercher une gare", text: $searchQuery)
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
            if !searchQuery.isEmpty {
                Button { searchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 46)
        .background(DS.Color.paper2.opacity(0.7))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: - Province section

    private func provinceSection(_ group: (province: String, stations: [SNCBStation])) -> some View {
        let isOpen = expandedProvinces.contains(group.province)
        return VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.easeInOut(duration: 0.2)) {
                    if isOpen { expandedProvinces.remove(group.province) }
                    else { expandedProvinces.insert(group.province) }
                }
            } label: {
                sectionHeader(icon: "mappin.and.ellipse", title: group.province, count: group.stations.count, expanded: isOpen)
            }
            .buttonStyle(.plain)

            if isOpen {
                gareListContainer {
                    ForEach(group.stations) { station in
                        gareRow(station, subtitle: "Gare SNCB", proximityLabel: nil)
                    }
                }
            }
        }
    }

    // MARK: - Rows

    private func gareRow(_ station: SNCBStation, subtitle: String, proximityLabel: String?) -> some View {
        let alerts = badgeCount(station)
        return Button { onSelect(station) } label: {
            HStack(spacing: 12) {
                ZStack(alignment: .topTrailing) {
                    Image("operator-sncb")
                        .renderingMode(.original)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 30, height: 30)
                        .frame(width: 46, height: 46)
                        .background(DS.Color.paper2.opacity(0.65))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    if alerts > 0 {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .font(.system(size: 9, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 18, height: 18)
                            .background(Circle().fill(DS.Color.statusMajor))
                            .overlay(Circle().stroke(DS.Color.paper, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }

                VStack(alignment: .leading, spacing: 3) {
                    if let proximityLabel {
                        Text(proximityLabel)
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(Color(hex: "#0055A4"))
                    }
                    Text(station.displayName)
                        .font(DS.Font.bodyBold)
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Text(alerts > 0 ? "\(alerts) signalement\(alerts > 1 ? "s" : "") · \(subtitle)" : subtitle)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(alerts > 0 ? DS.Color.statusMajor : DS.Color.inkMute)
                        .lineLimit(1)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.vertical, 11)
            .padding(.horizontal, 12)
            .background(DS.Color.paper)
            .overlay(Rectangle().fill(DS.Color.ink.opacity(0.10)).frame(height: 1), alignment: .bottom)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private func sectionHeader(icon: String, title: String, count: Int, expanded: Bool) -> some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 30, height: 30)
                .background(DS.Color.paper2)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
            Text(title.uppercased())
                .font(DS.Font.eyebrow)
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)
            Spacer()
            Text("\(count)")
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(DS.Color.inkMute)
            Image(systemName: "chevron.down")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
                .rotationEffect(.degrees(expanded ? 0 : -90))
        }
        .contentShape(Rectangle())
    }

    private func gareListContainer<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(spacing: 0) { content() }
            .background(DS.Color.paper.opacity(0.95))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
    }

    // MARK: - Data helpers

    private var nearestStations: [SNCBStationDistance] {
        SNCBStationService.nearbyStations(around: userCoordinate, radiusMeters: 35_000, limit: 3)
    }

    private var filteredStations: [SNCBStation] {
        let needle = trimmedQuery
            .folding(options: .diacriticInsensitive, locale: .current)
            .lowercased()
        guard !needle.isEmpty else { return SNCBStationService.allStations }
        return SNCBStationService.allStations.filter { station in
            station.displayName
                .folding(options: .diacriticInsensitive, locale: .current)
                .lowercased()
                .contains(needle)
        }
    }

    private func distanceFromUser(to station: SNCBStation) -> Int {
        let origin = userCoordinate ?? CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
        let distance = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
            .distance(from: CLLocation(latitude: station.lat, longitude: station.lng))
        return Int(distance.rounded())
    }

    private func formattedDistance(_ meters: Int) -> String {
        if meters >= 1000 {
            return String(format: "%.1f km", Double(meters) / 1000)
        }
        return "\(meters)m"
    }

    private func proximityLabel(_ index: Int) -> String {
        switch index {
        case 0: return "GARE LA PLUS PROCHE"
        case 1: return "2E GARE PROCHE"
        default: return "3E GARE PROCHE"
        }
    }
}
