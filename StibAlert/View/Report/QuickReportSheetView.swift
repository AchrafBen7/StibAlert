import SwiftUI
import CoreLocation
import UIKit

/// A selectable train at a gare for the SNCB report flow — sourced from live
/// (iRail) departures when available, else the static schedule.
struct SNCBTrainOption: Identifiable, Equatable {
    let id: String
    let line: String
    let destination: String
    let time: String
    let delayMinutes: Int
    let canceled: Bool
}

struct QuickReportSheetView: View {
    @Binding var isShowing: Bool
    let userLatitude: Double?
    let userLongitude: Double?
    let activeSignalements: [SignalementDTO]
    var onSubmitted: ((SignalementDTO) -> Void)? = nil

    @State private var selectedStop: NearbyStop? = nil
    @State private var selectedLine: NearbyIssueLine? = nil
    @State private var selectedProblem: ReportProblemType? = nil
    @State private var description: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submitError: String? = nil
    @State private var submitSuccess: Bool = false
    @State private var confirmingExistingId: String? = nil
    @State private var showConfetti: Bool = false
    /// Set once a report is successfully published online — drives the
    /// "avertir vos proches" share prompt before the sheet closes.
    @State private var createdSignalement: SignalementDTO? = nil
    @State private var nearbyStops: [NearbyStop] = []
    @State private var isLoadingStops = false
    @State private var isStopPickerExpanded = false
    @State private var stopSearchQuery = ""
    @State private var selectedOperator: TransitOperator = .stib
    @State private var sncbTrainOptions: [SNCBTrainOption] = []
    @State private var selectedSncbTrain: SNCBTrainOption? = nil
    @State private var isLoadingSncbTrains = false
    @FocusState private var focusedField: FocusedField?

    private enum FocusedField { case description }

    private var safeTop: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.top ?? 50
    }

    private var safeBottom: CGFloat {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.windows.first?.safeAreaInsets.bottom ?? 34
    }

    private var userCoordinate: CLLocationCoordinate2D? {
        guard let lat = userLatitude, let lng = userLongitude else { return nil }
        return CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }

    private var matchingActiveSignalements: [SignalementDTO] {
        guard let stop = selectedStop else { return [] }
        return activeSignalements.filter { s in
            guard s.status != "resolved" else { return false }
            if case .populated(let arret) = s.arretId, arret.nom == stop.name { return true }
            return false
        }
    }

    private var canSubmit: Bool {
        selectedStop != nil && selectedLine != nil && selectedProblem != nil && !isSubmitting && !submitSuccess
    }

    private var submitBottomPadding: CGFloat {
        safeBottom + 8
    }

    private var scrollBottomPadding: CGFloat {
        // Always leave enough room for the keyboard's safe-area inset
        // plus a little visual breathing space below the description field.
        focusedField == .description ? 128 : 20
    }

    private var filteredNearbyStops: [NearbyStop] {
        let trimmed = stopSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nearbyStops }
        return nearbyStops.filter {
            $0.name.localizedCaseInsensitiveContains(trimmed)
            || $0.issueLines.contains(where: { $0.number.localizedCaseInsensitiveContains(trimmed) })
            || $0.issueLines.contains(where: { $0.direction.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    var body: some View {
        ZStack(alignment: .bottom) {
            DS.Color.ink.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: handleClose)

            sheetContent
                .frame(maxWidth: .infinity)
                .background(
                    DS.Color.paper
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )

            if showConfetti {
                ConfettiBurst()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: bootstrap)
        .onChange(of: selectedOperator) { _, _ in
            resetTargetSelection()
            bootstrap()
        }
        .onChange(of: selectedStop?.id) { _, _ in
            Task { await loadSncbTrains() }
        }
        .sheet(item: $createdSignalement) { signalement in
            ReportSharePromptSheet(signalement: signalement) {
                createdSignalement = nil
                handleClose()
            }
        }
        // No manual keyboard observers — SwiftUI's safe area handles avoidance
        // for the bottom-anchored sheet (we don't .ignoresSafeArea(.keyboard)).
    }

    // MARK: - Sheet layout

    private var sheetContent: some View {
        VStack(spacing: 0) {
            handleBar

            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 20) {
                        sheetHeader
                        operatorSelectorSection
                        stopSection
                        if !isStopPickerExpanded {
                            if selectedOperator == .sncb, selectedStop != nil {
                                sncbTrainSection
                            } else if selectedOperator == .delijn || selectedOperator == .tec {
                                // De Lijn / TEC: report is stop-level (no local
                                // per-stop line list); the operator pseudo-line
                                // is selected under the hood.
                                EmptyView()
                            } else if let stop = selectedStop, !stop.issueLines.isEmpty {
                                lineChipsSection(stop)
                            }
                            if !matchingActiveSignalements.isEmpty {
                                activeHereSection
                            }
                            typeSection
                            if selectedProblem != nil {
                                optionalDescriptionField
                            }
                            if let submitError {
                                Text(submitError)
                                    .font(DS.Font.bodySmall)
                                    .foregroundStyle(DS.Color.statusMajor)
                                    .padding(.horizontal, 18)
                                    .id("submitError")
                            }
                        }
                        Spacer(minLength: 12)
                    }
                    .padding(.top, 4)
                    .padding(.bottom, scrollBottomPadding)
                }
                .scrollDismissesKeyboard(.interactively)
                .onChange(of: focusedField) { _, newValue in
                    guard newValue == .description else { return }
                    // Short delay — SwiftUI handles the keyboard avoidance
                    // natively now, we just need a frame for layout to settle.
                    scrollToDescription(proxy, delay: 0.05)
                }
                .onChange(of: selectedProblem) { _, newValue in
                    guard newValue != nil else { return }
                    scrollToDescription(proxy)
                }
            }
            // Let the scroll claim every remaining vertical pixel between
            // handleBar and submitBar — without this the VStack would
            // shrink-wrap and the sheet would look like "handle + submit only".
            .frame(maxHeight: .infinity)

            submitBar
        }
        // Cap to the usable height (status bar excluded). SwiftUI's automatic
        // keyboard avoidance will further shrink the available area when the
        // keyboard appears, so we don't subtract the keyboard manually.
        .frame(maxHeight: maxSheetHeight)
    }

    private var maxSheetHeight: CGFloat {
        UIScreen.main.bounds.height - safeTop - 24
    }

    // MARK: - Header

    private var sheetHeader: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Signaler un problème")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(DS.Color.ink)
            Text(selectedOperator == .sncb ? "Gare détectée automatiquement" : "Arrêt détecté automatiquement")
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.inkSoft)
        }
        .padding(.horizontal, 18)
    }

    private var operatorSelectorSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "square.grid.2x2.fill", text: "Réseau")
            TransitOperatorRow(
                activeOperator: selectedOperator,
                enabledOperators: [.stib, .sncb, .delijn, .tec],
                onSelect: { selectedOperator = $0 }
            )
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Handle bar

    private var handleBar: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(DS.Color.ink.opacity(0.35))
                .frame(width: 44, height: 5)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button(action: handleClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .frame(width: 30, height: 30)
                    .background(DS.Color.secondary)
                    .clipShape(Circle())
                    .overlay(Circle().stroke(DS.Color.ink.opacity(0.16), lineWidth: 1))
                    .padding(.trailing, 14)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Fermer")
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Stop section

    private var stopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                icon: selectedOperator == .sncb ? "train.side.front.car" : "mappin.and.ellipse",
                text: selectedOperator == .sncb ? "Gare" : "Arrêt"
            )

            if isLoadingStops {
                stopSkeleton
            } else if isStopPickerExpanded {
                stopPickerExpanded
            } else if let stop = selectedStop {
                stopCompactCard(stop)
            } else {
                Text(emptyTargetMessage)
                    .font(.system(size: 13))
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.horizontal, 18)
            }
        }
    }

    private var stopSkeleton: some View {
        HStack(spacing: 12) {
            RoundedRectangle(cornerRadius: 18)
                .fill(DS.Color.paper2)
                .frame(width: 36, height: 36)
            VStack(alignment: .leading, spacing: 6) {
                RoundedRectangle(cornerRadius: 3).fill(DS.Color.paper2).frame(width: 140, height: 12)
                RoundedRectangle(cornerRadius: 3).fill(DS.Color.paper2).frame(width: 80, height: 10)
            }
            Spacer()
        }
        .padding(14)
        .overlay(
            RoundedRectangle(cornerRadius: 16).stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
        )
        .padding(.horizontal, 18)
    }

    private func stopCompactCard(_ stop: NearbyStop) -> some View {
        HStack(spacing: 12) {
            targetIcon

            VStack(alignment: .leading, spacing: 2) {
                Text(stop.name)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(stopDistanceAndLineCountText(stop))
                    .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
            }

            Spacer()

            Button("Changer") {
                UIImpactFeedbackGenerator(style: .soft).impactOccurred()
                withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                    isStopPickerExpanded = true
                }
            }
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(DS.Color.community)
        }
        .padding(14)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Color.community.opacity(0.35), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
    }

    private var stopPickerExpanded: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text(selectedOperator == .sncb ? "Choisir une autre gare" : "Choisir un autre arrêt")
                    .font(.system(size: 14, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                        isStopPickerExpanded = false
                        stopSearchQuery = ""
                    }
                }) {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)
                        .frame(width: 28, height: 28)
                        .background(DS.Color.paper2)
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 18)

            stopSearchField

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(Array(filteredNearbyStops.prefix(8))) { stop in
                    stopCard(stop)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var stopSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)

            TextField(selectedOperator == .sncb ? "Rechercher une gare" : "Rechercher un arrêt ou une ligne", text: $stopSearchQuery)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !stopSearchQuery.isEmpty {
                Button { stopSearchQuery = "" } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(DS.Color.inkMute.opacity(0.7))
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(DS.Color.paper2.opacity(0.55))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(DS.Color.ink.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
    }

    private func stopCard(_ stop: NearbyStop) -> some View {
        let isSelected = selectedStop?.id == stop.id
        let primaryLine = stop.issueLines.first?.number ?? stop.lines.first?.number ?? "?"
        let direction = stop.issueLines.first?.direction ?? "Direction à confirmer"
        let borderColor = isSelected ? DS.Color.primary : DS.Color.ink.opacity(0.08)
        let selectedFill = LinearGradient(
            colors: [DS.Color.primary.opacity(0.16), DS.Color.statusMinor.opacity(0.10), DS.Color.paper],
            startPoint: .topLeading, endPoint: .bottomTrailing
        )

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedStop = stop
            selectedLine = stop.issueLines.first
            selectedProblem = nil
            description = ""
            withAnimation(.spring(response: 0.32, dampingFraction: 0.85)) {
                isStopPickerExpanded = false
                stopSearchQuery = ""
            }
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(stop.name.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                }

                HStack(spacing: 6) {
                    LineBadge(line: primaryLine, size: .sm)
                    ForEach(Array(stop.lines.dropFirst().prefix(2))) { line in
                        LineBadge(line: line.number, size: .sm)
                    }
                }
                .padding(.top, 11)

                Text(direction.uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(2)
                    .padding(.top, 10)

                Spacer(minLength: 8)

                Text(stopDistanceAndLineCountText(stop))
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Color.ink)
                    .padding(.top, 12)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 146, alignment: .topLeading)
            .background {
                if isSelected { selectedFill } else { DS.Color.paper }
            }
            .overlay(
                RoundedRectangle(cornerRadius: 20)
                    .stroke(borderColor, lineWidth: isSelected ? 1.8 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: DS.Color.primary.opacity(isSelected ? 0.14 : 0), radius: 14, x: 0, y: 6)
            .shadow(color: DS.Color.ink.opacity(isSelected ? 0.06 : 0.035), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    @ViewBuilder
    private var targetIcon: some View {
        if selectedOperator == .sncb {
            Image("operator-sncb")
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .frame(width: 36, height: 36)
                .background(DS.Color.paper2.opacity(0.65))
                .clipShape(Circle())
        } else {
            Image(systemName: "mappin.and.ellipse")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Color.community)
                .frame(width: 36, height: 36)
                .background(DS.Color.community.opacity(0.12))
                .clipShape(Circle())
        }
    }

    private var emptyTargetMessage: String {
        switch selectedOperator {
        case .stib:
            return "Aucun arrêt détecté à proximité."
        case .sncb:
            return "Aucune gare SNCB détectée à proximité."
        case .delijn, .tec:
            return "\(selectedOperator.shortName) n’est pas encore connecté aux arrêts proches."
        }
    }

    // MARK: - Line chips (inline horizontal)

    private func lineChipsSection(_ stop: NearbyStop) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "tram.fill", text: "Ligne concernée")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(stop.issueLines) { line in
                        lineChip(line)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private func lineChip(_ line: NearbyIssueLine) -> some View {
        let isSelected = selectedLine?.id == line.id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedLine = line
        } label: {
            HStack(spacing: 8) {
                LineBadge(line: line.number, size: .sm)
                Text(line.direction.uppercased())
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Color.paper)
                        .frame(width: 18, height: 18)
                        .background(DS.Color.ink)
                        .clipShape(Circle())
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(isSelected ? DS.Color.paper2 : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - SNCB train picker

    /// SNCB has no numbered lines like the STIB — so "Ligne concernée" becomes
    /// "Train concerné": the user picks the specific departure (e.g. the 16:26
    /// to Nivelles) from this gare. Optional — "Toute la gare" reports the gare
    /// in general. The chosen train is folded into the report description; the
    /// report's `ligne` stays "SNCB" so it keeps showing under the SNCB filter.
    private var sncbTrainSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "train.side.front.car", text: "Train concerné")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    allGareChip
                    if isLoadingSncbTrains && sncbTrainOptions.isEmpty {
                        ProgressView().tint(DS.Color.ink).padding(.horizontal, 8)
                    }
                    ForEach(sncbTrainOptions) { trainChip($0) }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var allGareChip: some View {
        let isSelected = selectedSncbTrain == nil
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedSncbTrain = nil
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "building.columns.fill")
                    .font(.system(size: 11, weight: .bold))
                Text("TOUTE LA GARE")
                    .font(.system(size: 10.5, weight: .bold))
            }
            .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(isSelected ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    private func trainChip(_ train: SNCBTrainOption) -> some View {
        let isSelected = selectedSncbTrain?.id == train.id
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedSncbTrain = isSelected ? nil : train
        } label: {
            HStack(spacing: 8) {
                Text(train.time)
                    .font(.system(size: 12, weight: .black, design: .monospaced))
                    .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
                if !train.line.isEmpty {
                    Text(train.line)
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .frame(height: 18)
                        .background(Color(hex: "#0055A4"))
                        .clipShape(Capsule())
                }
                Text("→ \(train.destination)")
                    .font(.system(size: 10.5, weight: .bold))
                    .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
                    .lineLimit(1)
                if train.canceled {
                    Text("SUPPR.")
                        .font(.system(size: 8, weight: .black))
                        .foregroundStyle(DS.Color.statusMajor)
                } else if train.delayMinutes > 0 {
                    Text("+\(train.delayMinutes)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(DS.Color.statusMinor)
                }
            }
            .padding(.horizontal, 12)
            .frame(height: 40)
            .background(isSelected ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Type grid

    private var typeSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "exclamationmark.triangle.fill", text: "Type de problème")

            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)],
                spacing: 10
            ) {
                ForEach(ReportProblemType.allCases) { type in
                    problemCard(type)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func problemCard(_ type: ReportProblemType) -> some View {
        let isSelected = selectedProblem == type
        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedProblem = type
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack {
                    Image(systemName: typeIcon(type))
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(type.accentColor)
                    Text(type.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                    Spacer()
                    Circle()
                        .fill(type.accentColor)
                        .frame(width: 9, height: 9)
                }
                Text(type.descriptionLines.first ?? "")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkSoft)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(isSelected ? type.backgroundColor : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? type.accentColor : DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func typeIcon(_ type: ReportProblemType) -> String {
        switch type {
        case .accident:   return "exclamationmark.triangle.fill"
        case .delay:      return "clock.fill"
        case .breakdown:  return "wrench.and.screwdriver.fill"
        case .incivility: return "person.2.slash.fill"
        case .cleanliness: return "sparkles"
        case .aggression: return "shield.lefthalf.filled"
        }
    }

    // MARK: - Already reported here

    private var activeHereSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(
                icon: "bubble.left.and.bubble.right.fill",
                text: "Déjà signalé ici (\(matchingActiveSignalements.count))"
            )
            VStack(spacing: 8) {
                ForEach(matchingActiveSignalements.prefix(3)) { signalement in
                    activeHereCard(signalement)
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func activeHereCard(_ signalement: SignalementDTO) -> some View {
        let confirmations = signalement.community?.confirmations ?? 0
        let isConfirming = confirmingExistingId == signalement.id
        return HStack(spacing: 10) {
            LineBadge(line: signalement.ligne, size: .sm)

            VStack(alignment: .leading, spacing: 2) {
                Text(signalement.typeProbleme)
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                HStack(spacing: 6) {
                    Text(relativeTime(from: signalement.dateSignalement))
                        .font(.system(size: 11.5))
                        .foregroundStyle(DS.Color.inkMute)
                    if confirmations > 0 {
                        Text(confirmationCountText(confirmations))
                            .font(.system(size: 11.5))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                }
            }

            Spacer()

            Button(action: { confirmExisting(signalement) }) {
                HStack(spacing: 4) {
                    if isConfirming {
                        ProgressView().tint(DS.Color.paper).scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark").font(.system(size: 11, weight: .semibold))
                    }
                    Text("Confirmer").font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(DS.Color.paper)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(DS.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(confirmingExistingId != nil)
        }
        .padding(10)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Optional description

    private var optionalDescriptionField: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Description optionnelle")
                .font(.system(size: 12.5, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 18)

            TextField("Ex : Tram bloqué depuis 5 min au feu.", text: $description, axis: .vertical)
                .focused($focusedField, equals: .description)
                .lineLimit(4...6)
                .padding(14)
                .frame(minHeight: 118, alignment: .topLeading)
                .background(DS.Color.paper2.opacity(0.35))
                .clipShape(RoundedRectangle(cornerRadius: 14))
                .overlay(
                    RoundedRectangle(cornerRadius: 14)
                        .stroke(focusedField == .description ? DS.Color.primary.opacity(0.55) : DS.Color.ink.opacity(0.08), lineWidth: 1.2)
                )
                .foregroundStyle(DS.Color.ink)
                .font(.system(size: 15))
                .submitLabel(.done)
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Terminé") {
                            focusedField = nil
                        }
                        .font(.system(size: 15, weight: .semibold))
                    }
                }
                .padding(.horizontal, 18)
                .id("descriptionField")
                // Removed manual .onTapGesture that set focusedField — it was
                // racing with TextField's native tap-to-focus and swallowing
                // the first tap, forcing users to tap 2–3 times before the
                // keyboard came up. The .focused() binding handles it.
                .onChange(of: description) { _, newValue in
                    if newValue.count > 280 {
                        description = String(newValue.prefix(280))
                    }
                }

            HStack {
                Text("Facultatif")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Text(descriptionCharacterCountText)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 18)
        }
    }

    // MARK: - Submit bar

    private var submitBar: some View {
        Button(action: submit) {
            HStack(spacing: 10) {
                if isSubmitting {
                    ProgressView().tint(DS.Color.primaryForeground)
                } else if submitSuccess {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                    Text("Envoyé")
                } else {
                    Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                    Text("Signaler")
                }
            }
            .font(DS.Font.bodyBold)
            .foregroundStyle(canSubmit || submitSuccess ? DS.Color.primaryForeground : DS.Color.primaryForeground.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .background(canSubmit || submitSuccess ? DS.Color.primary : DS.Color.primary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(DS.Color.ink, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
        .disabled(!canSubmit)
        .padding(.horizontal, 18)
        .padding(.bottom, submitBottomPadding)
        .padding(.top, 10)
        .background(DS.Color.paper)
    }

    // MARK: - Helpers

    private func sectionTitle(icon: String, text: String) -> some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute)
            Text(text)
                .font(DS.Font.sectionTitle)
                .foregroundStyle(DS.Color.ink)
                .kerning(1.2)
        }
        .padding(.horizontal, 18)
    }

    private func stopDistanceAndLineCountText(_ stop: NearbyStop) -> String {
        let lineLabel = stop.lines.count == 1 ? String(localized: "ligne") : String(localized: "lignes")
        return "\(stop.distanceMeters)m · \(stop.lines.count) \(lineLabel)"
    }

    private func confirmationCountText(_ count: Int) -> String {
        let label = count == 1 ? String(localized: "confirmé") : String(localized: "confirmés")
        return "· \(count) \(label)"
    }

    private var descriptionCharacterCountText: String {
        "\(description.count)/280"
    }

    private func relativeTime(from date: Date?) -> String {
        guard let date else { return "À l'instant" }
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 60 { return "à l'instant" }
        let minutes = seconds / 60
        if minutes < 60 { return "il y a \(minutes) min" }
        return "il y a \(minutes / 60) h"
    }

    private func handleClose() {
        focusedField = nil
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isShowing = false
        }
    }

    // MARK: - Bootstrap

    private func bootstrap() {
        guard selectedOperator == .stib else {
            loadLocalOperatorTargets()
            return
        }
        guard let lat = userLatitude, let lng = userLongitude else { return }
        isLoadingStops = true
        Task {
            defer { isLoadingStops = false }
            do {
                let stops = try await NearbyStopService.fetchNearby(lat: lat, lng: lng)
                guard selectedOperator == .stib else { return }
                nearbyStops = stops
                selectedStop = NearestStopFinder.nearest(
                    to: userCoordinate, in: stops, maxMeters: 120
                ) ?? NearestStopFinder.closest(
                    to: userCoordinate, in: stops
                ) ?? stops.first
                selectedLine = selectedStop?.issueLines.first
            } catch {
                print("NearbyStopService failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadLocalOperatorTargets() {
        isLoadingStops = false
        switch selectedOperator {
        case .sncb:
            let stops = SNCBStationService.nearbyStations(
                around: userCoordinate,
                radiusMeters: 35_000,
                limit: 8
            ).map(SNCBStationService.nearbyStop(from:))
            nearbyStops = stops
            selectedStop = stops.first
            selectedLine = stops.first?.issueLines.first
        case .delijn, .tec:
            isLoadingStops = true
            let op = selectedOperator
            // Fall back to Brussels centre if the device location isn't ready
            // yet (same behaviour as SNCB) so the picker is never empty.
            let origin = userCoordinate ?? CLLocationCoordinate2D(latitude: 50.8503, longitude: 4.3517)
            // De Lijn / TEC stops are served by viewport — fetch a box around
            // the user, widening once if the area is sparse.
            Task {
                defer { isLoadingStops = false }
                func fetch(_ d: Double) async -> [OperatorMapStop] {
                    await OperatorStopService.stops(
                        operator: op,
                        minLat: origin.latitude - d, maxLat: origin.latitude + d,
                        minLng: origin.longitude - d, maxLng: origin.longitude + d,
                        limit: 80
                    )
                }
                var stops = await fetch(0.03)         // ≈ 3 km
                if stops.isEmpty { stops = await fetch(0.09) } // widen if sparse/edge
                guard selectedOperator == op else { return }
                let originLoc = CLLocation(latitude: origin.latitude, longitude: origin.longitude)
                let nearby = stops
                    .map { s -> (OperatorMapStop, Int) in
                        (s, Int(originLoc.distance(from: CLLocation(latitude: s.lat, longitude: s.lng)).rounded()))
                    }
                    .sorted { $0.1 < $1.1 }
                    .prefix(40)
                    .map { operatorNearbyStop(from: $0.0, distanceMeters: $0.1) }
                nearbyStops = Array(nearby)
                selectedStop = nearbyStops.first
                selectedLine = nearbyStops.first?.issueLines.first
            }
        case .stib:
            break
        }
    }

    /// Build a `NearbyStop` for a De Lijn / TEC stop, with a single operator
    /// pseudo-line (these networks expose no per-stop line list locally).
    private func operatorNearbyStop(from stop: OperatorMapStop, distanceMeters: Int) -> NearbyStop {
        let color = stop.op.brandColor
        let issue = NearbyIssueLine(
            number: stop.op.mapLabel,
            color: color,
            direction: stop.op.mapLabel,
            crowding: .low,
            reliability: 100,
            lineTextColor: stop.op.brandTextColor
        )
        return NearbyStop(
            backendId: stop.id,
            stopId: stop.id,
            name: stop.name,
            lines: [StopLine(number: stop.op.mapLabel, color: color)],
            distanceMeters: distanceMeters,
            issueLines: [issue],
            coordinate: stop.coordinate
        )
    }

    private func resetTargetSelection() {
        selectedStop = nil
        selectedLine = nil
        selectedProblem = nil
        description = ""
        submitError = nil
        isStopPickerExpanded = false
        stopSearchQuery = ""
        sncbTrainOptions = []
        selectedSncbTrain = nil
    }

    /// Loads the selected gare's upcoming trains for the SNCB "Train concerné"
    /// picker — live (iRail) first so the user sees real times/delays, falling
    /// back to the static next departures. No-op for non-SNCB.
    @MainActor
    private func loadSncbTrains() async {
        selectedSncbTrain = nil
        guard selectedOperator == .sncb, let stop = selectedStop,
              let gareId = stop.stopId ?? stop.backendId else {
            sncbTrainOptions = []
            return
        }
        isLoadingSncbTrains = true
        defer { isLoadingSncbTrains = false }

        if let rt = await SNCBStationService.realtime(stationId: gareId), !rt.departures.isEmpty {
            sncbTrainOptions = rt.departures.prefix(15).map {
                SNCBTrainOption(
                    id: "rt-\($0.scheduledMinutes)-\($0.destination)-\($0.line)",
                    line: $0.line, destination: $0.destination, time: $0.time,
                    delayMinutes: $0.delayMinutes, canceled: $0.canceled
                )
            }
        } else {
            let deps = await SNCBStationService.departures(stationId: gareId, limit: 15)
            sncbTrainOptions = deps.map {
                SNCBTrainOption(
                    id: "sc-\($0.minutes)-\($0.destination)-\($0.line)",
                    line: $0.line, destination: $0.destination, time: $0.time,
                    delayMinutes: 0, canceled: false
                )
            }
        }
    }

    // MARK: - Submit

    private func submit() {
        focusedField = nil
        guard canSubmit,
              let stop = selectedStop,
              let line = selectedLine,
              let problem = selectedProblem
        else { return }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        var finalDescription = trimmed.count >= 3 ? trimmed : "Signalement rapide — \(problem.title)"
        // SNCB: fold the chosen train into the description so the report stays
        // tied to a specific departure while `ligne` remains "SNCB".
        if selectedOperator == .sncb, let train = selectedSncbTrain {
            let lineText = train.line.isEmpty ? "" : "\(train.line) "
            finalDescription = "🚆 \(lineText)→ \(train.destination) · \(train.time)\n\(finalDescription)"
        }
        let reportLatitude = stop.coordinate?.latitude ?? userLatitude
        let reportLongitude = stop.coordinate?.longitude ?? userLongitude

        isSubmitting = true
        submitError = nil

        Task {
            do {
                let response = try await SignalementService.ajouter(
                    nomArret: stop.name,
                    ligne: line.number,
                    typeProbleme: problem.title,
                    description: finalDescription,
                    latitude: reportLatitude,
                    longitude: reportLongitude,
                    transportOperator: selectedOperator.rawValue,
                    photo: nil
                )
                // Hand the new signalement back to the parent so it can appear
                // on the map + in the stop detail before the next backend poll.
                onSubmitted?(response.signalement)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.25)) {
                    submitSuccess = true
                    showConfetti = true
                }
                // Let the confetti play, then offer to warn relatives instead
                // of closing straight away.
                try? await Task.sleep(nanoseconds: 800_000_000)
                createdSignalement = response.signalement
            } catch {
                let isNetworkIssue = isNetworkRelated(error)
                if isNetworkIssue {
                    // Queue offline — sync will happen when connectivity returns.
                    OfflineCache.enqueueReport(OfflineCache.QueuedReport(
                        nomArret: stop.name,
                        ligne: line.number,
                        typeProbleme: problem.title,
                        description: finalDescription,
                        latitude: reportLatitude,
                        longitude: reportLongitude,
                        transportOperator: selectedOperator.rawValue
                    ))
                    UINotificationFeedbackGenerator().notificationOccurred(.success)
                    withAnimation(.easeOut(duration: 0.25)) {
                        submitSuccess = true
                        submitError = "Hors ligne. Envoi quand la connexion revient."
                    }
                    try? await Task.sleep(nanoseconds: 1_800_000_000)
                    handleClose()
                } else {
                    UINotificationFeedbackGenerator().notificationOccurred(.error)
                    submitError = (error as? APIError)?.errorDescription ?? error.localizedDescription
                }
            }
            isSubmitting = false
        }
    }

    private func isNetworkRelated(_ error: Error) -> Bool {
        if let apiError = error as? APIError {
            if case .network = apiError { return true }
        }
        let nsError = error as NSError
        if nsError.domain == NSURLErrorDomain {
            return [
                NSURLErrorNotConnectedToInternet,
                NSURLErrorNetworkConnectionLost,
                NSURLErrorTimedOut,
                NSURLErrorCannotFindHost,
                NSURLErrorCannotConnectToHost,
                NSURLErrorDNSLookupFailed,
            ].contains(nsError.code)
        }
        return false
    }

    private func scrollToDescription(_ proxy: ScrollViewProxy, delay: Double = 0.12) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            withAnimation(.easeOut(duration: 0.22)) {
                proxy.scrollTo("descriptionField", anchor: .top)
            }
        }
    }

    private func confirmExisting(_ signalement: SignalementDTO) {
        guard confirmingExistingId == nil else { return }
        confirmingExistingId = signalement.id
        UIImpactFeedbackGenerator(style: .soft).impactOccurred()
        Task {
            do {
                _ = try await SignalementService.confirmer(signalementId: signalement.id)
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.25)) {
                    showConfetti = true
                    submitSuccess = true
                }
                try? await Task.sleep(nanoseconds: 900_000_000)
                handleClose()
            } catch {
                submitError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            confirmingExistingId = nil
        }
    }
}

// MARK: - Confetti burst

private struct ConfettiBurst: View {
    @State private var animate = false
    private let colors: [Color] = [
        AppTheme.Palette.alert,
        AppTheme.Palette.warning,
        AppTheme.Palette.success,
        AppTheme.Palette.info,
        AppTheme.Palette.brandStrong,
        AppTheme.Palette.brand
    ]

    var body: some View {
        GeometryReader { proxy in
            ZStack {
                ForEach(0..<36, id: \.self) { index in
                    ConfettiParticle(
                        color: colors[index % colors.count],
                        horizontalStart: CGFloat.random(in: -proxy.size.width / 2 ... proxy.size.width / 2),
                        horizontalEnd: CGFloat.random(in: -proxy.size.width / 2 ... proxy.size.width / 2),
                        delay: Double.random(in: 0...0.3),
                        duration: Double.random(in: 1.0...1.8),
                        rotationStart: Double.random(in: 0...360),
                        rotationEnd: Double.random(in: 360...1080),
                        size: CGFloat.random(in: 6...12),
                        animate: animate,
                        screenHeight: proxy.size.height
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .onAppear {
            withAnimation(.easeOut(duration: 1.6)) { animate = true }
        }
    }
}

private struct ConfettiParticle: View {
    let color: Color
    let horizontalStart: CGFloat
    let horizontalEnd: CGFloat
    let delay: Double
    let duration: Double
    let rotationStart: Double
    let rotationEnd: Double
    let size: CGFloat
    let animate: Bool
    let screenHeight: CGFloat

    var body: some View {
        RoundedRectangle(cornerRadius: 1.5)
            .fill(color)
            .frame(width: size, height: size * 1.6)
            .rotationEffect(.degrees(animate ? rotationEnd : rotationStart))
            .offset(
                x: animate ? horizontalEnd : horizontalStart,
                y: animate ? screenHeight / 2 + 100 : -screenHeight / 2 - 50
            )
            .opacity(animate ? 0 : 1)
            .animation(.easeIn(duration: duration).delay(delay), value: animate)
    }
}
