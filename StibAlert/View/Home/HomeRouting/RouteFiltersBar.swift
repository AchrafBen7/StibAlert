import SwiftUI

/// Modes de transit envoyés au backend (`transitModes` de
/// `POST /api/transport/route/recommend`).
///
/// ⚠️ Les rawValues sont le vocabulaire **MOTIS**, transmis TEL QUEL sur le
/// réseau (`HomeView` fait `.map(\.rawValue)`). Ne les traduis pas, ne les
/// renomme pas : le backend n'accepte que ce sous-ensemble exact
/// (`TRAM`, `SUBWAY`, `BUS`, `RAIL`) et ignore silencieusement le reste — un
/// mode mal orthographié ne ferait pas d'erreur, il rendrait juste le filtre
/// inopérant. L'ordre de déclaration = l'ordre d'affichage.
enum RouteTransitMode: String, CaseIterable, Hashable {
    case subway = "SUBWAY"
    case tram = "TRAM"
    case bus = "BUS"
    case rail = "RAIL"

    /// Libellé affiché. Passe par `AppLocalizer` (via `L10n`) : l'app a un
    /// override de langue interne que `Locale.current` ne voit pas.
    var label: String {
        switch self {
        case .subway: return L10n.Routing.metro
        case .tram: return L10n.Routing.tram
        case .bus: return L10n.Routing.bus
        case .rail: return L10n.Routing.train
        }
    }

    var icon: String {
        switch self {
        case .subway: return "tram.fill.tunnel"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .rail: return "train.side.front.car"
        }
    }
}

/// Opérateur préféré (`preferredOperator` du backend). Les libellés sont des
/// MARQUES : jamais traduits, jamais passés au catalogue de localisation.
private struct RouteOperatorChoice: Identifiable {
    let value: String
    let label: String

    var id: String { value }

    static let all: [RouteOperatorChoice] = [
        RouteOperatorChoice(value: "stib", label: "STIB"),
        RouteOperatorChoice(value: "sncb", label: "SNCB"),
        RouteOperatorChoice(value: "delijn", label: "De Lijn"),
        RouteOperatorChoice(value: "tec", label: "TEC")
    ]
}

private enum RouteFilterKind: String, Identifiable {
    case departure
    case transports
    case operators

    var id: String { rawValue }
}

/// Rangée de filtres du sheet d'itinéraires : Départ / Transports / Opérateur.
///
/// Convention d'état, valable pour les 3 filtres : **la valeur "par défaut" est
/// l'absence de valeur** (`nil` / ensemble vide) — pas une valeur sentinelle
/// "tous". C'est ce qui permet à `HomeView.hasActiveRouteFilters` de distinguer
/// « l'utilisateur n'a rien filtré » de « l'utilisateur a filtré et le backend
/// n'a rien trouvé » (état vide honnête au lieu d'un repli Apple Maps qui
/// ignorerait le filtre).
///
/// Style : capsule claire au repos, capsule noire pleine + coche quand active —
/// même motif que les zones De Lijn/TEC (`OperatorCatalogViews.zoneChip`).
struct RouteFiltersBar: View {
    @Binding var departureTime: Date?
    @Binding var transitModes: Set<RouteTransitMode>
    @Binding var preferredOperator: String?
    var onChange: () -> Void = {}

    /// SEUL état local de la barre. Les brouillons vivent DANS chaque sheet (cf.
    /// `TransportModesFilterSheet` & co.), pas ici : un `@State` de la barre muté
    /// dans le même cycle que la présentation du sheet est capturé AVANT sa
    /// mise à jour — les 4 modes pré-cochés s'affichaient alors décochés. Les
    /// `@Binding` ci-dessus, eux, lisent toujours la source de vérité (HomeView)
    /// et peuvent donc être passés tels quels à l'ouverture.
    @State private var activeSheet: RouteFilterKind?

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.timeZone = TimeZone(identifier: "Europe/Brussels")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                capsule(.departure, label: departureLabel, isActive: departureTime != nil)
                capsule(.transports, label: transportsLabel, isActive: !transitModes.isEmpty)
                capsule(.operators, label: operatorLabel, isActive: preferredOperator != nil)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 2) // le stroke des capsules ne doit pas être rogné
        }
        // Chaque sheet reçoit la valeur COURANTE (lue à travers le @Binding, donc
        // jamais périmée) et gère son propre brouillon. Il applique au dismiss —
        // bouton "Terminé" comme swipe — et ne relance la requête que si la
        // valeur a réellement changé : ouvrir/refermer sans rien toucher ne doit
        // pas recalculer l'itinéraire, et cocher 4 modes ne doit pas déclencher
        // 4 requêtes.
        .sheet(item: $activeSheet) { kind in
            switch kind {
            case .departure:
                DepartureFilterSheet(initial: departureTime) { newValue in
                    guard newValue != departureTime else { return }
                    departureTime = newValue
                    onChange()
                }
            case .transports:
                TransportModesFilterSheet(initial: transitModes) { newValue in
                    guard newValue != transitModes else { return }
                    transitModes = newValue
                    onChange()
                }
            case .operators:
                OperatorFilterSheet(initial: preferredOperator) { newValue in
                    guard newValue != preferredOperator else { return }
                    preferredOperator = newValue
                    onChange()
                }
            }
        }
    }

    // MARK: - Capsules

    private func capsule(_ kind: RouteFilterKind, label: String, isActive: Bool) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            activeSheet = kind
        } label: {
            HStack(spacing: 6) {
                if isActive {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .black))
                }
                Text(label)
                    .font(.system(size: 12, weight: .black, design: .rounded))
                    .lineLimit(1)
                Image(systemName: "chevron.down")
                    .font(.system(size: 9, weight: .black))
                    .opacity(0.55)
            }
            .foregroundStyle(isActive ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 11)
            .frame(height: 34)
            .background(isActive ? DS.Color.ink : DS.Color.paper)
            .overlay(
                Capsule()
                    .stroke(isActive ? DS.Color.ink : DS.Color.ink.opacity(0.14), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }

    private var departureLabel: String {
        guard let departureTime else { return L10n.Routing.now }
        return L10n.Routing.departureAt(Self.timeFormatter.string(from: departureTime))
    }

    /// Les modes choisis en toutes lettres tant que ça tient (« Tram, Bus »),
    /// sinon un décompte — au-delà de 2, la capsule déborderait.
    private var transportsLabel: String {
        let selected = RouteTransitMode.allCases.filter { transitModes.contains($0) }
        guard !selected.isEmpty else { return L10n.Routing.transportsFilter }
        if selected.count <= 2 {
            return selected.map(\.label).joined(separator: ", ")
        }
        return L10n.Routing.transportsCount(selected.count)
    }

    private var operatorLabel: String {
        guard let preferredOperator,
              let choice = RouteOperatorChoice.all.first(where: { $0.value == preferredOperator })
        else { return L10n.Routing.operatorsFilter }
        return choice.label
    }

}

/// Sheet « Heure de départ » : bouton Maintenant + roue heure/minute.
private struct DepartureFilterSheet: View {
    let onApply: (Date?) -> Void

    @State private var usesNow: Bool
    @State private var time: Date

    /// Le brouillon est amorcé DANS le sheet (et non par le parent avant la
    /// présentation) : un `@State` du parent muté dans le même cycle que la
    /// présentation est capturé avant sa mise à jour.
    init(initial: Date?, onApply: @escaping (Date?) -> Void) {
        self.onApply = onApply
        _usesNow = State(initialValue: initial == nil)
        _time = State(initialValue: initial ?? Date())
    }

    var body: some View {
        RouteFilterSheetShell(title: L10n.Routing.departureTimeTitle, detent: .height(360)) {
            VStack(spacing: 14) {
                RouteFilterRow(label: L10n.Routing.now, icon: "bolt.fill", isSelected: usesNow) {
                    usesNow = true
                }

                DatePicker(
                    L10n.Routing.departureTimeTitle,
                    selection: Binding(
                        get: { time },
                        set: { newValue in
                            time = newValue
                            usesNow = false // toucher la roue = vouloir une heure précise
                        }
                    ),
                    displayedComponents: .hourAndMinute
                )
                .datePickerStyle(.wheel)
                .labelsHidden()
                .opacity(usesNow ? 0.45 : 1)
            }
        }
        .onDisappear { onApply(usesNow ? nil : Self.normalized(time)) }
    }

    /// Recale l'heure choisie dans la fenêtre J+0 / J+1.
    ///
    /// La roue ne rend que des heures/minutes : à 13 h, choisir « 08:00 » produit
    /// un `Date` situé CE MATIN, donc dans le passé. Le backend ignore en silence
    /// une heure passée et retombe sur « maintenant » — la capsule afficherait
    /// « Départ 08:00 » au-dessus d'un itinéraire calculé pour maintenant, c'est-
    /// à-dire un mensonge. Une heure déjà passée ne peut donc désigner que demain.
    /// La tolérance d'une minute est celle du backend.
    private static func normalized(_ date: Date) -> Date {
        guard date < Date().addingTimeInterval(-60) else { return date }
        return date.addingTimeInterval(24 * 3600)
    }
}

/// Sheet « Transports » : multi-sélection Métro / Tram / Bus / Train.
private struct TransportModesFilterSheet: View {
    let onApply: (Set<RouteTransitMode>) -> Void

    @State private var selection: Set<RouteTransitMode>

    init(initial: Set<RouteTransitMode>, onApply: @escaping (Set<RouteTransitMode>) -> Void) {
        self.onApply = onApply
        // Filtre inactif = ensemble vide = « tous » : on coche donc les 4 modes.
        // Afficher 0 coche laisserait croire qu'aucun transport n'est autorisé.
        _selection = State(initialValue: initial.isEmpty ? Set(RouteTransitMode.allCases) : initial)
    }

    var body: some View {
        RouteFilterSheetShell(title: L10n.Routing.transportsFilter, detent: .height(430)) {
            VStack(spacing: 10) {
                ForEach(RouteTransitMode.allCases, id: \.self) { mode in
                    RouteFilterRow(label: mode.label, icon: mode.icon, isSelected: selection.contains(mode)) {
                        if selection.contains(mode) {
                            selection.remove(mode)
                        } else {
                            selection.insert(mode)
                        }
                    }
                }

                Button { selection = Set(RouteTransitMode.allCases) } label: {
                    Text(L10n.Routing.allTransports)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .onDisappear {
            // Les 4 modes cochés (ou aucun) == aucun filtre : on repasse à
            // l'ensemble vide, sinon la capsule resterait « active » et le
            // backend recevrait un `transitModes` qui n'exclut rien.
            let all = Set(RouteTransitMode.allCases)
            onApply(selection.isEmpty || selection == all ? [] : selection)
        }
    }
}

/// Sheet « Opérateurs » : sélection UNIQUE (le backend ne prend qu'un
/// `preferredOperator`), un 2ᵉ tap sur le même désélectionne.
private struct OperatorFilterSheet: View {
    let onApply: (String?) -> Void

    @State private var selection: String?

    init(initial: String?, onApply: @escaping (String?) -> Void) {
        self.onApply = onApply
        _selection = State(initialValue: initial)
    }

    var body: some View {
        RouteFilterSheetShell(title: L10n.Routing.operatorsFilter, detent: .height(430)) {
            VStack(spacing: 10) {
                ForEach(RouteOperatorChoice.all) { choice in
                    RouteFilterRow(
                        label: choice.label,
                        icon: "building.2.fill",
                        isSelected: selection == choice.value
                    ) {
                        selection = selection == choice.value ? nil : choice.value
                    }
                }

                Button { selection = nil } label: {
                    Text(L10n.Routing.allOperators)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
                .padding(.top, 2)
            }
        }
        .onDisappear { onApply(selection) }
    }
}

/// Enveloppe commune des 3 sheets de filtre : titre, contenu, bouton "Terminé".
/// Le bouton ne fait que FERMER — chaque sheet applique son brouillon dans son
/// propre `onDisappear`, donc un swipe vers le bas vaut validation lui aussi
/// (pas de modification perdue en silence).
private struct RouteFilterSheetShell<Content: View>: View {
    let title: String
    let detent: PresentationDetent
    @ViewBuilder var content: Content

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(title)
                .font(DS.Font.displayH3)
                .foregroundStyle(DS.Color.ink)

            content

            Spacer(minLength: 0)

            Button {
                dismiss()
            } label: {
                Text(L10n.Common.done)
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.primaryForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
                    .background(DS.Color.ink)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper.ignoresSafeArea())
        .presentationDetents([detent])
        .presentationDragIndicator(.visible)
    }
}

/// Rangée sélectionnable des sheets de filtre — même grammaire que les capsules
/// (noir plein + coche quand actif), en pleine largeur.
private struct RouteFilterRow: View {
    let label: String
    let icon: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            withAnimation(.easeInOut(duration: 0.18)) {
                action()
            }
        } label: {
            HStack(spacing: 10) {
                Image(systemName: icon)
                    .font(.system(size: 13, weight: .bold))
                    .frame(width: 20)
                Text(label)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .lineLimit(1)
                Spacer(minLength: 8)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .black))
                }
            }
            .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 14)
            .frame(height: 48)
            .background(isSelected ? DS.Color.ink : DS.Color.paper2.opacity(0.6))
            .overlay(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}
