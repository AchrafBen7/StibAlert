import SwiftUI
import CoreLocation
import UIKit

struct QuickReportSheetView: View {
    @Binding var isShowing: Bool
    let userLatitude: Double?
    let userLongitude: Double?
    let activeSignalements: [SignalementDTO]

    @State private var selectedStop: NearbyStop? = nil
    @State private var selectedLine: NearbyIssueLine? = nil
    @State private var selectedProblem: ReportProblemType? = nil
    @State private var detailsExpanded: Bool = false
    @State private var description: String = ""
    @State private var isSubmitting: Bool = false
    @State private var submitError: String? = nil
    @State private var submitSuccess: Bool = false
    @State private var confirmingExistingId: String? = nil

    @State private var showConfetti: Bool = false
    @State private var nearbyStops: [NearbyStop] = []
    @State private var isLoadingStops = false
    @State private var stopSearchQuery = ""

    private let screen = UIScreen.main.bounds.height

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

    private var autoDetectedStop: Bool {
        guard let selectedStop, let stopCoord = selectedStop.coordinate, let userCoordinate else { return false }
        let dx = stopCoord.latitude - userCoordinate.latitude
        let dy = stopCoord.longitude - userCoordinate.longitude
        return dx * dx + dy * dy < 0.0001
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

    private var filteredNearbyStops: [NearbyStop] {
        let trimmed = stopSearchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nearbyStops }
        return nearbyStops.filter { stop in
            stop.name.localizedCaseInsensitiveContains(trimmed)
            || stop.issueLines.contains(where: { $0.number.localizedCaseInsensitiveContains(trimmed) })
            || stop.issueLines.contains(where: { $0.direction.localizedCaseInsensitiveContains(trimmed) })
        }
    }

    private var currentStep: Int {
        if selectedStop == nil { return 1 }
        if selectedLine == nil { return 2 }
        return 3
    }

    private var sheetTitle: String {
        switch currentStep {
        case 1: return "Arrêts à proximité"
        case 2: return "Ligne concernée"
        default: return "Quel est le problème ?"
        }
    }

    private var sheetSubtitle: String {
        switch currentStep {
        case 1: return "Signaler un arrêt"
        case 2: return selectedStop?.name ?? "Choisissez la ligne desservie"
        default: return selectedLine?.direction ?? "Décrivez l’incident"
        }
    }

    var body: some View {
        ZStack {
            DS.Color.ink.opacity(0.42)
                .ignoresSafeArea()
                .onTapGesture(perform: handleClose)

            sheetContent
                .frame(maxWidth: .infinity)
                .background(
                    DS.Color.paper
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .ignoresSafeArea(edges: .bottom)

            if showConfetti {
                ConfettiBurst()
                    .allowsHitTesting(false)
                    .transition(.opacity)
            }
        }
        .onAppear(perform: bootstrap)
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            handleBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 20) {
                    progressHeader
                    stopSection
                    if !matchingActiveSignalements.isEmpty {
                        activeHereSection
                    }
                    lineSection
                    problemSection
                    detailsAccordion
                    Text("Le signalement sera publié sans photo.")
                        .font(DS.Font.bodySmall)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.horizontal, 18)
                    if let submitError {
                        Text(submitError)
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.statusMajor)
                            .padding(.horizontal, 18)
                    }
                    Spacer(minLength: 12)
                }
                .padding(.top, 4)
                .padding(.bottom, 20)
            }

            submitBar
        }
        .frame(maxHeight: screen - safeTop - 24)
    }

    private var progressHeader: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(spacing: 0) {
                ForEach(1...3, id: \.self) { step in
                    HStack(spacing: 0) {
                        ZStack {
                            Circle()
                                .fill(step <= currentStep ? DS.Color.paper : DS.Color.paper)
                                .frame(width: 34, height: 34)
                            Circle()
                                .stroke(step <= currentStep ? DS.Color.ink : DS.Color.ink.opacity(0.25), lineWidth: 1.5)
                                .frame(width: 34, height: 34)
                            Text("\(step)")
                                .font(DS.Font.mono.weight(.bold))
                                .foregroundStyle(step <= currentStep ? DS.Color.ink : DS.Color.inkMute)
                        }

                        if step < 3 {
                            Rectangle()
                                .fill(DS.Color.ink.opacity(0.18))
                                .frame(maxWidth: .infinity)
                                .frame(height: 1.5)
                        }
                    }
                }
            }
            .frame(height: 34)

            VStack(alignment: .leading, spacing: 6) {
                Text(sheetTitle)
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(sheetSubtitle)
                    .font(.system(size: 14))
                    .foregroundStyle(DS.Color.inkSoft)
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Handle

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
            .accessibilityLabel("Fermer le signalement rapide")
            .accessibilityHint("Ferme cette feuille sans envoyer de signalement.")
        }
        .padding(.top, 14)
        .padding(.bottom, 10)
    }

    // MARK: - Stop

    private var stopSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "mappin.and.ellipse", text: "1 · Arrêt")

            stopSearchField

            if isLoadingStops {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.85)
                    Text("Recherche des arrêts à proximité…")
                        .font(.system(size: 12.5))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .padding(.horizontal, 18)
                .padding(.top, 6)
            } else if filteredNearbyStops.isEmpty {
                Text("Aucun arrêt trouvé pour cette recherche.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.Color.inkMute)
                    .padding(.horizontal, 18)
                    .padding(.top, 6)
            } else {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 12) {
                    ForEach(filteredNearbyStops) { stop in
                        stopCard(stop)
                    }
                }
                .padding(.horizontal, 18)
            }
        }
    }

    private var stopSearchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)

            TextField("Rechercher un arrêt ou une ligne", text: $stopSearchQuery)
                .font(.system(size: 14))
                .foregroundStyle(DS.Color.ink)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()

            if !stopSearchQuery.isEmpty {
                Button {
                    stopSearchQuery = ""
                } label: {
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
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .padding(.horizontal, 18)
    }

    private func stopCard(_ stop: NearbyStop) -> some View {
        let isSelected = selectedStop?.id == stop.id
        let primaryLine = stop.issueLines.first?.number ?? stop.lines.first?.number ?? "?"
        let direction = stop.issueLines.first?.direction ?? "Direction à confirmer"
        let borderColor = isSelected ? DS.Color.community.opacity(0.8) : DS.Color.ink.opacity(0.08)

        return Button {
            UISelectionFeedbackGenerator().selectionChanged()
            selectedStop = stop
            selectedLine = stop.issueLines.first
        } label: {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(stop.name.uppercased())
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                    Spacer(minLength: 8)
                    Circle()
                        .fill(isSelected ? DS.Color.community : DS.Color.community.opacity(0.65))
                        .frame(width: 10, height: 10)
                }

                HStack(spacing: 6) {
                    LineBadge(line: primaryLine, size: .sm)

                    ForEach(Array(stop.lines.dropFirst().prefix(2))) { line in
                        LineBadge(line: line.number, size: .sm)
                    }
                }
                .padding(.top, 14)

                Text(direction.uppercased())
                    .font(.system(size: 10.5, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(2)
                    .padding(.top, 12)

                Spacer(minLength: 10)

                Text("\(stop.distanceMeters)m · \(stop.lines.count) lignes")
                    .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(DS.Color.ink)
                    .padding(.top, 16)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 168, alignment: .topLeading)
            .background(isSelected ? DS.Color.hsl(221, 56, 78) : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 24)
                    .stroke(borderColor, lineWidth: isSelected ? 1.5 : 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: 24))
            .shadow(color: DS.Color.ink.opacity(isSelected ? 0.08 : 0.04), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
    }

    // MARK: - Lines

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "tram.fill", text: "2 · Ligne")

            if let stop = selectedStop, !stop.issueLines.isEmpty {
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
                    ForEach(stop.issueLines) { line in
                        lineChip(line)
                    }
                }
                .padding(.horizontal, 18)
            } else {
                Text("Sélectionnez un arrêt pour voir les lignes")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.Color.inkMute)
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
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top, spacing: 10) {
                    LineBadge(line: line.number, size: .lg)
                    Spacer(minLength: 4)
                    if isSelected {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.Color.paper)
                            .frame(width: 20, height: 20)
                            .background(DS.Color.ink)
                            .clipShape(Circle())
                    }
                }

                Text(line.direction.uppercased())
                    .font(.system(size: 12.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(2)
                    .padding(.top, 14)

                HStack(spacing: 6) {
                    crowdingTag(for: line.crowding)
                    reliabilityTag(line.reliability)
                }
                .padding(.top, 10)
            }
            .padding(14)
            .frame(maxWidth: .infinity, minHeight: 112, alignment: .topLeading)
            .background(isSelected ? DS.Color.paper2.opacity(0.75) : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: 18)
                    .stroke(isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.15), lineWidth: 1.5)
            )
            .clipShape(RoundedRectangle(cornerRadius: 18))
        }
        .buttonStyle(.plain)
    }

    private func crowdingTag(for crowding: IssueLineCrowding) -> some View {
        let color: Color
        switch crowding {
        case .low:
            color = DS.Color.statusOK
        case .medium:
            color = DS.Color.statusMinor
        case .high:
            color = DS.Color.statusMajor
        }

        return Text(crowding.label.uppercased())
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .background(color.opacity(0.12))
            .overlay(Capsule().stroke(color.opacity(0.28), lineWidth: 1))
            .clipShape(Capsule())
    }

    private func reliabilityTag(_ reliability: Int) -> some View {
        Text("\(max(0, reliability))% FIABLE")
            .font(.system(size: 9, weight: .bold, design: .monospaced))
            .foregroundStyle(DS.Color.inkMute)
            .padding(.horizontal, 6)
            .padding(.vertical, 4)
            .overlay(Capsule().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
            .clipShape(Capsule())
    }

    // MARK: - Problems

    private var problemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "exclamationmark.triangle.fill", text: "3 · Type de problème")

            LazyVGrid(columns: [GridItem(.flexible(), spacing: 10), GridItem(.flexible(), spacing: 10)], spacing: 10) {
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
                        .foregroundStyle(isSelected ? DS.Color.paper : type.accentColor)
                    Text(type.title)
                        .font(.system(size: 13, weight: .bold))
                        .foregroundStyle(isSelected ? DS.Color.paper : DS.Color.ink)
                    Spacer()
                    Circle()
                        .fill(isSelected ? DS.Color.paper.opacity(0.88) : type.accentColor)
                        .frame(width: 9, height: 9)
                }
                Text(type.descriptionLines.first ?? "")
                    .font(.system(size: 11.5, weight: .medium))
                    .foregroundStyle(isSelected ? DS.Color.paper.opacity(0.82) : DS.Color.inkSoft)
                    .lineLimit(2)
                    .padding(.top, 10)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 84, alignment: .topLeading)
            .background(isSelected ? type.accentColor : DS.Color.paper)
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
        case .accident:
            return "exclamationmark.triangle.fill"
        case .delay:
            return "clock.fill"
        case .breakdown:
            return "wrench.and.screwdriver.fill"
        case .incivility:
            return "person.2.slash.fill"
        case .cleanliness:
            return "sparkles"
        case .aggression:
            return "shield.lefthalf.filled"
        }
    }

    // MARK: - Active here

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
                        Text("· \(confirmations) confirmé·e")
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
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Confirmer")
                        .font(.system(size: 12, weight: .bold))
                }
                .foregroundStyle(DS.Color.paper)
                .padding(.horizontal, 10)
                .frame(height: 34)
                .background(DS.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .buttonStyle(.plain)
            .disabled(confirmingExistingId != nil)
            .accessibilityLabel("Confirmer ce signalement")
            .accessibilityHint("Ajoute votre confirmation à ce problème déjà signalé.")
        }
        .padding(10)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 14)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    // MARK: - Details

    private var detailsAccordion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    detailsExpanded.toggle()
                }
            } label: {
                VStack(alignment: .leading, spacing: 0) {
                    HStack {
                        HStack(spacing: 8) {
                            Image(systemName: "text.badge.plus")
                                .font(.system(size: 13, weight: .semibold))
                            Text("4 · Description")
                                .font(DS.Font.sectionTitle)
                            Text("OPTIONNEL")
                                .font(.system(size: 9, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        Spacer()
                        Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 14)

                    if detailsExpanded {
                        Rectangle()
                            .fill(DS.Color.ink.opacity(0.1))
                            .frame(height: 1)
                            .padding(.horizontal, 14)

                        ZStack(alignment: .topLeading) {
                            TextEditor(text: $description)
                                .scrollContentBackground(.hidden)
                                .frame(minHeight: 112)
                                .padding(10)
                                .background(DS.Color.paper2.opacity(0.35))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                                .foregroundStyle(DS.Color.ink)
                                .font(.system(size: 13))
                            if description.isEmpty {
                                Text("Ex : Tram bloqué depuis 5 min au feu, impossible de monter.")
                                    .font(.system(size: 13))
                                    .foregroundStyle(DS.Color.inkMute)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 18)
                                    .allowsHitTesting(false)
                            }
                        }
                        .padding(14)

                        HStack {
                            Text("Le signalement peut être envoyé sans texte.")
                                .font(.system(size: 11.5))
                                .foregroundStyle(DS.Color.inkMute)
                            Spacer()
                            Text("\(description.count)/280")
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .foregroundStyle(DS.Color.inkMute)
                        }
                        .padding(.horizontal, 14)
                        .padding(.bottom, 14)
                    }
                }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 16))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detailsExpanded ? "Masquer les détails optionnels" : "Afficher les détails optionnels")
            .accessibilityHint("Permet d'ajouter une description au signalement.")
        }
        .padding(.horizontal, 18)
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
                    Text("Publier le signalement")
                }
            }
            .font(DS.Font.bodyBold)
            .foregroundStyle(canSubmit || submitSuccess ? DS.Color.primaryForeground : DS.Color.primaryForeground.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: 48)
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
        .padding(.bottom, safeBottom + 8)
        .padding(.top, 10)
        .accessibilityLabel(submitSuccess ? "Signalement envoyé" : "Envoyer le signalement")
        .accessibilityHint("Envoie le signalement avec l'arrêt, la ligne et le type de problème sélectionnés.")
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

    private func bootstrap() {
        guard let lat = userLatitude, let lng = userLongitude else { return }
        isLoadingStops = true
        Task {
            defer { isLoadingStops = false }
            do {
                let stops = try await NearbyStopService.fetchNearby(lat: lat, lng: lng)
                nearbyStops = stops
                selectedStop = NearestStopFinder.nearest(
                    to: userCoordinate,
                    in: stops,
                    maxMeters: 120
                ) ?? NearestStopFinder.closest(
                    to: userCoordinate,
                    in: stops
                ) ?? stops.first
                selectedLine = selectedStop?.issueLines.first
            } catch {
                print("NearbyStopService failed: \(error.localizedDescription)")
            }
        }
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
        withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
            isShowing = false
        }
    }

    private func submit() {
        guard canSubmit,
              let stop = selectedStop,
              let line = selectedLine,
              let problem = selectedProblem
        else { return }

        let trimmed = description.trimmingCharacters(in: .whitespacesAndNewlines)
        let finalDescription = trimmed.count >= 3 ? trimmed : "Signalement rapide — \(problem.title)"

        isSubmitting = true
        submitError = nil

        Task {
            do {
                _ = try await SignalementService.ajouter(
                    nomArret: stop.name,
                    ligne: line.number,
                    typeProbleme: problem.title,
                    description: finalDescription,
                    latitude: userLatitude,
                    longitude: userLongitude,
                    photo: nil
                )
                UINotificationFeedbackGenerator().notificationOccurred(.success)
                withAnimation(.easeOut(duration: 0.25)) {
                    submitSuccess = true
                    showConfetti = true
                }
                try? await Task.sleep(nanoseconds: 1_400_000_000)
                handleClose()
            } catch {
                UINotificationFeedbackGenerator().notificationOccurred(.error)
                submitError = (error as? APIError)?.errorDescription ?? error.localizedDescription
            }
            isSubmitting = false
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
            .animation(
                .easeIn(duration: duration).delay(delay),
                value: animate
            )
    }
}
