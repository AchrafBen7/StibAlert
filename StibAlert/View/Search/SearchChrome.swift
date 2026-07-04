import SwiftUI

struct SearchTopBar: View {
    @Binding var query: String
    let destination: SearchPlace?
    let isExpanded: Bool
    let onOpenMenu: () -> Void
    let onOpenSearch: () -> Void
    let onCloseSearch: () -> Void

    var body: some View {
        HStack {
            Button(action: onOpenMenu) {
                SearchIconButton(icon: "line.3.horizontal")
            }
            .buttonStyle(.plain)
            .accessibilityLabel(L10n.Common.openSettings)
            .accessibilityHint(L10n.Common.openSettings)

            Spacer()

            if isExpanded {
                HStack(spacing: 10) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)

                    TextField("", text: $query, prompt: Text(destination?.name ?? L10n.Routing.searchDestination).foregroundStyle(Color.white.opacity(0.72)))
                        .font(AppTheme.Fonts.body(15, weight: .semibold))
                        .foregroundStyle(.white)
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()

                    Button(action: onCloseSearch) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.82))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.Common.close)
                    .accessibilityHint(L10n.Common.close)
                }
                .padding(.horizontal, 14)
                .frame(width: 244, height: 40)
                .background(DesignSystem.Colors.background)
                .clipShape(Capsule())
                .transition(.move(edge: .trailing).combined(with: .opacity))
            } else {
                Button(action: onOpenSearch) {
                    SearchIconButton(icon: "magnifyingglass")
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Routing.searchDestination)
                .accessibilityHint(L10n.Routing.searchDestination)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.28, dampingFraction: 0.88), value: isExpanded)
    }
}

struct SearchIconButton: View {
    let icon: String

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(DesignSystem.Colors.background)
                .frame(width: 42, height: 40)

            Image(systemName: icon)
                .font(.system(size: 24, weight: .regular))
                .foregroundStyle(.white)
        }
    }
}

struct SearchDestinationSheet: View {
    let title: String
    @Binding var query: String
    let selectedField: SearchField
    let suggestions: [SearchPlaceSuggestion]
    let places: [SearchPlace]
    let isResolvingSuggestion: Bool
    let locationDenied: Bool
    let onUseCurrentLocation: () -> Void
    let onSelectSuggestion: (SearchPlaceSuggestion) -> Void
    let onSelect: (SearchPlace) -> Void
    // Découverte (champ vide) : récents + Domicile/Travail — style Google Maps.
    var recents: [SearchPlace] = []
    var home: SearchPlace?
    var work: SearchPlace?
    var onTapHome: () -> Void = {}
    var onTapWork: () -> Void = {}
    var onClearRecents: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Capsule()
                .fill(Color.white.opacity(0.18))
                .frame(width: 42, height: 5)
                .frame(maxWidth: .infinity)

            Text(title)
                .font(AppTheme.Fonts.clash(18))
                .foregroundStyle(DesignSystem.Colors.primaryText)

            if selectedField == .origin {
                Button(action: onUseCurrentLocation) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 15, style: .continuous)
                            .fill(DesignSystem.Colors.success.opacity(0.14))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: "location.fill")
                                    .font(.system(size: 18, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.success)
                            )

                        VStack(alignment: .leading, spacing: 4) {
                            Text(L10n.Routing.useCurrentPosition)
                                .font(DesignSystem.Typography.bodySemibold)
                                .foregroundStyle(DesignSystem.Colors.primaryText)

                            Text(locationDenied ? L10n.Routing.locationAccessDenied : L10n.Routing.useCurrentPositionHint)
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .multilineTextAlignment(.leading)
                        }

                        Spacer()
                    }
                    .padding(14)
                    .background(
                        LinearGradient(
                            colors: [DesignSystem.Colors.accentSoft, Color.white],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 22, style: .continuous)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Routing.useCurrentPosition)
                .accessibilityHint(L10n.Routing.useCurrentPositionHint)
            }

            HStack(spacing: 12) {
                Image(systemName: selectedField == .origin ? "location.fill" : "magnifyingglass")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DesignSystem.Colors.secondaryText)

                TextField(
                    selectedField == .origin ? L10n.Routing.searchDeparture : L10n.Routing.searchDestination,
                    text: $query
                )
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DesignSystem.Colors.primaryText)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
            }
            .padding(.horizontal, 16)
            .frame(height: 54)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))

            ScrollView(showsIndicators: false) {
                VStack(spacing: 10) {
                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 10) {
                            Text(L10n.Routing.suggestions)
                                .font(DesignSystem.Typography.labelSemibold)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .frame(maxWidth: .infinity, alignment: .leading)

                            ForEach(suggestions) { suggestion in
                                Button {
                                    onSelectSuggestion(suggestion)
                                } label: {
                                    HStack(spacing: 14) {
                                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                                            .fill(DesignSystem.Colors.accent.opacity(0.10))
                                            .frame(width: 46, height: 46)
                                            .overlay(
                                                Image(systemName: "sparkle.magnifyingglass")
                                                    .font(.system(size: 18, weight: .semibold))
                                                    .foregroundStyle(DesignSystem.Colors.accent)
                                            )

                                        VStack(alignment: .leading, spacing: 4) {
                                            Text(suggestion.title)
                                                .font(DesignSystem.Typography.bodySemibold)
                                                .foregroundStyle(DesignSystem.Colors.primaryText)

                                            Text(suggestion.subtitle)
                                                .font(DesignSystem.Typography.description)
                                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                                .multilineTextAlignment(.leading)
                                        }

                                        Spacer()

                                        if isResolvingSuggestion {
                                            ProgressView()
                                                .controlSize(.small)
                                        }
                                    }
                                    .padding(14)
                                    .background(DesignSystem.Colors.cardBackground)
                                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                                    )
                                }
                                .buttonStyle(.plain)
                                .accessibilityLabel(L10n.Routing.suggestionLabel(suggestion.title))
                                .accessibilityHint(L10n.Routing.suggestions)
                            }
                        }
                    }

                    if suggestions.isEmpty {
                        if selectedField == .destination {
                            homeWorkRow
                        }
                        if !recents.isEmpty {
                            recentsSection
                        }
                    }

                    if !places.isEmpty {
                        Text(L10n.Routing.brussels)
                            .font(DesignSystem.Typography.labelSemibold)
                            .foregroundStyle(DesignSystem.Colors.secondaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.top, suggestions.isEmpty ? 0 : 4)
                    }

                    ForEach(places) { place in
                        Button {
                            onSelect(place)
                        } label: {
                            HStack(spacing: 14) {
                                RoundedRectangle(cornerRadius: 14, style: .continuous)
                                    .fill(DesignSystem.Colors.accentSoft)
                                    .frame(width: 46, height: 46)
                                    .overlay(
                                        Image(systemName: place.id == SearchLocationManager.currentLocationID ? "location.fill" : "mappin.and.ellipse")
                                            .font(.system(size: 18, weight: .semibold))
                                            .foregroundStyle(DesignSystem.Colors.accent)
                                    )

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(place.name)
                                        .font(DesignSystem.Typography.bodySemibold)
                                        .foregroundStyle(DesignSystem.Colors.primaryText)

                                    Text(place.subtitle)
                                        .font(DesignSystem.Typography.description)
                                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                                        .multilineTextAlignment(.leading)
                                }

                                Spacer()
                            }
                            .padding(14)
                            .background(DesignSystem.Colors.cardBackground)
                            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 20, style: .continuous)
                                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(place.id == SearchLocationManager.currentLocationID ? L10n.Routing.currentLocationPlace : L10n.Routing.placeLabel(place.name))
                        .accessibilityHint(L10n.Routing.searchDestination)
                    }
                }
                .padding(.bottom, 4)
            }
            .frame(maxHeight: 300)
        }
        .padding(18)
        .background(Color.white)
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.black.opacity(0.06), lineWidth: 1)
        )
    }

    // MARK: - Découverte (champ vide) — style Google Maps

    private var homeWorkRow: some View {
        HStack(spacing: 12) {
            quickChip(place: home, filledIcon: "house.fill", label: "Domicile", onTap: onTapHome)
            quickChip(place: work, filledIcon: "briefcase.fill", label: "Travail", onTap: onTapWork)
        }
    }

    private func quickChip(place: SearchPlace?, filledIcon: String, label: String, onTap: @escaping () -> Void) -> some View {
        Button(action: onTap) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(DesignSystem.Colors.accentSoft)
                    .frame(width: 38, height: 38)
                    .overlay(
                        Image(systemName: place == nil ? "plus" : filledIcon)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(DesignSystem.Colors.accent)
                    )
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(DesignSystem.Typography.bodySemibold)
                        .foregroundStyle(DesignSystem.Colors.primaryText)
                    Text(place?.name ?? "Ajouter")
                        .font(DesignSystem.Typography.description)
                        .foregroundStyle(DesignSystem.Colors.secondaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity)
            .background(DesignSystem.Colors.cardBackground)
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(DesignSystem.Colors.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(label) : \(place?.name ?? "non défini")")
    }

    private var recentsSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Récent")
                    .font(DesignSystem.Typography.labelSemibold)
                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                Spacer()
                Button(action: onClearRecents) {
                    Text("Effacer")
                        .font(DesignSystem.Typography.labelSemibold)
                        .foregroundStyle(DesignSystem.Colors.accent)
                }
                .buttonStyle(.plain)
            }

            ForEach(recents) { place in
                Button {
                    onSelect(place)
                } label: {
                    HStack(spacing: 14) {
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .fill(DesignSystem.Colors.background.opacity(0.5))
                            .frame(width: 46, height: 46)
                            .overlay(
                                Image(systemName: "clock.arrow.circlepath")
                                    .font(.system(size: 17, weight: .semibold))
                                    .foregroundStyle(DesignSystem.Colors.secondaryText)
                            )
                        VStack(alignment: .leading, spacing: 4) {
                            Text(place.name)
                                .font(DesignSystem.Typography.bodySemibold)
                                .foregroundStyle(DesignSystem.Colors.primaryText)
                                .lineLimit(1)
                            Text(place.subtitle)
                                .font(DesignSystem.Typography.description)
                                .foregroundStyle(DesignSystem.Colors.secondaryText)
                                .lineLimit(1)
                        }
                        Spacer()
                    }
                    .padding(14)
                    .background(DesignSystem.Colors.cardBackground)
                    .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20, style: .continuous)
                            .stroke(DesignSystem.Colors.border, lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
                .accessibilityLabel(L10n.Routing.placeLabel(place.name))
            }
        }
    }
}
