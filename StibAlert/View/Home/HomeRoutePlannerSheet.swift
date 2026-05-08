import SwiftUI
import MapKit

struct HomeRoutePlannerSheet: View {
    @Binding var isPresented: Bool

    let userCoordinate: CLLocationCoordinate2D?
    let isRouting: Bool
    let onPlanRoute: (MKMapItem, MKMapItem, String) -> Void

    @State private var departureQuery = "Ma position"
    @State private var arrivalQuery = ""
    @State private var departureSuggestions: [MKMapItem] = []
    @State private var arrivalSuggestions: [MKMapItem] = []
    @State private var selectedDeparture: MKMapItem?
    @State private var selectedArrival: MKMapItem?
    @State private var searchTask: Task<Void, Never>?
    @State private var isResolving = false
    @State private var errorMessage: String?
    @FocusState private var focusedField: PlannerField?

    private enum PlannerField: Hashable {
        case departure
        case arrival
    }

    private let brussels = CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    header
                    routeFields
                    suggestionsBlock
                    infoCard
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                .padding(.bottom, 110)
            }
            .background(DS.Color.background.ignoresSafeArea())
            .safeAreaInset(edge: .bottom) {
                bottomAction
            }
            .toolbar(.hidden, for: .navigationBar)
            .onAppear {
                focusedField = .arrival
            }
        }
        .preferredColorScheme(.light)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Itinéraires")
                        .displayH1()

                    Text("Choisis un départ et une arrivée pour calculer une route précise.")
                        .font(DS.Font.body)
                        .foregroundStyle(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer()

                Button {
                    isPresented = false
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 18, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 44, height: 44)
                        .background(DS.Color.paper)
                        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                                .stroke(DS.Color.border, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(DS.Color.ink)
                .frame(height: 3)
        }
    }

    private var routeFields: some View {
        VStack(spacing: 10) {
            plannerField(
                title: "Départ",
                icon: "location.fill",
                text: $departureQuery,
                focused: .departure,
                placeholder: "Adresse de départ"
            )

            plannerField(
                title: "Arrivée",
                icon: "mappin.and.ellipse",
                text: $arrivalQuery,
                focused: .arrival,
                placeholder: "Où vas-tu ?"
            )
        }
        .padding(14)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
        .shadow(DS.Shadow.raised)
    }

    private func plannerField(
        title: String,
        icon: String,
        text: Binding<String>,
        focused: PlannerField,
        placeholder: String
    ) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(focused == .departure ? DS.Color.community : DS.Color.primary)
                .frame(width: 34, height: 34)
                .background((focused == .departure ? DS.Color.community : DS.Color.primary).opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(DS.Font.monoSmall)
                    .tracking(1.4)
                    .textCase(.uppercase)
                    .foregroundStyle(DS.Color.inkMute)

                TextField(placeholder, text: text)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .focused($focusedField, equals: focused)
                    .submitLabel(.search)
                    .onChange(of: text.wrappedValue) { _, newValue in
                        handleQueryChange(newValue, for: focused)
                    }
            }

            if !text.wrappedValue.isEmpty && !(focused == .departure && text.wrappedValue == "Ma position") {
                Button {
                    clearField(focused)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 66)
        .background(focusedField == focused ? DS.Color.secondary : DS.Color.background)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(focusedField == focused ? DS.Color.ink.opacity(0.28) : DS.Color.border, lineWidth: 1)
        )
    }

    @ViewBuilder
    private var suggestionsBlock: some View {
        let suggestions = focusedField == .departure ? departureSuggestions : arrivalSuggestions

        if focusedField == .departure || !suggestions.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                if focusedField == .departure {
                    Button {
                        selectedDeparture = nil
                        departureQuery = "Ma position"
                        departureSuggestions = []
                        focusedField = .arrival
                    } label: {
                        suggestionRow(
                            icon: "location.viewfinder",
                            title: "Ma position actuelle",
                            subtitle: "Utiliser ta position comme départ"
                        )
                    }
                    .buttonStyle(.plain)
                }

                ForEach(suggestions, id: \.self) { item in
                    Button {
                        selectSuggestion(item)
                    } label: {
                        suggestionRow(
                            icon: "mappin.circle.fill",
                            title: item.name ?? "Adresse",
                            subtitle: item.placemark.title ?? "Bruxelles"
                        )
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }

    private func suggestionRow(icon: String, title: String, subtitle: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(DS.Color.primary)
                .frame(width: 40, height: 40)
                .background(DS.Color.primary.opacity(0.10))
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)

                Text(subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }

            Spacer()

            Image(systemName: "arrow.up.right")
                .font(.system(size: 12, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
        }
        .padding(12)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }

    private var infoCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Calcul STIB + carte")
                .sectionTitle()

            Text("Le calcul réutilise les itinéraires transport existants, avec alternatives transport, vélo et marche quand elles sont disponibles.")
                .font(DS.Font.bodySmall)
                .foregroundStyle(DS.Color.inkSoft)
                .fixedSize(horizontal: false, vertical: true)

            if let errorMessage {
                Text(errorMessage)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.statusMajor)
            }
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper2.opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
    }

    private var bottomAction: some View {
        VStack(spacing: 10) {
            Button {
                Task { await submit() }
            } label: {
                HStack(spacing: 10) {
                    if isResolving || isRouting {
                        ProgressView()
                            .tint(DS.Color.primaryForeground)
                    } else {
                        Image(systemName: "arrow.triangle.turn.up.right.diamond.fill")
                            .font(.system(size: 16, weight: .bold))
                    }

                    Text("Voir les itinéraires")
                        .font(.system(size: 15, weight: .bold))
                }
            }
            .buttonStyle(DS.PrimaryButtonStyle())
            .disabled(!canSubmit || isResolving || isRouting)
            .opacity(canSubmit ? 1 : 0.45)
        }
        .padding(.horizontal, 20)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .background(.ultraThinMaterial)
    }

    private var canSubmit: Bool {
        let arrivalReady = selectedArrival != nil || !arrivalQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        let departureReady = selectedDeparture != nil
            || userCoordinate != nil
            || !departureQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return arrivalReady && departureReady
    }

    private func handleQueryChange(_ value: String, for field: PlannerField) {
        if field == .departure {
            selectedDeparture = nil
        } else {
            selectedArrival = nil
        }

        searchTask?.cancel()
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count >= 2, !(field == .departure && trimmed == "Ma position") else {
            if field == .departure {
                departureSuggestions = []
            } else {
                arrivalSuggestions = []
            }
            return
        }

        searchTask = Task {
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            let results = await searchSuggestions(for: trimmed)
            await MainActor.run {
                if field == .departure {
                    departureSuggestions = results
                } else {
                    arrivalSuggestions = results
                }
            }
        }
    }

    private func clearField(_ field: PlannerField) {
        if field == .departure {
            departureQuery = ""
            selectedDeparture = nil
            departureSuggestions = []
        } else {
            arrivalQuery = ""
            selectedArrival = nil
            arrivalSuggestions = []
        }
    }

    private func selectSuggestion(_ item: MKMapItem) {
        if focusedField == .departure {
            selectedDeparture = item
            departureQuery = item.name ?? item.placemark.title ?? ""
            departureSuggestions = []
            focusedField = .arrival
        } else {
            selectedArrival = item
            arrivalQuery = item.name ?? item.placemark.title ?? ""
            arrivalSuggestions = []
            focusedField = nil
        }
    }

    @MainActor
    private func submit() async {
        isResolving = true
        errorMessage = nil
        defer { isResolving = false }

        let resolvedArrival: MKMapItem?
        if let selectedArrival {
            resolvedArrival = selectedArrival
        } else {
            resolvedArrival = await resolve(query: arrivalQuery)
        }

        guard let destination = resolvedArrival else {
            errorMessage = "Adresse d’arrivée introuvable."
            return
        }

        let source: MKMapItem
        let originName: String

        if departureQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || departureQuery.trimmingCharacters(in: .whitespacesAndNewlines) == "Ma position" {
            guard let userCoordinate else {
                errorMessage = "Position actuelle indisponible."
                return
            }
            source = MKMapItem(placemark: MKPlacemark(coordinate: userCoordinate))
            source.name = "Votre position"
            originName = "Votre position"
        } else if let selectedDeparture {
            source = selectedDeparture
            originName = selectedDeparture.name ?? selectedDeparture.placemark.title ?? "Départ"
        } else if let resolvedDeparture = await resolve(query: departureQuery) {
            source = resolvedDeparture
            originName = resolvedDeparture.name ?? resolvedDeparture.placemark.title ?? "Départ"
        } else {
            errorMessage = "Adresse de départ introuvable."
            return
        }

        isPresented = false
        onPlanRoute(source, destination, originName)
    }

    private func searchSuggestions(for text: String) async -> [MKMapItem] {
        let request = MKLocalSearch.Request()
        request.naturalLanguageQuery = text
        request.resultTypes = [.address, .pointOfInterest]
        request.region = MKCoordinateRegion(
            center: brussels,
            span: MKCoordinateSpan(latitudeDelta: 0.35, longitudeDelta: 0.35)
        )

        guard let response = try? await MKLocalSearch(request: request).start() else {
            return []
        }

        var unique: [MKMapItem] = []
        var seen = Set<String>()
        for item in response.mapItems {
            let key = "\(item.name ?? "")|\(item.placemark.title ?? "")"
            if seen.insert(key).inserted {
                unique.append(item)
            }
        }
        return Array(unique.prefix(6))
    }

    private func resolve(query: String) async -> MKMapItem? {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return await searchSuggestions(for: trimmed).first
    }
}
