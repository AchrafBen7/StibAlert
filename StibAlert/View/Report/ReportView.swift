import SwiftUI
import CoreLocation

// MARK: - 3-level snap sheet heights

enum SheetLevel: Int, CaseIterable {
    case peek    // just handle visible
    case middle  // half open
    case full    // full screen

    func height(screen: CGFloat) -> CGFloat {
        switch self {
        case .peek:   return 110
        case .middle: return 340
        case .full:   return screen
        }
    }
}

// MARK: - Report sheet (overlaid on HomeView's map)

struct ReportSheetView: View {
    @EnvironmentObject private var stibi: StibiCenter
    @Binding var isShowing: Bool
    var userLatitude: Double? = nil
    var userLongitude: Double? = nil

    @State private var level: SheetLevel = .full
    @GestureState private var liveOffset: CGFloat = 0
    @State private var selectedStop: UUID? = nil
    @State private var selectedIssueLine: UUID? = nil
    @State private var selectedProblemType: ReportProblemType? = nil
    @State private var isShowingProblemTypeHelp = false
    @State private var additionalDetails = ""
    @State private var currentStep: ReportFlowStep = .stop
    @State private var isSubmitting = false
    @State private var submitError: String?
    @State private var submitSuccess = false
    @State private var stibiReportBrief: AssistantBriefDTO?

    private let screen = UIScreen.main.bounds.height
    private let snapSpring = Animation.spring(response: 0.36, dampingFraction: 0.78)

    private var selectedStopItem: NearbyStop? {
        NearbyStopMockData.stops.first(where: { $0.id == selectedStop })
    }

    private var availableIssueLines: [NearbyIssueLine] {
        selectedStopItem?.issueLines ?? []
    }

    private var selectedIssueLineItem: NearbyIssueLine? {
        availableIssueLines.first(where: { $0.id == selectedIssueLine })
    }

    private var formattedReportTime: String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "fr_BE")
        formatter.dateFormat = "HH'h'mm"
        return formatter.string(from: Date())
    }

    // Leaves the status bar / dynamic island area uncovered
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

    private var fullHeight: CGFloat { screen - safeTop - 24 }

    @State private var baseHeight: CGFloat = 0

    private func heights() -> (peek: CGFloat, middle: CGFloat, full: CGFloat) {
        (110, 340, fullHeight)
    }

    private var displayHeight: CGFloat {
        let h = heights()
        return (baseHeight - liveOffset).clamped(to: h.peek...h.full)
    }

    private var sheetDrag: some Gesture {
        DragGesture(minimumDistance: 6, coordinateSpace: .global)
            .updating($liveOffset) { value, state, _ in
                state = value.translation.height
            }
            .onEnded { value in
                let h = heights()
                let velocity = value.predictedEndTranslation.height - value.translation.height
                let endH = (baseHeight - value.translation.height).clamped(to: h.peek...h.full)
                let snapped = snapToLevel(current: endH, velocity: velocity)
                withAnimation(snapSpring) { level = snapped }
                baseHeight = heightFor(snapped)

                if snapped == .peek && value.translation.height > 60 {
                    withAnimation(snapSpring) { isShowing = false }
                }
            }
    }

    private func heightFor(_ l: SheetLevel) -> CGFloat {
        switch l {
        case .peek:   return heights().peek
        case .middle: return heights().middle
        case .full:   return heights().full
        }
    }

    private func snapToLevel(current: CGFloat, velocity: CGFloat) -> SheetLevel {
        let levels = SheetLevel.allCases
        if velocity < -300 { return levels[min(level.rawValue + 1, levels.count - 1)] }
        if velocity > 300  { return levels[max(level.rawValue - 1, 0)] }
        return levels.min(by: { abs(heightFor($0) - current) < abs(heightFor($1) - current) }) ?? .middle
    }

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                Capsule()
                    .fill(Color.white.opacity(0.55))
                    .frame(width: 44, height: 5)
                    .padding(.top, 18)
                    .padding(.bottom, 18)
                    .frame(maxWidth: .infinity)

                SheetNavigationRow(
                    showsBack: currentStep != .stop,
                    onBack: handleBack,
                    onClose: handleClose
                )
                .padding(.horizontal, 20)
                .padding(.bottom, 18)

                ScrollView(showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        StepIndicatorRow(current: currentStep.rawValue, total: 5)
                            .padding(.horizontal, 20)
                            .padding(.bottom, 20)

                        Text(currentStepTitle)
                            .font(DesignSystem.Typography.title2)
                            .foregroundStyle(.white)
                            .padding(.horizontal, 20)

                        Text(currentStepSubtitle)
                            .font(DesignSystem.Typography.description)
                            .foregroundStyle(AppTheme.Colors.textInverse)
                            .padding(.horizontal, 20)
                            .padding(.top, 4)
                            .padding(.bottom, 20)

                        if currentStep == .stop {
                            StopCardsGrid(selectedStop: $selectedStop)
                                .padding(.horizontal, 14)
                        } else if currentStep == .line {
                            IssueLineCardsGrid(
                                lines: availableIssueLines,
                                selectedLine: $selectedIssueLine
                            )
                            .padding(.horizontal, 14)
                        } else if currentStep == .problemType {
                            ProblemTypeStepView(selectedProblemType: $selectedProblemType)
                                .padding(.horizontal, 12)
                        } else if currentStep == .details {
                            AdditionalDetailsStepView(details: $additionalDetails)
                                .padding(.horizontal, 16)
                        } else {
                            ReportConfirmationStepView(
                                stopName: selectedStopItem?.name ?? "Non défini",
                                line: selectedIssueLineItem,
                                problemType: selectedProblemType,
                                description: additionalDetails,
                                formattedTime: formattedReportTime
                            )
                            .padding(.horizontal, 16)
                        }

                        if currentStep == .problemType {
                            ProblemTypeHelpRow {
                                withAnimation(DesignSystem.Animation.quick) {
                                    isShowingProblemTypeHelp = true
                                }
                            }
                            .padding(.horizontal, 16)
                            .padding(.top, 18)
                        }

                        VStack(spacing: 8) {
                            if let submitError {
                                Text(submitError)
                                    .font(AppTheme.Fonts.caption)
                                    .foregroundStyle(AppTheme.Palette.alert)
                                    .multilineTextAlignment(.center)
                                    .padding(.horizontal, 20)
                            }
                            Button(action: handleContinue) {
                                HStack(spacing: 10) {
                                    if isSubmitting {
                                        ProgressView().tint(AppTheme.Palette.textOnBrand)
                                    } else if submitSuccess {
                                        Image(systemName: "checkmark")
                                            .font(.system(size: 18, weight: .bold))
                                        Text("Envoyé")
                                    } else {
                                        Text(currentStep.primaryButtonTitle)
                                    }
                                }
                                .font(AppTheme.Fonts.bodyStrong)
                                .foregroundStyle(buttonIsEnabled ? AppTheme.Palette.textOnBrand : AppTheme.Palette.textOnBrand.opacity(0.45))
                                .frame(maxWidth: .infinity)
                                .frame(height: AppTheme.ButtonHeight.primary)
                                .background(buttonIsEnabled ? AppTheme.Palette.brand : AppTheme.Palette.brand.opacity(0.65))
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                            }
                            .disabled(!buttonIsEnabled || isSubmitting || submitSuccess)
                            .accessibilityLabel(currentStep.primaryButtonTitle)
                            .accessibilityHint("Passe à l'étape suivante du signalement ou envoie la confirmation finale.")
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 36)
                        .padding(.bottom, safeBottom + 6)
                    }
                }
            }
            .scrollDisabled(level != .full || isShowingProblemTypeHelp)

            if isShowingProblemTypeHelp {
                ProblemTypeHelpOverlay {
                    withAnimation(DesignSystem.Animation.quick) {
                        isShowingProblemTypeHelp = false
                    }
                }
                .padding(.horizontal, 12)
                .transition(.opacity)
                .zIndex(1)
            }
        }
        .frame(height: displayHeight)
        .frame(maxWidth: .infinity)
        .background(
            ZStack(alignment: .bottom) {
                AppTheme.Palette.screenElevated
                    .ignoresSafeArea(edges: .bottom)
                RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                    .fill(AppTheme.Palette.screenElevated)
            }
            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: -2)
        )
        .gesture(sheetDrag)
        .onChange(of: level) { _, newLevel in
            baseHeight = heightFor(newLevel)
        }
        .task { await refreshStibiReportHelp() }
        .onChange(of: currentStep) { _, _ in Task { await refreshStibiReportHelp() } }
        .onChange(of: selectedStop) { _, _ in Task { await refreshStibiReportHelp() } }
        .onChange(of: selectedIssueLine) { _, _ in Task { await refreshStibiReportHelp() } }
        .onChange(of: selectedProblemType) { _, _ in Task { await refreshStibiReportHelp() } }
        .onChange(of: additionalDetails) { _, _ in Task { await refreshStibiReportHelp() } }
        .onAppear {
            stibi.setCurrentScreen("report")
            level = .full
            baseHeight = fullHeight
        }
    }

    private var currentStepTitle: String {
        if currentStep == .line, let stopName = selectedStopItem?.name {
            return stopName
        }
        return currentStep.title
    }

    private var currentStepSubtitle: String {
        if currentStep == .line {
            return "Signaler une ligne"
        }
        return currentStep.subtitle
    }

    private var buttonIsEnabled: Bool {
        switch currentStep {
        case .stop:
            return selectedStop != nil
        case .line:
            return selectedIssueLine != nil
        case .problemType:
            return selectedProblemType != nil
        case .details:
            return true
        case .confirmation:
            return true
        }
    }

    private func handleContinue() {
        switch currentStep {
        case .stop:
            guard selectedStop != nil else { return }
            selectedIssueLine = nil
            currentStep = .line
        case .line:
            guard selectedIssueLine != nil else { return }
            selectedProblemType = nil
            currentStep = .problemType
        case .problemType:
            guard selectedProblemType != nil else { return }
            currentStep = .details
        case .details:
            currentStep = .confirmation
        case .confirmation:
            submitSignalement()
        }
    }

    private func submitSignalement() {
        guard
            let stop = selectedStopItem,
            let line = selectedIssueLineItem,
            let problem = selectedProblemType
        else { return }

        let trimmed = additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines)
        let description = trimmed.isEmpty ? "Aucun détail supplémentaire" : trimmed

        isSubmitting = true
        submitError = nil

        Task {
            do {
                _ = try await SignalementService.ajouter(
                    nomArret: stop.name,
                    ligne: line.number,
                    typeProbleme: problem.title,
                    description: description,
                    latitude: userLatitude,
                    longitude: userLongitude,
                    photo: nil
                )
                submitSuccess = true
                try? await Task.sleep(nanoseconds: 600_000_000)
                withAnimation(snapSpring) { isShowing = false }
            } catch {
                submitError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
        }
    }

    private func handleBack() {
        switch currentStep {
        case .stop:
            return
        case .line:
            selectedIssueLine = nil
            currentStep = .stop
        case .problemType:
            isShowingProblemTypeHelp = false
            selectedProblemType = nil
            currentStep = .line
        case .details:
            currentStep = .problemType
        case .confirmation:
            currentStep = .details
        }
    }

    private func handleClose() {
        withAnimation(snapSpring) {
            isShowingProblemTypeHelp = false
            isShowing = false
        }
    }

    @MainActor
    private func refreshStibiReportHelp() async {
        guard AppConfig.isBackendEnabled else { return }
        do {
            let brief = try await AssistantService.reportHelp(
                step: currentStep.stibiStepName,
                stopName: selectedStopItem?.name,
                line: selectedIssueLineItem?.number,
                problemType: selectedProblemType?.title,
                details: additionalDetails.trimmingCharacters(in: .whitespacesAndNewlines),
                lat: userLatitude,
                lng: userLongitude
            )
            stibiReportBrief = brief
            stibi.consume(brief)
        } catch {
            print("Stibi report help failed: \(error.localizedDescription)")
        }
    }
}

// MARK: - Step indicator row

private struct SheetNavigationRow: View {
    let showsBack: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        HStack {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 22, weight: .regular))
                    .foregroundStyle(showsBack ? Color.white : Color.clear)
                    .frame(width: 24, height: 24)
            }
            .disabled(!showsBack)
            .accessibilityLabel("Revenir")
            .accessibilityHint("Revient à l'étape précédente du signalement.")

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 20, weight: .regular))
                    .foregroundStyle(Color.white)
                    .frame(width: 24, height: 24)
            }
            .accessibilityLabel("Fermer")
            .accessibilityHint("Ferme le flow de signalement.")
        }
    }
}

private struct StepIndicatorRow: View {
    let current: Int
    let total: Int

    var body: some View {
        HStack(spacing: 0) {
            ForEach(1...total, id: \.self) { step in
                ZStack {
                    Circle()
                        .stroke(Color.white.opacity(step <= current ? 1.0 : 0.3), lineWidth: 1.5)
                        .frame(width: 32, height: 32)
                    Circle()
                        .fill(step == current ? Color.white.opacity(0.15) : .clear)
                        .frame(width: 32, height: 32)
                    Text("\(step)")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(step <= current ? 1.0 : 0.35))
                }
                if step < total {
                    Rectangle()
                        .fill(Color.white.opacity(0.2))
                        .frame(height: 1)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }
}

// MARK: - Stop cards

private struct StopCardsGrid: View {
    @Binding var selectedStop: UUID?
    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(NearbyStopMockData.stops) { stop in
                NearbyStopCard(stop: stop, isSelected: selectedStop == stop.id)
                    .onTapGesture { selectedStop = stop.id }
            }
        }
    }
}

private struct IssueLineCardsGrid: View {
    let lines: [NearbyIssueLine]
    @Binding var selectedLine: UUID?

    private let columns = [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 10) {
            ForEach(lines) { line in
                IssueLineCard(line: line, isSelected: selectedLine == line.id)
                    .onTapGesture { selectedLine = line.id }
            }
        }
    }
}

private struct ProblemTypeStepView: View {
    @Binding var selectedProblemType: ReportProblemType?

    private let columns = [GridItem(.flexible(), spacing: 14), GridItem(.flexible(), spacing: 14)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 16) {
            ForEach(ReportProblemType.allCases) { problemType in
                ReportProblemTypeCard(
                    problemType: problemType,
                    isSelected: selectedProblemType == problemType
                )
                .onTapGesture {
                    selectedProblemType = problemType
                }
            }
        }
    }
}

private struct ReportProblemTypeCard: View {
    let problemType: ReportProblemType
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(problemType.title)
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .fixedSize(horizontal: false, vertical: true)

                Spacer(minLength: 6)

                Circle()
                    .fill(problemType.accentColor)
                    .frame(width: 12, height: 12)
                    .overlay(
                        Circle()
                            .stroke(Color.black.opacity(isSelected ? 0.18 : 0), lineWidth: 1.5)
                    )
            }

            Spacer(minLength: 14)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(problemType.descriptionLines, id: \.self) { line in
                    Text(line)
                        .font(DesignSystem.Typography.caption)
                        .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.92))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 14)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(problemType.backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(Color.white.opacity(isSelected ? 0.8 : 0), lineWidth: 2)
        )
        .scaleEffect(isSelected ? 0.985 : 1)
        .animation(.easeInOut(duration: 0.16), value: isSelected)
    }
}

private struct ProblemTypeHelpRow: View {
    let onTap: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Text("Je ne suis pas sûr?")
                .font(DesignSystem.Typography.description)
                .foregroundStyle(Color.white.opacity(0.95))

            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.9))
                    .frame(width: 22, height: 22)

                Text("?")
                    .font(DesignSystem.Typography.bodySemibold)
                    .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.75))
            }

            Spacer()
        }
        .contentShape(Rectangle())
        .onTapGesture(perform: onTap)
    }
}

private struct ProblemTypeHelpOverlay: View {
    let onDismiss: () -> Void

    var body: some View {
        ZStack {
            Color.black.opacity(0.53)
                .ignoresSafeArea()
                .onTapGesture(perform: onDismiss)

            VStack(alignment: .leading, spacing: 0) {
                Text("Pas sûr du problème ?")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .padding(.horizontal, 32)
                    .padding(.top, 22)
                    .padding(.bottom, 28)

                VStack(alignment: .leading, spacing: 18) {
                    ForEach(ReportProblemType.allCases) { type in
                        HStack(alignment: .top, spacing: 12) {
                            Circle()
                                .fill(type.accentColor)
                                .frame(width: 30, height: 30)

                            Text(type.helpDescription)
                                .font(DesignSystem.Typography.caption)
                                .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.84))
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding(.horizontal, 32)

                Button("Je comprends", action: onDismiss)
                    .font(DesignSystem.Typography.buttonText)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                    .frame(maxWidth: .infinity)
                    .frame(height: AppTheme.ButtonHeight.primary)
                    .background(AppTheme.Palette.surfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
                    .padding(.horizontal, 12)
                    .padding(.top, 28)
                    .padding(.bottom, 16)
                    .accessibilityHint("Ferme l'aide sur les types de problème.")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        }
    }
}

private struct AdditionalDetailsStepView: View {
    @Binding var details: String

    private let limit = 250

    private var clampedDetails: Binding<String> {
        Binding(
            get: { details },
            set: { newValue in
                details = String(newValue.prefix(limit))
            }
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .fill(Color.white)
                .frame(height: 273)
                .overlay(alignment: .topLeading) {
                    TextEditor(text: clampedDetails)
                        .scrollContentBackground(.hidden)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 10)
                        .background(Color.clear)
                        .overlay(alignment: .topLeading) {
                            if details.isEmpty {
                                Text("Ce champ est facultatif. Ex: “Le tram est bloqué\ndepuis 5 min au feu.”")
                                    .font(DesignSystem.Typography.body)
                                    .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.82))
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 16)
                                    .allowsHitTesting(false)
                            }
                        }
                }

            Text("\(details.count)/\(limit)")
                .font(DesignSystem.Typography.body)
                .foregroundStyle(AppTheme.Palette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .trailing)
                .padding(.top, 10)
                .padding(.trailing, 4)
        }
    }
}

private struct ReportConfirmationStepView: View {
    let stopName: String
    let line: NearbyIssueLine?
    let problemType: ReportProblemType?
    let description: String
    let formattedTime: String

    private var finalDescription: String {
        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Aucun détail supplémentaire" : trimmed
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top) {
                Text("Confirmation")
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)

                Spacer()

                Image(systemName: "checkmark")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
            }

            Text("Votre signalement aide à améliorer les trajets.")
                .font(DesignSystem.Typography.description)
                .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.84))

            VStack(alignment: .leading, spacing: 18) {
                confirmationRow(index: 1, title: "Arret", content: stopName)
                confirmationLineRow(index: 2, line: line)
                confirmationRow(index: 3, title: "Type de probleme", content: problemType?.title ?? "Non défini")
                confirmationRow(index: 4, title: "Description", content: finalDescription)
                confirmationRow(index: 5, title: "Heures", content: formattedTime)
            }
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.Palette.brandStrong.opacity(0.9))
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous)
                .stroke(AppTheme.Palette.info.opacity(0.72), lineWidth: 1)
        )
    }

    private func confirmationRow(index: Int, title: String, content: String) -> some View {
        (
            Text("\(index). ")
                .font(DesignSystem.Typography.bodySemibold)
            + Text("\(title): ")
                .font(DesignSystem.Typography.bodySemibold)
            + Text(content)
                .font(DesignSystem.Typography.body)
        )
        .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.95))
        .fixedSize(horizontal: false, vertical: true)
    }

    @ViewBuilder
    private func confirmationLineRow(index: Int, line: NearbyIssueLine?) -> some View {
        HStack(alignment: .top, spacing: 0) {
            (
                Text("\(index). ")
                    .font(DesignSystem.Typography.bodySemibold)
                + Text("Lignes: ")
                    .font(DesignSystem.Typography.bodySemibold)
            )
            .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.95))

            if let line {
                HStack(spacing: 8) {
                    Text(line.number)
                        .font(DesignSystem.Typography.captionStrong)
                        .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.95))
                        .frame(width: 24, height: 24)
                        .background(line.color)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                    Text(line.direction)
                        .font(DesignSystem.Typography.body)
                        .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.95))
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text("Non définie")
                    .font(DesignSystem.Typography.body)
                    .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.95))
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct NearbyStopCard: View {
    let stop: NearbyStop
    let isSelected: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(stop.name)
                    .font(DesignSystem.Typography.title3)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                Circle()
                    .fill(AppTheme.Palette.info)
                    .frame(width: 10, height: 10)
                    .padding(.top, 3)
            }
            WrappingLineBadges(lines: stop.lines)
            Spacer(minLength: 0)
            Text("\(stop.distanceMeters)m de votre position")
                .font(DesignSystem.Typography.caption)
                .foregroundStyle(AppTheme.Palette.textOnBrand)
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 120, alignment: .topLeading)
        .background(isSelected ? AppTheme.Palette.brandStrong.opacity(0.92) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct IssueLineCard: View {
    let line: NearbyIssueLine
    let isSelected: Bool

    private var reliabilityColor: Color {
        if line.reliability >= 90 { return AppTheme.Palette.success }
        if line.reliability >= 60 { return AppTheme.Palette.warning }
        return AppTheme.Palette.alert
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: 8) {
                Text(line.number)
                    .font(DesignSystem.Typography.title2)
                    .foregroundStyle(line.lineTextColor)
                    .frame(width: 32, height: 31)
                    .background(line.color)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                Spacer(minLength: 4)

                Text("\(line.reliability)% fiable")
                    .font(DesignSystem.Typography.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)
                    .padding(.horizontal, 10)
                    .frame(height: 32)
                    .background(reliabilityColor)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
            }
            .padding(.bottom, 12)

            Text(line.direction)
                .font(DesignSystem.Typography.bodySemibold)
                .foregroundStyle(AppTheme.Palette.textOnBrand)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 12)

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Text("Affluence:")
                    .font(DesignSystem.Typography.caption)
                    .foregroundStyle(AppTheme.Palette.textOnBrand)

                HStack(spacing: 4) {
                    ForEach(0..<5, id: \.self) { index in
                        Image(systemName: "person.fill")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundStyle(index < line.crowding.level ? AppTheme.Palette.textOnBrand : AppTheme.Palette.textOnBrand.opacity(0.16))
                    }
                }
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, minHeight: 126, alignment: .topLeading)
        .background(isSelected ? AppTheme.Palette.brandStrong.opacity(0.9) : Color.white)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
        .shadow(color: .black.opacity(0.25), radius: 2, x: 0, y: 4)
        .overlay(
            RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                .stroke(isSelected ? Color.clear : Color.clear, lineWidth: 0)
        )
        .animation(.easeInOut(duration: 0.15), value: isSelected)
    }
}

private struct WrappingLineBadges: View {
    let lines: [StopLine]
    var body: some View {
        let chunks = lines.chunked(into: 4)
        VStack(alignment: .leading, spacing: 5) {
            ForEach(chunks.indices, id: \.self) { i in
                HStack(spacing: 5) {
                    ForEach(chunks[i]) { line in
                        Text(line.number)
                            .font(DesignSystem.Typography.captionStrong)
                            .foregroundStyle(AppTheme.Palette.textOnBrand)
                            .frame(width: 28, height: 24)
                            .background(line.color)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                    }
                }
            }
        }
    }
}

// MARK: - Models

struct StopLine: Identifiable {
    let id = UUID()
    let number: String
    let color: Color
}

struct NearbyStop: Identifiable {
    let id = UUID()
    let name: String
    let lines: [StopLine]
    let distanceMeters: Int
    let issueLines: [NearbyIssueLine]
    var coordinate: CLLocationCoordinate2D? = nil
}

struct NearbyIssueLine: Identifiable {
    let id = UUID()
    let number: String
    let color: Color
    let direction: String
    let crowding: IssueLineCrowding
    let reliability: Int
    let lineTextColor: Color
}

enum IssueLineCrowding {
    case low
    case medium
    case high

    var label: String {
        switch self {
        case .low: return "faible"
        case .medium: return "moyenne"
        case .high: return "élevée"
        }
    }

    var level: Int {
        switch self {
        case .low: return 1
        case .medium: return 3
        case .high: return 5
        }
    }
}

enum ReportFlowStep: Int {
    case stop = 1
    case line = 2
    case problemType = 3
    case details = 4
    case confirmation = 5

    var title: String {
        switch self {
        case .stop: return "Arrets a proximité"
        case .line: return "Lignes problematiques"
        case .problemType: return "Quel est le problème ?"
        case .details: return "Un détail à ajouter ?"
        case .confirmation: return ""
        }
    }

    var subtitle: String {
        switch self {
        case .stop: return "Signaler un arret"
        case .line: return "Choisissez la ligne concernée"
        case .problemType: return "Sélectionnez le type de problème recontré"
        case .details: return "Aide les autres à comprendre la situation plus précisément."
        case .confirmation: return ""
        }
    }

    var primaryButtonTitle: String {
        switch self {
        case .confirmation:
            return "Envoyer"
        default:
            return "Continuer"
        }
    }

    var stibiStepName: String {
        switch self {
        case .stop: return "stop"
        case .line: return "line"
        case .problemType: return "problemType"
        case .details: return "details"
        case .confirmation: return "confirmation"
        }
    }
}

enum ReportProblemType: String, CaseIterable, Identifiable {
    case accident
    case delay
    case breakdown
    case incivility
    case cleanliness
    case aggression

    var id: String { rawValue }

    var title: String {
        switch self {
        case .accident: return "Accident"
        case .delay: return "Retard"
        case .breakdown: return "Panne"
        case .incivility: return "Incivilité"
        case .cleanliness: return "Propreté"
        case .aggression: return "Agression"
        }
    }

    var descriptionLines: [String] {
        switch self {
        case .accident:
            return ["Collision ou chute", "Police ou pompiers sur place"]
        case .delay:
            return ["Plus de 10 min d’attente?", "Transport non arrivé?"]
        case .breakdown:
            return ["Véhicule bloqué", "Portes ou moteur en panne"]
        case .incivility:
            return ["Musique ou cris forts", "Portes ou moteur en panne"]
        case .cleanliness:
            return ["Déchets ou odeur forte", "Sol ou siège très sale"]
        case .aggression:
            return ["Comportement violent", "Harcèlement observé"]
        }
    }

    var backgroundColor: Color {
        switch self {
        case .accident: return Color(hex: "#FFB4B4")
        case .delay: return Color(hex: "#FFB9EE")
        case .breakdown: return Color(hex: "#FFED91")
        case .incivility: return Color(hex: "#BBDCFF")
        case .cleanliness: return Color(hex: "#CBFBE6")
        case .aggression: return Color(hex: "#FFCFA1")
        }
    }

    var accentColor: Color {
        switch self {
        case .accident: return Color(hex: "#FF6B6B")
        case .delay: return Color(hex: "#EE63D8")
        case .breakdown: return Color(hex: "#FFD34D")
        case .incivility: return Color(hex: "#73A9F8")
        case .cleanliness: return Color(hex: "#45D29A")
        case .aggression: return Color(hex: "#FF922E")
        }
    }

    var helpDescription: String {
        switch self {
        case .accident:
            return "Collision, chute, blessé ou véhicule endommagé."
        case .delay:
            return "Plus de 10 min d’attente, transport qui n’arrive pas."
        case .breakdown:
            return "Véhicule bloqué ou portes qui ne s’ouvrent pas."
        case .incivility:
            return "Cris, musique forte, comportements dérangeants."
        case .cleanliness:
            return "Mauvaises odeurs, saleté au sol ou sur les sièges."
        case .aggression:
            return "Personne violente ou harcèlement observé."
        }
    }
}

extension Array {
    func chunked(into size: Int) -> [[Element]] {
        stride(from: 0, to: count, by: size).map {
            Array(self[$0..<Swift.min($0 + size, count)])
        }
    }
}

extension Comparable {
    func clamped(to range: ClosedRange<Self>) -> Self {
        max(range.lowerBound, min(range.upperBound, self))
    }
}

// MARK: - Mock data

enum NearbyStopMockData {
    private static func l(_ n: String, _ r: Double, _ g: Double, _ b: Double) -> StopLine {
        StopLine(number: n, color: Color(red: r, green: g, blue: b))
    }
    private static func i(_ n: String, _ r: Double, _ g: Double, _ b: Double, _ transport: String, _ direction: String, _ crowding: IssueLineCrowding) -> NearbyIssueLine {
        NearbyIssueLine(
            number: n,
            color: Color(red: r, green: g, blue: b),
            direction: direction,
            crowding: crowding,
            reliability: mockReliability(for: n, transport: transport),
            lineTextColor: lineForeground(for: transport, number: n)
        )
    }

    private static func mockReliability(for line: String, transport: String) -> Int {
        switch (transport, line) {
        case ("Metro", "1"): return 63
        case ("Metro", "5"): return 98
        case ("Metro", "2"): return 93
        case ("Metro", "6"): return 25
        case ("Tram", "92"): return 37
        default: return 63
        }
    }

    private static func lineForeground(for transport: String, number: String) -> Color {
        switch (transport, number) {
        case ("Tram", "92"), ("Metro", "5"), ("Bus", "95"), ("Bus", "33"):
            return .white
        default:
            return .black
        }
    }
    private static func c(_ lat: Double, _ lng: Double) -> CLLocationCoordinate2D {
        CLLocationCoordinate2D(latitude: lat, longitude: lng)
    }
    static let stops: [NearbyStop] = [
        .init(name: "Gare centrale", lines: [l("63",0.57,0.75,0.90),l("66",0.14,0.35,0.71),l("65",0.93,0.64,0.18),l("89",0.52,0.63,0.19),l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12)], distanceMeters: 50, issueLines: [
            i("1",0.42,0.22,0.68,"Metro","vers Stockel",.medium),
            i("5",0.90,0.50,0.14,"Metro","vers Erasme",.high),
            i("38",0.55,0.36,0.75,"Bus","vers Herois",.low),
            i("71",0.18,0.62,0.23,"Bus","vers Delta",.medium)
        ], coordinate: c(50.8446, 4.3571)),
        .init(name: "Bourse", lines: [l("63",0.57,0.75,0.90),l("66",0.14,0.35,0.71),l("65",0.93,0.64,0.18),l("89",0.52,0.63,0.19),l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12),l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12)], distanceMeters: 95, issueLines: [
            i("3",0.00,0.67,0.40,"Metro","vers Churchill",.high),
            i("4",0.91,0.28,0.44,"Tram","vers Gare du Nord",.medium),
            i("10",0.55,0.36,0.75,"Tram","vers Vanderkindere",.low)
        ], coordinate: c(50.8487, 4.3514)),
        .init(name: "Royale", lines: [l("33",0.91,0.42,0.55),l("38",0.55,0.36,0.75),l("71",0.18,0.62,0.23),l("95",0.14,0.42,0.25)], distanceMeters: 120, issueLines: [
            i("92",0.82,0.27,0.12,"Tram","vers Fort-Jaco",.medium),
            i("33",0.91,0.42,0.55,"Bus","vers Dansaert",.low),
            i("95",0.14,0.42,0.25,"Bus","vers Wiener",.high)
        ], coordinate: c(50.8443, 4.3657)),
        .init(name: "Parc", lines: [l("63",0.57,0.75,0.90),l("66",0.14,0.35,0.71),l("65",0.93,0.64,0.18),l("89",0.52,0.63,0.19),l("92",0.82,0.27,0.12),l("93",0.88,0.44,0.10),l("29",0.90,0.50,0.14)], distanceMeters: 150, issueLines: [
            i("2",0.23,0.45,0.84,"Metro","vers Simonis",.medium),
            i("6",0.14,0.35,0.71,"Metro","vers Roi Baudouin",.high),
            i("29",0.90,0.50,0.14,"Bus","vers De Brouckere",.low)
        ], coordinate: c(50.8453, 4.3658)),
        .init(name: "De Brouckère", lines: [l("4",0.91,0.28,0.44),l("10",0.55,0.36,0.75),l("5",0.90,0.50,0.14),l("1",0.42,0.22,0.68)], distanceMeters: 175, issueLines: [
            i("1",0.42,0.22,0.68,"Metro","vers Weststation",.low),
            i("5",0.90,0.50,0.14,"Metro","vers Herrmann-Debroux",.medium),
            i("4",0.91,0.28,0.44,"Tram","vers Stalle",.high)
        ], coordinate: c(50.8509, 4.3535)),
        .init(name: "Palais", lines: [l("92",0.82,0.27,0.12)], distanceMeters: 200, issueLines: [
            i("92",0.82,0.27,0.12,"Tram","vers Schaerbeek Gare",.medium)
        ], coordinate: c(50.8423, 4.3666)),
        .init(name: "Sainte-Catherine", lines: [l("1",0.42,0.22,0.68),l("5",0.90,0.50,0.14)], distanceMeters: 250, issueLines: [
            i("1",0.42,0.22,0.68,"Metro","vers Stockel",.low),
            i("5",0.90,0.50,0.14,"Metro","vers Erasme",.medium)
        ], coordinate: c(50.8511, 4.3493)),
        .init(name: "Ravenstein", lines: [l("38",0.55,0.36,0.75),l("52",0.95,0.65,0.12),l("71",0.18,0.62,0.23)], distanceMeters: 300, issueLines: [
            i("38",0.55,0.36,0.75,"Bus","vers Homborch",.low),
            i("52",0.95,0.65,0.12,"Bus","vers Gare Centrale",.medium),
            i("71",0.18,0.62,0.23,"Bus","vers Delta",.high)
        ], coordinate: c(50.8434, 4.3635)),
    ]
}
