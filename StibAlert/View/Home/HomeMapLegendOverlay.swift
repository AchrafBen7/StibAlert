import SwiftUI

/// Interactive map layer panel. Each operator/extra row is a
/// toggle wired to the map; De Lijn / TEC are shown as disabled placeholders
/// until their datasets land.
struct MapLegendOverlay: View {
    @Binding var showStibStops: Bool
    @Binding var showSncbStations: Bool
    @Binding var showDelijnStops: Bool
    @Binding var showTecStops: Bool
    @Binding var showVilloStations: Bool
    @Binding var showEventImpacts: Bool
    @Binding var showCommunitySignals: Bool
    @Binding var showOfficialSignals: Bool
    @Binding var signalsFavoritesOnly: Bool
    let onDismiss: () -> Void

    /// Distance sous le haut de la zone sûre : le panneau pend juste sous la
    /// rangée de puces (Itinéraires / Favoris / Alertes).
    private static let topOffset: CGFloat = 122
    /// Place laissée en bas pour ne jamais recouvrir la barre d'onglets.
    private static let bottomReserve: CGFloat = 104

    var body: some View {
        // Le `GeometryReader` accepte exactement la taille proposée par le
        // parent : il ne peut donc plus la gonfler. C'était toute l'origine du
        // bug — la liste, sans hauteur maximale ni défilement, mesurait ~750 pt
        // et débordait de l'écran. Comme la ZStack racine prend la taille de son
        // plus grand enfant, elle grandissait avec le panneau, et les
        // `.overlay(alignment: .top / .bottom)` suivaient : la barre de
        // recherche remontait dans la barre d'état, la barre d'onglets
        // descendait hors écran, et le bas de la liste était coupé.
        GeometryReader { proxy in
            ZStack(alignment: .topTrailing) {
                Color.black.opacity(0.12)
                    .ignoresSafeArea()
                    .onTapGesture(perform: onDismiss)

                VStack(alignment: .leading, spacing: 0) {
                    legendHeader

                    ScrollView(.vertical, showsIndicators: true) {
                        VStack(alignment: .leading, spacing: 0) {
                            legendSubheader(AppLocalizer.string("layers.operators", defaultValue: "OPÉRATEURS"))
                            operatorToggleRow(asset: "operator-stib", title: "STIB-MIVB", isOn: $showStibStops)
                            operatorToggleRow(asset: "operator-sncb", title: "SNCB", isOn: $showSncbStations)
                            // S1 — De Lijn / TEC activés maintenant que le live multi-op
                            // marche (commits c42fb27 De Lijn live + 0ae65db TEC live).
                            operatorToggleRow(asset: "operator-delijn", title: "De Lijn", isOn: $showDelijnStops)
                            operatorToggleRow(asset: "operator-tec", title: "TEC", isOn: $showTecStops)

                            legendSubheader(AppLocalizer.string("layers.signalements", defaultValue: "SIGNALEMENTS"))
                            symbolToggleRow(systemImage: "exclamationmark.bubble.fill", fill: DS.Color.warning,
                                            title: AppLocalizer.string("layers.community_signals", defaultValue: "Communauté"),
                                            isOn: $showCommunitySignals)
                            symbolToggleRow(systemImage: "exclamationmark.triangle.fill", fill: DS.Color.info,
                                            title: AppLocalizer.string("layers.official_signals", defaultValue: "Officiel"),
                                            isOn: $showOfficialSignals)
                            symbolToggleRow(systemImage: "star.fill", fill: DS.Color.primary,
                                            title: AppLocalizer.string("layers.my_lines_only", defaultValue: "Mes lignes seulement"),
                                            isOn: $signalsFavoritesOnly)

                            legendSubheader(AppLocalizer.string("layers.others", defaultValue: "AUTRES"))
                            iconToggleRow(letter: "V", fill: Color(hex: "#2E8B57"), title: "Villo!", isOn: $showVilloStations)
                            iconToggleRow(letter: "E", fill: Color(hex: "#8E2AD1"), title: AppLocalizer.string("scope.events", defaultValue: "Événements"), isOn: $showEventImpacts)

                            // S4 — Preset rapide "Vue épurée" : cache Villo + événements
                            // + véhicules pour ne garder que STIB + SNCB + perturbations.
                            // Réduit la saturation visuelle de ~63 marqueurs à ~40.
                            cleanViewPresetRow
                        }
                    }
                }
                .frame(width: 268, alignment: .leading)
                .frame(
                    maxHeight: max(240, proxy.size.height - Self.topOffset - Self.bottomReserve),
                    alignment: .top
                )
                .background(DS.Color.paper)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
                )
                .shadow(color: DS.Color.ink.opacity(0.16), radius: 18, y: 10)
                .padding(.top, Self.topOffset)
                .padding(.trailing, 18)
            }
        }
    }

    private var legendHeader: some View {
        HStack {
            // Chaîne littérale volontaire : déjà extraite et traduite
            // (« LAGEN » en néerlandais). Une clé sémantique repartirait de zéro.
            Text("CALQUES")
            Spacer()
            // Était une icône de réglages purement décorative, à l'endroit
            // exact où l'on cherche une croix. C'en est une maintenant.
            Button(action: onDismiss) {
                Image(systemName: "xmark")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(DS.Color.paper)
                    .frame(width: 30, height: 30)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(AppLocalizer.string("common.close", defaultValue: "Fermer"))
        }
        .font(DS.Font.label.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.paper)
        .padding(.leading, 12)
        .padding(.trailing, 6)
        .frame(height: 42)
        .background(DS.Color.ink)
    }

    private func legendSubheader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
        .font(DS.Font.label.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.inkMute)
        .padding(.horizontal, 12)
        .frame(height: 34)
        .background(DS.Color.paper2.opacity(0.65))
    }

    private func operatorToggleRow(asset: String, title: String, isOn: Binding<Bool>) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            isOn.wrappedValue.toggle()
        } label: {
            rowBody(
                leading: operatorLogo(asset, active: isOn.wrappedValue),
                title: title,
                titleColor: isOn.wrappedValue ? DS.Color.ink : DS.Color.inkMute,
                trailing: AnyView(toggleIndicator(isOn: isOn.wrappedValue))
            )
        }
        .buttonStyle(.plain)
    }

    /// Vrai quand seuls les calques essentiels tournent. L'ancienne version ne
    /// regardait que Villo + événements et laissait De Lijn / TEC allumés : la
    /// « vue épurée » ne l'était pas vraiment.
    private var isCleanView: Bool {
        !showVilloStations && !showEventImpacts && !showDelijnStops && !showTecStops
    }

    /// La carte s'ouvre désormais épurée. Ce raccourci sert donc surtout à
    /// **tout rallumer** d'un coup — et à revenir au calme sans décocher 4 cases.
    private var cleanViewPresetRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            let turnOn = isCleanView
            withAnimation(.easeOut(duration: 0.2)) {
                showVilloStations = turnOn
                showEventImpacts = turnOn
                showDelijnStops = turnOn
                showTecStops = turnOn
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isCleanView ? "square.stack.3d.up.fill" : "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(DS.Color.aiForeground)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DS.Color.ai))
                    .overlay(Circle().stroke(DS.Color.paper.opacity(0.5), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text(isCleanView ? "Tout afficher" : "Vue épurée")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text(isCleanView
                         ? "Villo, événements, De Lijn, TEC"
                         : "Ne garder que STIB, SNCB et les alertes")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMute)
                }
                Spacer()
                Image(systemName: isCleanView ? "arrow.right.circle" : "sparkles")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Color.ink.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.Color.paper2.opacity(0.6))
        }
        .buttonStyle(.plain)
    }


    private func iconToggleRow(letter: String, fill: Color, title: String, isOn: Binding<Bool>) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            isOn.wrappedValue.toggle()
        } label: {
            rowBody(
                leading: AnyView(
                    ZStack {
                        Circle()
                            .fill(isOn.wrappedValue ? fill : DS.Color.paper2)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
                        Text(letter)
                            .font(.system(size: 16, weight: .heavy, design: .rounded))
                            .foregroundStyle(isOn.wrappedValue ? .white : DS.Color.inkMute)
                    }
                ),
                title: title,
                titleColor: isOn.wrappedValue ? DS.Color.ink : DS.Color.inkMute,
                trailing: AnyView(toggleIndicator(isOn: isOn.wrappedValue))
            )
        }
        .buttonStyle(.plain)
    }

    /// Variante de `iconToggleRow` avec une icône SF au lieu d'une lettre —
    /// langue-neutre, utilisée pour les signalements (communauté / officiel).
    private func symbolToggleRow(systemImage: String, fill: Color, title: String, isOn: Binding<Bool>) -> some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            isOn.wrappedValue.toggle()
        } label: {
            rowBody(
                leading: AnyView(
                    ZStack {
                        Circle()
                            .fill(isOn.wrappedValue ? fill : DS.Color.paper2)
                            .frame(width: 40, height: 40)
                            .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
                        Image(systemName: systemImage)
                            .font(.system(size: 15, weight: .bold))
                            .foregroundStyle(isOn.wrappedValue ? .white : DS.Color.inkMute)
                    }
                ),
                title: title,
                titleColor: isOn.wrappedValue ? DS.Color.ink : DS.Color.inkMute,
                trailing: AnyView(toggleIndicator(isOn: isOn.wrappedValue))
            )
        }
        .buttonStyle(.plain)
    }

    private func rowBody(leading: some View, title: String, titleColor: Color, trailing: AnyView) -> some View {
        HStack(spacing: 12) {
            leading
            Text(title)
                .font(.system(size: 15, weight: .bold))
                .foregroundStyle(titleColor)
            Spacer()
            trailing
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .overlay(alignment: .bottom) {
            Rectangle()
                .fill(DS.Color.ink.opacity(0.08))
                .frame(height: 1)
                .padding(.leading, 66)
        }
    }

    private func operatorLogo(_ asset: String, active: Bool) -> AnyView {
        AnyView(
            Image(asset)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .frame(width: 40, height: 40)
                .background(Circle().fill(DS.Color.paper2.opacity(0.6)))
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
                .saturation(active ? 1 : 0)
                .opacity(active ? 1 : 0.5)
        )
    }

    private func toggleIndicator(isOn: Bool) -> some View {
        Image(systemName: isOn ? "checkmark.circle.fill" : "circle")
            .font(.system(size: 20, weight: .semibold))
            .foregroundStyle(isOn ? DS.Color.statusOK : DS.Color.ink.opacity(0.22))
    }
}
