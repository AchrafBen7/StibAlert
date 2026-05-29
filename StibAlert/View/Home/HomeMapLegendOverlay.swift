import SwiftUI

/// Interactive map layer panel (the 🗂 button). Each operator/extra row is a
/// toggle wired to the map; De Lijn / TEC are shown as disabled placeholders
/// until their datasets land.
struct MapLegendOverlay: View {
    @Binding var showStibStops: Bool
    @Binding var showSncbStations: Bool
    @Binding var showDelijnStops: Bool
    @Binding var showTecStops: Bool
    @Binding var showVilloStations: Bool
    @Binding var showEventImpacts: Bool
    let onDismiss: () -> Void

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.opacity(0.12)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                legendHeader

                legendSubheader("OPÉRATEURS")
                operatorToggleRow(asset: "operator-stib", title: "STIB-MIVB", isOn: $showStibStops)
                operatorToggleRow(asset: "operator-sncb", title: "SNCB", isOn: $showSncbStations)
                // S1 — De Lijn / TEC activés maintenant que le live multi-op
                // marche (commits c42fb27 De Lijn live + 0ae65db TEC live).
                operatorToggleRow(asset: "operator-delijn", title: "De Lijn", isOn: $showDelijnStops)
                operatorToggleRow(asset: "operator-tec", title: "TEC", isOn: $showTecStops)

                legendSubheader("AUTRES")
                iconToggleRow(letter: "V", fill: Color(hex: "#2E8B57"), title: "Villo!", isOn: $showVilloStations)
                iconToggleRow(letter: "E", fill: Color(hex: "#8E2AD1"), title: "Évènements", isOn: $showEventImpacts)

                // S4 — Preset rapide "Vue épurée" : cache Villo + événements
                // + véhicules pour ne garder que STIB + SNCB + perturbations.
                // Réduit la saturation visuelle de ~63 marqueurs à ~40.
                cleanViewPresetRow
            }
            .frame(width: 268, alignment: .leading)
            .background(DS.Color.paper)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
            )
            .shadow(color: DS.Color.ink.opacity(0.16), radius: 18, y: 10)
            .padding(.top, 122)
            .padding(.trailing, 18)
        }
    }

    private var legendHeader: some View {
        HStack {
            Text("CALQUES")
            Spacer()
            Image(systemName: "square.3.layers.3d.down.right")
                .font(.system(size: 14, weight: .bold))
        }
        .font(DS.Font.mono.weight(.bold))
        .tracking(2)
        .foregroundStyle(DS.Color.paper)
        .padding(.horizontal, 12)
        .frame(height: 42)
        .background(DS.Color.ink)
    }

    private func legendSubheader(_ title: String) -> some View {
        HStack {
            Text(title)
            Spacer()
        }
        .font(DS.Font.mono.weight(.bold))
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

    private var cleanViewPresetRow: some View {
        Button {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            // Toggle binaire : si déjà épuré, on remet tout. Sinon on épure.
            let isCurrentlyClean = !showVilloStations && !showEventImpacts
            withAnimation(.easeOut(duration: 0.2)) {
                if isCurrentlyClean {
                    showVilloStations = true
                    showEventImpacts = true
                } else {
                    showVilloStations = false
                    showEventImpacts = false
                }
            }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: "sparkles")
                    .font(.system(size: 14, weight: .heavy))
                    .foregroundStyle(DS.Color.accentForeground)
                    .frame(width: 40, height: 40)
                    .background(Circle().fill(DS.Color.accent))
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.14), lineWidth: 1))
                VStack(alignment: .leading, spacing: 1) {
                    Text("Vue épurée")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Text("Cache Villo + événements")
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMute)
                }
                Spacer()
                Image(systemName: (!showVilloStations && !showEventImpacts) ? "checkmark.circle.fill" : "arrow.right.circle")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle((!showVilloStations && !showEventImpacts) ? DS.Color.statusOK : DS.Color.ink.opacity(0.4))
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(DS.Color.paper2.opacity(0.6))
        }
        .buttonStyle(.plain)
    }

    private func operatorDisabledRow(asset: String, title: String) -> some View {
        rowBody(
            leading: operatorLogo(asset, active: false),
            title: title,
            titleColor: DS.Color.inkMute,
            trailing: AnyView(
                Text("BIENTÔT")
                    .font(DS.Font.monoSmall.weight(.bold))
                    .tracking(1)
                    .foregroundStyle(DS.Color.inkMute)
            )
        )
        .opacity(0.7)
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
