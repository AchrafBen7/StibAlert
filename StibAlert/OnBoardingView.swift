import SwiftUI

// MARK: - Entry point

/// Onboarding en 2 écrans : lignes → notifications.
///
/// L'écran « routine » (heure de départ habituelle) a été retiré : il réclamait
/// un réglage précis avant que l'usager ait seulement vu la carte. Il se
/// configure désormais dans Profil → Mon trajet quotidien, quand on sait à quoi
/// il sert.
///
/// Un 4ᵉ écran (« Choisis tes arrêts favoris ») ouvrait autrefois le parcours. Il a
/// été retiré : il exigeait la localisation dès la première seconde, et sans elle il
/// affichait « Aucun arrêt STIB à proximité » — un mensonge, puisque la vraie raison
/// était qu'on ignorait où se trouvait l'usager. Les arrêts favoris s'ajoutent depuis
/// l'onglet Favoris, quand l'usager sait déjà à quoi ils servent. La permission de
/// localisation est demandée par `HomeLocationManager` à l'ouverture de la carte.
struct OnboardingView: View {
    @State private var step: OnboardingStep = .lines
    @State private var savedLines: [String] = []
    var onFinish: () -> Void = {}

    var body: some View {
        ZStack {
            DS.Color.background.ignoresSafeArea()
            switch step {
            case .lines:
                OnboardingLinesStep(
                    onContinue: { lines in
                        savedLines = lines
                        step = .push
                    },
                    onSkip: onFinish
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            case .push:
                OnboardingPushStep(
                    primaryLine: savedLines.first ?? "92",
                    onFinish: onFinish
                )
                .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
            }
        }
        .animation(.spring(response: 0.38, dampingFraction: 0.88), value: step)
    }

    /// L'étape « routine » (heure de départ habituelle + point de départ) a été
    /// RETIRÉE du parcours : elle demandait un réglage précis avant même que
    /// l'utilisateur ait vu la carte, pour un bénéfice invisible à ce moment-là.
    /// La fonctionnalité, elle, reste entière : elle se configure dans
    /// Profil → Mon trajet quotidien. `OnboardingRoutineStep` n'est plus
    /// instanciée mais reste dans le dépôt, prête à être réutilisée là-bas.
    private enum OnboardingStep { case lines, push }
}

// MARK: - Step 1 — Lignes

private struct OnboardingLinesStep: View {
    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = AppTheme.ButtonHeight.primary

    @State private var selectedOperator: TransitOperator = .stib
    @State private var selectedLines: Set<String> = Set(OnboardingPreferenceStore.load().favoriteLines.map(Self.normalizedStoredLine))
    @State private var stibLines: [String] = [
        "1","2","3","4","5","6","7","8","9","10","12","19","25","38","46","47","53","55","56","58","59","71","81","92","95"
    ]
    @State private var delijnLines: [OperatorLine] = []
    @State private var tecLines: [OperatorLine] = []
    @State private var isLoadingStib = false
    @State private var isLoadingDelijn = false
    @State private var isLoadingTec = false

    let onContinue: ([String]) -> Void
    let onSkip: () -> Void

    private let maxSelection = 6
    private var canContinue: Bool { !selectedLines.isEmpty }
    private var sortedSelectedLines: [String] { selectedLines.sorted(by: Self.storedLineSort) }

    private var activeCandidates: [OnboardingLineCandidate] {
        switch selectedOperator {
        case .stib:
            return stibLines.map {
                OnboardingLineCandidate(
                    storageKey: $0,
                    displayCode: $0,
                    title: "Ligne \($0)",
                    subtitle: Self.modeLabel(for: $0),
                    operatorType: .stib,
                    colorHex: nil,
                    textHex: nil
                )
            }
        case .sncb:
            return Self.sncbCandidates
        case .delijn:
            return Self.dedupedByCode(delijnLines).map {
                OnboardingLineCandidate(
                    storageKey: "DELIJN:\($0.shortName)",
                    displayCode: $0.shortName,
                    title: $0.longName.isEmpty ? "Ligne \($0.shortName)" : $0.longName,
                    subtitle: $0.modeLabel,
                    operatorType: .delijn,
                    colorHex: $0.color,
                    textHex: $0.textColor
                )
            }
        case .tec:
            return Self.dedupedByCode(tecLines).map {
                OnboardingLineCandidate(
                    storageKey: "TEC:\($0.shortName)",
                    displayCode: $0.shortName,
                    title: $0.longName.isEmpty ? "Ligne \($0.shortName)" : $0.longName,
                    subtitle: $0.modeLabel,
                    operatorType: .tec,
                    colorHex: $0.color,
                    textHex: $0.textColor
                )
            }
        }
    }

    private var isLoadingActiveOperator: Bool {
        switch selectedOperator {
        case .stib: return isLoadingStib
        case .sncb: return false
        case .delijn: return isLoadingDelijn
        case .tec: return isLoadingTec
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    OnboardingLinesHeader()
                    OnboardingSelectedLinesCard(
                        selectedLines: sortedSelectedLines,
                        maxSelection: maxSelection,
                        onRemove: removeLine
                    )
                    TransitOperatorRow(
                        activeOperator: selectedOperator,
                        enabledOperators: [.stib, .sncb, .delijn, .tec],
                        onSelect: { selectedOperator = $0 }
                    )
                    OnboardingLinePickerCard(
                        operatorType: selectedOperator,
                        lines: activeCandidates,
                        selectedLines: selectedLines,
                        maxSelection: maxSelection,
                        isLoading: isLoadingActiveOperator,
                        onToggle: toggleLine
                    )
                }
                .padding(.horizontal, 22)
                .padding(.top, 56)
                .padding(.bottom, 154)
            }

            // 18 pt entre le bouton principal et « Je découvre d'abord » : à 10
            // le lien semblait collé au bouton et se lisait comme sa légende
            // plutôt que comme une porte de sortie distincte.
            VStack(spacing: 18) {
                continueButton
                skipButton
            }
            .padding(.horizontal, 22)
            .padding(.top, 22)
            .padding(.bottom, 34)
            .background(
                LinearGradient(
                    colors: [DS.Color.background.opacity(0), DS.Color.background, DS.Color.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .ignoresSafeArea(edges: .bottom)
            )
        }
        .background(DS.Color.background)
        .task { await loadLines() }
    }

    private var continueButton: some View {
        Button {
            saveLines()
            AppHaptics.success()
            onContinue(sortedSelectedLines)
        } label: {
            HStack(spacing: 10) {
                Text(canContinue
                     ? AppLocalizer.format("plural.continue_with_lines", defaultValue: "Continuer avec %lld lignes", selectedLines.count)
                     : AppLocalizer.string("onboarding.pick_one_line", defaultValue: "Choisis au moins une ligne"))
                Image(systemName: "arrow.right")
            }
            .font(DesignSystem.Typography.bodyStrong)
            .foregroundStyle(DS.Color.primaryForeground)
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(canContinue ? DS.Color.primary : DS.Color.ink.opacity(0.16))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(canContinue ? 0.95 : 0.18), lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canContinue)
    }

    private var skipButton: some View {
        Button {
            saveLines()
            onSkip()
        } label: {
            Text("Je découvre d'abord")
                .font(DS.Font.label)
                .tracking(1.4)
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func toggleLine(_ candidate: OnboardingLineCandidate) {
        if selectedLines.contains(candidate.storageKey) {
            selectedLines.remove(candidate.storageKey)
        } else if selectedLines.count < maxSelection {
            selectedLines.insert(candidate.storageKey)
        }
        AppHaptics.soft()
    }

    private func removeLine(_ line: String) {
        selectedLines.remove(line)
        AppHaptics.soft()
    }

    private func saveLines() {
        let existing = OnboardingPreferenceStore.load()
        OnboardingPreferenceStore.save(OnboardingPreferences(
            favoriteLines: sortedSelectedLines,
            stibFavoriteStopIds: existing.stibFavoriteStopIds,
            homeLabel: existing.homeLabel,
            departureTime: existing.departureTime
        ))
    }

    private static func normalizedStoredLine(_ rawValue: String) -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }
        if trimmed.contains(":") {
            let parts = trimmed.split(separator: ":", maxSplits: 1).map(String.init)
            guard parts.count == 2 else { return trimmed.uppercased() }
            return "\(parts[0].uppercased()):\(parts[1].trimmingCharacters(in: .whitespacesAndNewlines).uppercased())"
        }
        return trimmed.uppercased().replacingOccurrences(of: "BUS", with: "").trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func storedLineSort(_ lhs: String, _ rhs: String) -> Bool {
        let lhsOp = operatorPrefix(for: lhs).rawValue
        let rhsOp = operatorPrefix(for: rhs).rawValue
        if lhsOp != rhsOp { return lhsOp < rhsOp }
        let left = Int(displayCode(for: lhs).filter(\.isNumber)) ?? 999
        let right = Int(displayCode(for: rhs).filter(\.isNumber)) ?? 999
        if left == right { return lhs < rhs }
        return left < right
    }

    static func operatorPrefix(for storedLine: String) -> TransitOperator {
        let prefix = storedLine.split(separator: ":", maxSplits: 1).first.map(String.init)?.lowercased()
        switch prefix {
        case "delijn": return .delijn
        case "sncb": return .sncb
        case "tec": return .tec
        default: return .stib
        }
    }

    static func displayCode(for storedLine: String) -> String {
        if storedLine.contains(":") {
            return storedLine.split(separator: ":", maxSplits: 1).dropFirst().first.map(String.init) ?? storedLine
        }
        return storedLine
    }

    @MainActor
    private func loadLines() async {
        async let stib: () = loadStibLines()
        async let delijn: () = loadOperatorLines(.delijn)
        async let tec: () = loadOperatorLines(.tec)
        _ = await (stib, delijn, tec)
    }

    @MainActor
    private func loadStibLines() async {
        guard AppConfig.isBackendEnabled else { return }
        isLoadingStib = true
        defer { isLoadingStib = false }
        do {
            let lignes = try await LigneService.etatLignes()
            // On réduit chaque ligne à son shortCode (ex: "10:City"/"10:Suburb"
            // → "10") et on déduplique : avant, les variantes City/Suburb
            // s'affichaient en doublons "10:CITY" / "10:SUBURB", moches. Le
            // shortCode permet aussi d'appliquer la vraie couleur de ligne.
            let ids = lignes
                .map { LineStatusGrid.shortCode(from: $0.lineid) }
                .filter { !$0.isEmpty }
            let uniqueIds = Array(Set(ids)).sorted { (Int($0) ?? 999) < (Int($1) ?? 999) }
            if !uniqueIds.isEmpty {
                stibLines = uniqueIds
            }
        } catch {
            ErrorReporting.capture(error, tag: "onboarding.lignes")
        }
    }

    @MainActor
    private func loadOperatorLines(_ op: TransitOperator) async {
        guard op == .delijn || op == .tec else { return }
        if op == .delijn { isLoadingDelijn = true } else { isLoadingTec = true }
        defer {
            if op == .delijn { isLoadingDelijn = false } else { isLoadingTec = false }
        }
        let lines = await OperatorCatalogService.lines(operator: op)
            .sorted { $0.shortName.compare($1.shortName, options: .numeric) == .orderedAscending }
        if op == .delijn { delijnLines = lines } else { tecLines = lines }
    }

    private static func modeLabel(for line: String) -> String {
        let tram = AppLocalizer.string("mode.tram", defaultValue: "Tram")
        let bus = AppLocalizer.string("mode.bus", defaultValue: "Bus")
        guard let number = Int(line.filter(\.isNumber)) else { return tram }
        if (1...6).contains(number) { return AppLocalizer.string("mode.metro", defaultValue: "Métro") }
        if number >= 12 && number < 20 { return bus }
        if number >= 90 { return tram }
        return number >= 50 ? bus : tram
    }

    /// Une seule entrée par NUMÉRO de ligne.
    ///
    /// De Lijn et le TEC réutilisent les mêmes numéros d'une région à l'autre
    /// (un bus « 1 » à Anvers et un autre à Gand). Or l'identité d'une carte est
    /// `"DELIJN:\(shortName)"` : deux éléments partageaient donc le même `id`
    /// dans le `ForEach`, et SwiftUI les plaçait n'importe où — d'où les trous
    /// en escalier dans la grille. On garde la première occurrence de chaque
    /// numéro, ce qui correspond d'ailleurs au choix de l'utilisateur : il
    /// sélectionne « la ligne 7 », pas « la ligne 7 de telle ville ».
    private static func dedupedByCode(_ lines: [OperatorLine]) -> [OperatorLine] {
        var seen = Set<String>()
        return lines.filter { line in
            let key = line.shortName.trimmingCharacters(in: .whitespaces).uppercased()
            guard !key.isEmpty else { return false }
            return seen.insert(key).inserted
        }
    }

    /// Sous-titre SNCB : le TYPE de train, pas « SNCB · Bruxelles » répété
    /// treize fois. C'est la seule distinction utile au moment de choisir, et
    /// elle est exacte — on n'invente pas de destinations qu'on n'a pas.
    private static func sncbSubtitle(for code: String) -> String {
        if code.hasPrefix("S") { return AppLocalizer.string("sncb.kind.s", defaultValue: "Réseau S") }
        switch code {
        case "IC": return AppLocalizer.string("sncb.kind.ic", defaultValue: "InterCity")
        case "L":  return AppLocalizer.string("sncb.kind.l", defaultValue: "Omnibus")
        case "P":  return AppLocalizer.string("sncb.kind.p", defaultValue: "Heure de pointe")
        default:   return AppLocalizer.string("sncb.kind.train", defaultValue: "Train")
        }
    }

    private static let sncbCandidates: [OnboardingLineCandidate] = [
        "S1", "S2", "S3", "S4", "S5", "S6", "S7", "S8", "S9", "S10", "IC", "L", "P"
    ].map {
        OnboardingLineCandidate(
            storageKey: "SNCB:\($0)",
            displayCode: $0,
            title: $0.hasPrefix("S") ? "Train suburbain \($0)" : "Train \($0)",
            subtitle: sncbSubtitle(for: $0),
            operatorType: .sncb,
            colorHex: nil,
            textHex: nil
        )
    }
}

private struct OnboardingLineCandidate: Identifiable, Hashable {
    let storageKey: String
    let displayCode: String
    let title: String
    let subtitle: String
    let operatorType: TransitOperator
    let colorHex: String?
    let textHex: String?

    var id: String { storageKey }
}

private struct OnboardingLinesHeader: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("ÉTAPE 1 / 2")
                    .font(DS.Font.label)
                    .tracking(2.4)
                    .foregroundStyle(DS.Color.inkMute)

                Spacer()

                Text("BRUXELLES")
                    .font(DS.Font.labelSmall)
                    .tracking(2)
                    .foregroundStyle(DS.Color.inkMute)
            }

            // Paragraphe d'introduction SUPPRIMÉ. L'écran répétait trois fois la
            // même consigne (« choisis tes lignes »), et celui-ci se contredisait
            // avec le reste : il annonçait « jusqu'à 4 lignes » alors que
            // `maxSelection` vaut 6 et que la carte juste en dessous affiche
            // « 0/6 ». Restent le titre, puis la carte qui explique le bénéfice
            // (« des alertes utiles, pas du bruit ») et la consigne d'action au
            // dessus de la grille : une idée par bloc, aucune redite.
            Text("Tes lignes importantes.")
                .font(DesignSystem.Typography.display)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

private struct OnboardingSelectedLinesCard: View {
    let selectedLines: [String]
    let maxSelection: Int
    let onRemove: (String) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Réseau personnel")
                        .font(DS.Font.labelSmall)
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DS.Color.inkMute)

                    Text("\(selectedLines.count)/\(maxSelection) lignes")
                        .font(DesignSystem.Typography.title3)
                        .foregroundStyle(DS.Color.ink)
                }

                Spacer()

                Image(systemName: selectedLines.isEmpty ? "plus" : "checkmark")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(selectedLines.isEmpty ? DS.Color.inkMute : DS.Color.primary)
            }

            if selectedLines.isEmpty {
                Text("Ajoute tes lignes habituelles pour recevoir des alertes utiles, pas du bruit.")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 92), spacing: 10)], spacing: 10) {
                    ForEach(selectedLines, id: \.self) { line in
                        Button {
                            onRemove(line)
                        } label: {
                            HStack(spacing: 8) {
                                OnboardingStoredLineBadge(storedLine: line, size: 34)
                                Image(systemName: "xmark")
                                    .font(.system(size: 10, weight: .black))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            .padding(.trailing, 10)
                            .background(DS.Color.paper2)
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                            .overlay(
                                RoundedRectangle(cornerRadius: 12, style: .continuous)
                                    .stroke(DS.Color.border, lineWidth: 1)
                            )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Retirer la ligne \(line)")
                    }
                }
            }
        }
        .padding(18)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
        .shadow(color: DS.Color.ink.opacity(0.06), radius: 24, x: 0, y: 14)
    }
}

private struct OnboardingLinePickerCard: View {
    let operatorType: TransitOperator
    let lines: [OnboardingLineCandidate]
    let selectedLines: Set<String>
    let maxSelection: Int
    let isLoading: Bool
    let onToggle: (OnboardingLineCandidate) -> Void

    private var columns: [GridItem] {
        [GridItem(.adaptive(minimum: 72), spacing: 10)]
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Toutes les lignes \(operatorType.mapLabel)")
                        .font(DS.Font.labelSmall)
                        .tracking(1.8)
                        .textCase(.uppercase)
                        .foregroundStyle(DS.Color.inkMute)

                    Text("Appuie sur les lignes que tu prends vraiment.")
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(DS.Color.inkSoft)
                }

                Spacer()

                if isLoading {
                    ProgressView()
                        .tint(DS.Color.primary)
                }
            }

            if !isLoading && lines.isEmpty {
                Text("Aucune ligne \(operatorType.mapLabel) disponible pour le moment.")
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkMute)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.vertical, 18)
            } else {
                LazyVGrid(columns: columns, spacing: 10) {
                    ForEach(lines) { line in
                        OnboardingLineButton(
                            candidate: line,
                            isSelected: selectedLines.contains(line.storageKey),
                            isDisabled: !selectedLines.contains(line.storageKey) && selectedLines.count >= maxSelection,
                            onTap: { onToggle(line) }
                        )
                    }
                }
            }
        }
        .padding(18)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.Color.border, lineWidth: 1)
        )
    }
}

private struct OnboardingLineButton: View {
    let candidate: OnboardingLineCandidate
    let isSelected: Bool
    let isDisabled: Bool
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(spacing: 8) {
                OnboardingOperatorLineBadge(candidate: candidate, size: 42)
                    .opacity(isDisabled ? 0.32 : 1)

                // Le libellé « Métro / Tram / Bus » sous CHAQUE pastille
                // n'apprenait rien : la forme et la couleur du badge disent déjà
                // le mode, et répété quarante fois il transformait la grille en
                // mur de texte. On ne le garde que pour la SNCB, où il porte une
                // vraie distinction (Réseau S, InterCity, Omnibus, Heure de
                // pointe) impossible à deviner autrement.
                if candidate.operatorType == .sncb {
                    Text(candidate.subtitle)
                        .font(DS.Font.labelSmall)
                        .tracking(0.8)
                        .foregroundStyle(isSelected ? DS.Color.primary : DS.Color.inkMute)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: candidate.operatorType == .sncb ? 78 : 62)
            // Aucun cadre quand la ligne n'est PAS choisie : les pastilles sont
            // déjà des formes colorées, les encadrer toutes créait une grille de
            // boîtes grises qui écrasait les couleurs des lignes. La sélection,
            // elle, reste franche (fond teinté + contour épais), donc lisible
            // d'un coup d'œil au milieu des non-sélectionnées.
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(isSelected ? DS.Color.primary.opacity(0.12) : Color.clear)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(isSelected ? DS.Color.primary : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .accessibilityLabel("Ligne \(candidate.displayCode)")
        .accessibilityValue(isSelected ? "Sélectionnée" : "Non sélectionnée")
    }
}

private struct OnboardingOperatorLineBadge: View {
    let candidate: OnboardingLineCandidate
    let size: CGFloat

    var body: some View {
        Text(candidate.displayCode)
            .font(.system(size: size * 0.38, weight: .black, design: .rounded))
            .minimumScaleFactor(0.62)
            .foregroundStyle(textColor)
            .lineLimit(1)
            .frame(minWidth: size, minHeight: size)
            .padding(.horizontal, candidate.displayCode.count > 3 ? 6 : 0)
            .background(backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
            )
    }

    private var backgroundColor: Color {
        if let colorHex = candidate.colorHex?.trimmingCharacters(in: .whitespacesAndNewlines),
           !colorHex.isEmpty,
           colorHex.uppercased() != "FFFFFF" {
            return Color(hex: colorHex.hasPrefix("#") ? colorHex : "#\(colorHex)")
        }
        // STIB : vraie couleur OFFICIELLE par ligne (comme la page horaires)
        // au lieu d'une couleur de marque générique bleue pour toutes les lignes.
        if candidate.operatorType == .stib {
            return TransitLinePalette.fill(for: candidate.displayCode)
        }
        return candidate.operatorType.brandColor
    }

    private var textColor: Color {
        if let textHex = candidate.textHex?.trimmingCharacters(in: .whitespacesAndNewlines),
           !textHex.isEmpty {
            return Color(hex: textHex.hasPrefix("#") ? textHex : "#\(textHex)")
        }
        if candidate.operatorType == .stib {
            return TransitLinePalette.foreground(for: candidate.displayCode)
        }
        return candidate.operatorType.brandTextColor
    }
}

private struct OnboardingStoredLineBadge: View {
    let storedLine: String
    let size: CGFloat

    var body: some View {
        OnboardingOperatorLineBadge(
            candidate: OnboardingLineCandidate(
                storageKey: storedLine,
                displayCode: OnboardingLinesStep.displayCode(for: storedLine),
                title: storedLine,
                subtitle: OnboardingLinesStep.operatorPrefix(for: storedLine).mapLabel,
                operatorType: OnboardingLinesStep.operatorPrefix(for: storedLine),
                colorHex: nil,
                textHex: nil
            ),
            size: size
        )
    }
}

// MARK: - Step 2 — Push permission

private struct OnboardingPushStep: View {
    let primaryLine: String
    let onFinish: () -> Void

    @ScaledMetric(relativeTo: .body) private var buttonHeight: CGFloat = AppTheme.ButtonHeight.primary
    @State private var selectedScenario = 0
    @State private var notifAppeared = false
    @State private var isRequesting = false

    private var primaryLineLabel: String {
        OnboardingLinesStep.displayCode(for: primaryLine)
    }

    // MARK: Scénarios

    private struct NotifScenario: Identifiable {
        let id: Int
        let tabIcon: String
        let tabLabel: String
        let badgeColor: Color
        let body: String
    }

    /// `tabLabel` et `body` sont des `String` affichées via `Text(variable)`, qui ne se
    /// localise jamais. Elles restaient donc en français dans l'app en néerlandais —
    /// juste sous un titre traduit, ce qui est pire que pas de traduction du tout.
    private var scenarios: [NotifScenario] {
        [
            NotifScenario(
                id: 0,
                tabIcon: "exclamationmark.triangle.fill",
                tabLabel: AppLocalizer.string("Alerte", defaultValue: "Alerte"),
                badgeColor: Color(hex: "#FF6B3D"),
                body: AppLocalizer.format("push.scenario.alert",
                                          defaultValue: "Incident à Ixelles · ligne %@ perturbée dès 8h40. Envisage un départ avant 8h25.",
                                          primaryLineLabel)
            ),
            NotifScenario(
                id: 1,
                tabIcon: "checkmark.circle.fill",
                tabLabel: AppLocalizer.string("Tout roule", defaultValue: "Tout roule"),
                badgeColor: Color(hex: "#73F0D2"),
                body: AppLocalizer.format("push.scenario.ok",
                                          defaultValue: "Ligne %@ · 8h07 · Trafic normal ce matin. Prochain départ dans 4 min.",
                                          primaryLineLabel)
            ),
            NotifScenario(
                id: 2,
                tabIcon: "clock.badge.fill",
                tabLabel: AppLocalizer.string("Retard", defaultValue: "Retard"),
                badgeColor: Color(hex: "#B5CFF8"),
                body: AppLocalizer.format("push.scenario.delay",
                                          defaultValue: "Ligne %@ retardée de 8 min. Prochain départ depuis ton arrêt dans 11 min.",
                                          primaryLineLabel)
            ),
        ]
    }

    // MARK: Trust signals

    /// `var` calculée, pas `let` : un `let` contenant `AppLocalizer` fige la langue au
    /// premier accès, et changer de langue dans Profil ne rafraîchirait plus rien.
    private var trustSignals: [(icon: String, text: String)] {
        [
            ("clock.badge.checkmark.fill", AppLocalizer.string("Seulement avant ton trajet, pas à 2h du matin",
                                                               defaultValue: "Seulement avant ton trajet, pas à 2h du matin")),
            ("bell.slash.fill",            AppLocalizer.string("Silence complet si ta ligne tourne normalement",
                                                               defaultValue: "Silence complet si ta ligne tourne normalement")),
            ("lock.shield.fill",           AppLocalizer.string("Données jamais partagées ni vendues",
                                                               defaultValue: "Données jamais partagées ni vendues")),
        ]
    }

    // MARK: Layout

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 22) {
                    pushHeader
                    notificationPreviewCard
                    trustSignalsCard
                }
                .padding(.horizontal, 22)
                .padding(.top, 44)
                // 150 pt ici étaient un reliquat d'une version où le CTA flottait en
                // ZStack. Dans ce VStack, il occupe déjà sa place : le padding ne
                // faisait que pousser la carte « Pourquoi l'activer » hors de l'écran.
                .padding(.bottom, 12)
            }
            // Le dégradé vivait DANS `ctaArea`, donc sous le ScrollView dans le VStack :
            // il fondait le fond sur le fond, et ne servait à rien. En overlay, il fond
            // le contenu qui défile — la carte tranchée devient un indice « ça continue ».
            .overlay(alignment: .bottom) {
                LinearGradient(
                    colors: [DS.Color.background.opacity(0), DS.Color.background],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: 28)
                .allowsHitTesting(false)
            }

            ctaArea
        }
        .background(DS.Color.background)
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.75).delay(0.15)) {
                notifAppeared = true
            }
        }
    }

    // MARK: Header

    private var pushHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("ÉTAPE 2 / 2")
                .font(DS.Font.label)
                .tracking(2)
                .foregroundStyle(DS.Color.inkMute)

            Text("Être prévenu avant d’attendre.")
                .font(DesignSystem.Typography.display)
                .foregroundStyle(DS.Color.ink)
                .fixedSize(horizontal: false, vertical: true)

            Text("Blayse t’envoie uniquement les alertes utiles sur tes lignes, tes gares et tes trajets importants.")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(DS.Color.inkSoft)
                .lineSpacing(3)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    // MARK: Notification preview

    private var notificationPreviewCard: some View {
        VStack(alignment: .leading, spacing: 0) {
            iOSNotifHeader

            Divider()
                .background(DS.Color.ink.opacity(0.08))

            notifBody
                .padding(16)
                .offset(y: notifAppeared ? 0 : 16)
                .opacity(notifAppeared ? 1 : 0)

            Divider()
                .background(DS.Color.ink.opacity(0.08))

            scenarioTabs
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
        }
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(color: DS.Color.ink.opacity(0.08), radius: 24, x: 0, y: 12)
    }

    private var iOSNotifHeader: some View {
        HStack(spacing: 8) {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(DS.Color.primary)
                .frame(width: 28, height: 28)
                .overlay(
                    Image(systemName: "bell.badge.fill")
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.primaryForeground)
                )

            Text("BLAYSE")
                .font(DS.Font.label)
                .tracking(1.6)
                .foregroundStyle(DS.Color.inkMute)

            Spacer()

            Text("maintenant")
                .font(DS.Font.labelSmall)
                .foregroundStyle(DS.Color.inkMute)

            Circle()
                .fill(scenarios[selectedScenario].badgeColor)
                .frame(width: 8, height: 8)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var notifBody: some View {
        let scenario = scenarios[selectedScenario]
        return HStack(alignment: .top, spacing: 12) {
            Image(systemName: scenario.tabIcon)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(scenario.badgeColor)
                .frame(width: 42, height: 42)
                .background(scenario.badgeColor.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            VStack(alignment: .leading, spacing: 4) {
                Text("Ligne \(primaryLineLabel) · Perturbation réseau")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)

                Text(scenario.body)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
                    .lineSpacing(2)
            }
        }
        .animation(.spring(response: 0.35, dampingFraction: 0.82), value: selectedScenario)
    }

    private var scenarioTabs: some View {
        HStack(spacing: 8) {
            ForEach(scenarios) { scenario in
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.84)) {
                        selectedScenario = scenario.id
                    }
                    AppHaptics.soft()
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: scenario.tabIcon)
                            .font(.system(size: 10, weight: .semibold))
                        // Le néerlandais est plus long : « Waarschuwing » passait à la
                        // ligne au milieu du mot. Une pastille ne se lit que d'un trait.
                        Text(scenario.tabLabel)
                            .font(DS.Font.bodySmall.weight(.bold))
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                    .foregroundStyle(selectedScenario == scenario.id ? DS.Color.primaryForeground : DS.Color.inkMute)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(
                        selectedScenario == scenario.id
                        ? DS.Color.primary
                        : DS.Color.paper2
                    )
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(selectedScenario == scenario.id ? 0 : 0.08), lineWidth: 1)
                    )
                }
                .buttonStyle(.plain)
            }
            Spacer()
        }
    }

    // MARK: Trust signals

    private var trustSignalsCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Pourquoi l’activer")
                .font(DS.Font.label)
                .tracking(1.8)
                .textCase(.uppercase)
                .foregroundStyle(DS.Color.inkMute)
                .padding(.horizontal, 16)
                .padding(.top, 16)

            ForEach(Array(trustSignals.enumerated()), id: \.offset) { index, signal in
                HStack(spacing: 14) {
                    Image(systemName: signal.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Color.primary)
                        .frame(width: 32, height: 32)
                        .background(DS.Color.primary.opacity(0.10))
                        .clipShape(Circle())

                    Text(signal.text)
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)

                    Spacer(minLength: 0)
                }
                .padding(.vertical, 10)
                .padding(.horizontal, 16)

                if index < trustSignals.count - 1 {
                    Divider()
                        .background(DS.Color.ink.opacity(0.08))
                        .padding(.leading, 62)
                }
            }
        }
        .padding(.bottom, 6)
        .background(DS.Color.paper)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 24, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
    }

    // MARK: CTA

    private var ctaArea: some View {
        VStack(spacing: 10) {
            authorizeButton
            dialogHint
            laterButton
        }
        .padding(.horizontal, 24)
        .padding(.top, 8)
        .padding(.bottom, 24)
        .background(DS.Color.background)
    }

    private var authorizeButton: some View {
        Button {
            isRequesting = true
            Task {
                await PushNotificationManager.current?.requestAuthorizationAndRegister()
                isRequesting = false
                onFinish()
            }
        } label: {
            ZStack {
                if isRequesting {
                    ProgressView().tint(.black)
                } else {
                    HStack(spacing: 10) {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 15, weight: .semibold))
                        Text("Autoriser les notifications")
                            .font(DesignSystem.Typography.bodyStrong)
                    }
                    .foregroundStyle(DS.Color.primaryForeground)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(height: buttonHeight)
            .background(DS.Color.primary)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.95), lineWidth: 1.4)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRequesting)
        .accessibilityLabel("Autoriser les notifications push")
        .accessibilityHint("Une fenêtre iOS va s'ouvrir pour confirmer")
    }

    private var dialogHint: some View {
        HStack(spacing: 5) {
            Image(systemName: "hand.tap.fill")
                .font(.system(size: 10))
                .foregroundStyle(DS.Color.inkMute)
            // Pas de monospace : elle est réservée aux données temps réel.
            Text("Une fenêtre iOS va s'ouvrir pour confirmer")
                .font(DS.Font.caption)
                .foregroundStyle(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity)
    }

    private var laterButton: some View {
        Button(action: onFinish) {
            Text("Plus tard")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(DS.Color.inkMute)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
    }
}
