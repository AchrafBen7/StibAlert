import SwiftUI
import CoreLocation
import UIKit
import PhotosUI

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
    @State private var pickerItem: PhotosPickerItem? = nil
    @State private var photo: UIImage? = nil
    @State private var isSubmitting: Bool = false
    @State private var submitError: String? = nil
    @State private var submitSuccess: Bool = false
    @State private var showStopPicker: Bool = false
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

    var body: some View {
        ZStack {
            AppTheme.Palette.overlay
                .ignoresSafeArea()
                .onTapGesture(perform: handleClose)

            sheetContent
                .frame(maxWidth: .infinity)
                .background(
                    AppTheme.Palette.screenElevated
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.xl, style: .continuous))
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
        .onChange(of: pickerItem) { _, newValue in
            guard let newValue else { return }
            Task {
                if let data = try? await newValue.loadTransferable(type: Data.self),
                   let img = UIImage(data: data) {
                    photo = img
                }
            }
        }
        .sheet(isPresented: $showStopPicker) {
            stopPickerSheet
                .presentationDetents([.medium, .large])
                .presentationDragIndicator(.visible)
        }
    }

    private var sheetContent: some View {
        VStack(spacing: 0) {
            handleBar

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    stopSection
                    if !matchingActiveSignalements.isEmpty {
                        activeHereSection
                    }
                    lineSection
                    problemSection
                    detailsAccordion
                    if let submitError {
                        Text(submitError)
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.alert)
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

    // MARK: - Handle

    private var handleBar: some View {
        HStack {
            Spacer()
            Capsule()
                .fill(Color.white.opacity(0.55))
                .frame(width: 44, height: 5)
            Spacer()
        }
        .overlay(alignment: .trailing) {
            Button(action: handleClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                    .frame(width: 30, height: 30)
                    .background(AppTheme.Palette.surfaceMuted)
                    .clipShape(Circle())
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
            sectionTitle(icon: "mappin.and.ellipse", text: "Arrêt")

            Button {
                showStopPicker = true
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "location.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                        .frame(width: 30, height: 30)
                        .background(autoDetectedStop ? AppTheme.Palette.success : AppTheme.Palette.surfaceMuted)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        if isLoadingStops {
                            HStack(spacing: 6) {
                                ProgressView().scaleEffect(0.7)
                                Text("Recherche...")
                                    .font(AppTheme.Fonts.title3)
                                    .foregroundStyle(AppTheme.Palette.textMuted)
                            }
                        } else {
                            Text(selectedStop?.name ?? "Choisir un arrêt")
                                .font(AppTheme.Fonts.title3)
                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                .lineLimit(1)
                        }
                        Text(autoDetectedStop ? "Détecté à proximité" : (isLoadingStops ? "" : "Toucher pour changer"))
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AppTheme.Palette.textMuted)
                }
                .padding(.horizontal, 14)
                .frame(height: AppTheme.ButtonHeight.primary)
                .background(AppTheme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                        .stroke(autoDetectedStop ? AppTheme.Palette.success.opacity(0.45) : AppTheme.Palette.border, lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 18)
    }

    private var stopPickerSheet: some View {
        NavigationStack {
            Group {
                if isLoadingStops {
                    VStack(spacing: 12) {
                        ProgressView()
                        Text("Recherche des arrêts...")
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if nearbyStops.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "mappin.slash")
                            .font(.system(size: 32))
                            .foregroundStyle(AppTheme.Palette.textMuted)
                        Text("Aucun arrêt trouvé à proximité")
                            .font(AppTheme.Fonts.body)
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    VStack(spacing: 0) {
                        HStack(spacing: 10) {
                            Image(systemName: "magnifyingglass")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(AppTheme.Palette.textMuted)

                            TextField(
                                "",
                                text: $stopSearchQuery,
                                prompt: Text("Rechercher un arrêt ou une ligne")
                                    .foregroundStyle(AppTheme.Palette.textMuted)
                            )
                            .font(AppTheme.Fonts.body)
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .textInputAutocapitalization(.words)
                            .autocorrectionDisabled()
                        }
                        .padding(.horizontal, 14)
                        .frame(height: 44)
                        .background(AppTheme.Palette.surface)
                        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        .padding(.horizontal, 16)
                        .padding(.top, 10)
                        .padding(.bottom, 8)

                        List {
                            ForEach(filteredNearbyStops) { stop in
                                Button {
                                    selectedStop = stop
                                    selectedLine = stop.issueLines.first
                                    showStopPicker = false
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading, spacing: 5) {
                                            Text(stop.name)
                                                .font(AppTheme.Fonts.bodyStrong)
                                                .foregroundStyle(AppTheme.Palette.textPrimary)
                                            Text("\(stop.distanceMeters)m · \(stop.lines.count) lignes")
                                                .font(AppTheme.Fonts.caption)
                                                .foregroundStyle(AppTheme.Palette.textSecondary)

                                            ScrollView(.horizontal, showsIndicators: false) {
                                                HStack(spacing: 6) {
                                                    ForEach(Array(stop.lines.prefix(4))) { line in
                                                        Text(line.number)
                                                            .font(AppTheme.Fonts.captionStrong)
                                                            .foregroundStyle(AppTheme.Palette.textOnBrand)
                                                            .frame(width: 28, height: 22)
                                                            .background(line.color)
                                                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))
                                                    }
                                                }
                                            }

                                            if let primaryDirection = stop.issueLines.first?.direction {
                                                Text(primaryDirection)
                                                    .font(AppTheme.Fonts.caption)
                                                    .foregroundStyle(AppTheme.Palette.textSecondary)
                                                    .lineLimit(2)
                                            }
                                        }
                                        Spacer()
                                        if selectedStop?.id == stop.id {
                                            Image(systemName: "checkmark")
                                                .foregroundStyle(AppTheme.Palette.success)
                                        }
                                    }
                                }
                                .listRowBackground(AppTheme.Palette.screen)
                            }
                        }
                        .listStyle(.plain)
                    }
                }
            }
            .background(AppTheme.Palette.screen)
            .navigationTitle("Changer d'arrêt")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
    }

    // MARK: - Lines

    private var lineSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "tram.fill", text: "Ligne")

            if let stop = selectedStop, !stop.issueLines.isEmpty {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(stop.issueLines) { line in
                            lineChip(line)
                        }
                    }
                    .padding(.horizontal, 18)
                }
            } else {
                Text("Sélectionnez un arrêt pour voir les lignes")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textMuted)
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
            HStack(spacing: 6) {
                Text(line.number)
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(line.lineTextColor)
                    .frame(width: 26, height: 26)
                    .background(line.color)
                    .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

                Text(line.direction)
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                    .lineLimit(1)
            }
            .padding(.horizontal, 10)
            .frame(height: AppTheme.ButtonHeight.secondary)
            .background(isSelected ? AppTheme.Palette.surfaceElevated : AppTheme.Palette.surface)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                    .stroke(isSelected ? AppTheme.Palette.info : Color.clear, lineWidth: 1.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Problems

    private var problemSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            sectionTitle(icon: "exclamationmark.triangle.fill", text: "Type de problème")

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
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(type.title)
                        .font(AppTheme.Fonts.bodyStrong)
                        .foregroundStyle(AppTheme.Palette.textOnBrand)
                    Spacer()
                    Circle()
                        .fill(type.accentColor)
                        .frame(width: 10, height: 10)
                }
                Text(type.descriptionLines.first ?? "")
                    .font(AppTheme.Fonts.caption)
                    .foregroundStyle(AppTheme.Palette.textOnBrand.opacity(0.78))
                    .lineLimit(1)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, minHeight: 74, alignment: .topLeading)
            .background(type.backgroundColor)
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous)
                    .stroke(Color.white.opacity(isSelected ? 0.85 : 0), lineWidth: 2)
            )
            .scaleEffect(isSelected ? 0.98 : 1)
            .animation(.easeInOut(duration: 0.15), value: isSelected)
        }
        .buttonStyle(.plain)
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
            Text(signalement.ligne)
                .font(AppTheme.Fonts.captionStrong)
                .foregroundStyle(AppTheme.Palette.textOnBrand)
                .frame(width: 30, height: 30)
                .background(AppTheme.Palette.warning)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.sm, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                Text(signalement.typeProbleme)
                    .font(AppTheme.Fonts.captionStrong)
                    .foregroundStyle(AppTheme.Palette.textPrimary)
                HStack(spacing: 6) {
                    Text(relativeTime(from: signalement.dateSignalement))
                        .font(AppTheme.Fonts.caption)
                        .foregroundStyle(AppTheme.Palette.textSecondary)
                    if confirmations > 0 {
                        Text("· \(confirmations) confirmé·e")
                            .font(AppTheme.Fonts.caption)
                            .foregroundStyle(AppTheme.Palette.textSecondary)
                    }
                }
            }

            Spacer()

            Button(action: { confirmExisting(signalement) }) {
                HStack(spacing: 4) {
                    if isConfirming {
                        ProgressView().tint(AppTheme.Palette.textOnBrand).scaleEffect(0.7)
                    } else {
                        Image(systemName: "checkmark")
                            .font(.system(size: 11, weight: .semibold))
                    }
                    Text("Confirmer")
                        .font(AppTheme.Fonts.captionStrong)
                }
                .foregroundStyle(AppTheme.Palette.textOnBrand)
                .padding(.horizontal, 10)
                .frame(height: AppTheme.ButtonHeight.secondary)
                .background(AppTheme.Palette.brandStrong)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(confirmingExistingId != nil)
            .accessibilityLabel("Confirmer ce signalement")
            .accessibilityHint("Ajoute votre confirmation à ce problème déjà signalé.")
        }
        .padding(10)
        .background(AppTheme.Palette.surface)
        .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
    }

    // MARK: - Details

    private var detailsAccordion: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                withAnimation(.spring(response: 0.35, dampingFraction: 0.85)) {
                    detailsExpanded.toggle()
                }
            } label: {
                HStack {
                    Image(systemName: "text.badge.plus")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Ajouter des détails (optionnel)")
                        .font(AppTheme.Fonts.captionStrong)
                    Spacer()
                    Image(systemName: detailsExpanded ? "chevron.up" : "chevron.down")
                        .font(.system(size: 12, weight: .semibold))
                }
                .foregroundStyle(AppTheme.Palette.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: AppTheme.ButtonHeight.secondary)
                .background(AppTheme.Palette.surface)
                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(detailsExpanded ? "Masquer les détails optionnels" : "Afficher les détails optionnels")
            .accessibilityHint("Permet d'ajouter une description ou une photo au signalement.")

            if detailsExpanded {
                VStack(spacing: 10) {
                    ZStack(alignment: .topLeading) {
                        TextEditor(text: $description)
                            .scrollContentBackground(.hidden)
                            .frame(minHeight: 90)
                            .padding(10)
                            .background(AppTheme.Palette.surface)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .font(AppTheme.Fonts.body)
                        if description.isEmpty {
                            Text("Ex : Tram bloqué depuis 5 min au feu.")
                                .font(AppTheme.Fonts.body)
                                .foregroundStyle(AppTheme.Palette.textMuted)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 18)
                                .allowsHitTesting(false)
                        }
                    }

                    HStack(spacing: 10) {
                        PhotosPicker(selection: $pickerItem, matching: .images) {
                            HStack(spacing: 6) {
                                Image(systemName: photo == nil ? "camera.fill" : "photo.fill")
                                    .font(.system(size: 12, weight: .semibold))
                                Text(photo == nil ? "Ajouter une photo" : "Changer de photo")
                                    .font(AppTheme.Fonts.captionStrong)
                            }
                            .foregroundStyle(AppTheme.Palette.textPrimary)
                            .padding(.horizontal, 12)
                            .frame(height: 38)
                            .background(AppTheme.Palette.surfaceMuted)
                            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                        }
                        .accessibilityLabel(photo == nil ? "Ajouter une photo" : "Changer la photo")
                        .accessibilityHint("Ajoute une photo au signalement pour donner plus de contexte.")

                        if let photo {
                            Image(uiImage: photo)
                                .resizable()
                                .scaledToFill()
                                .frame(width: 38, height: 38)
                                .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous))
                                .overlay(
                                    RoundedRectangle(cornerRadius: AppTheme.Radius.md, style: .continuous)
                                        .stroke(AppTheme.Palette.borderStrong, lineWidth: 1)
                                )
                            Button(action: { self.photo = nil; self.pickerItem = nil }) {
                                Image(systemName: "xmark.circle.fill")
                                    .font(.system(size: 16))
                                    .foregroundStyle(AppTheme.Palette.textSecondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Supprimer la photo")
                            .accessibilityHint("Retire la photo sélectionnée du signalement.")
                        }

                        Spacer()
                    }
                }
            }
        }
        .padding(.horizontal, 18)
    }

    // MARK: - Submit bar

    private var submitBar: some View {
        Button(action: submit) {
            HStack(spacing: 10) {
                if isSubmitting {
                    ProgressView().tint(.black)
                } else if submitSuccess {
                    Image(systemName: "checkmark").font(.system(size: 18, weight: .bold))
                    Text("Envoyé")
                } else {
                    Image(systemName: "paperplane.fill").font(.system(size: 14, weight: .semibold))
                    Text("Envoyer signalement")
                }
            }
            .font(AppTheme.Fonts.bodyStrong)
            .foregroundStyle(canSubmit || submitSuccess ? AppTheme.Palette.textOnBrand : AppTheme.Palette.textOnBrand.opacity(0.4))
            .frame(maxWidth: .infinity)
            .frame(height: AppTheme.ButtonHeight.primary)
            .background(canSubmit || submitSuccess ? AppTheme.Palette.brand : AppTheme.Palette.brand.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: AppTheme.Radius.lg, style: .continuous))
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
                .foregroundStyle(AppTheme.Palette.textMuted)
            Text(text.uppercased())
                .font(AppTheme.Fonts.captionStrong)
                .foregroundStyle(AppTheme.Palette.textMuted)
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
                    photo: photo
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
