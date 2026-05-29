import SwiftUI
import PassKit

struct TransitPassSettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @StateObject private var nfcReader = MobibNFCReader()

    let onBack: () -> Void
    let onClose: () -> Void

    @State private var draftPass = TransitPassStorage.load()
    @State private var revealed = false
    @State private var detectionFlashOpacity: Double = 0
    @State private var pendingPassData: Data?
    @State private var isFetchingWalletPass = false
    @State private var walletErrorMessage: String?

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 20) {
                        TransitPassCardView(
                            pass: previewPass,
                            revealed: revealed,
                            validity: cardValidity,
                            isScanning: nfcReader.isScanning,
                            flashOpacity: detectionFlashOpacity
                        ) {
                            revealed.toggle()
                        }

                        HStack(spacing: 8) {
                            TransitMetaCell(label: "Type", value: "Personnelle")
                            TransitMetaCell(label: "Émise", value: issuedAtLabel)
                            TransitMetaCell(label: "Statut", value: previewPass.statusLabel, accent: true)
                        }

                        scanStateBanner

                        if shouldShowManualCompletionHint {
                            manualCompletionHint
                        }

                        sectionGroup(title: "Actions") {
                            TransitActionRow(
                                icon: nfcReader.isScanning ? "dot.radiowaves.left.and.right" : "wave.3.right.circle.fill",
                                label: nfcReader.isScanning ? "Lecture NFC en cours" : "Scanner en NFC",
                                value: previewPass.lastScannedAt.map(relativeDateText),
                                action: { nfcReader.beginScan() }
                            )
                            ProfileSettingsDivider()
                            if PKPassLibrary.isPassLibraryAvailable() {
                                TransitActionRow(
                                    icon: isFetchingWalletPass ? "hourglass" : "wallet.pass.fill",
                                    label: walletButtonLabel,
                                    value: nil,
                                    action: { Task { await addToAppleWallet() } }
                                )
                                .disabled(!canAddToWallet || isFetchingWalletPass)
                                .opacity(canAddToWallet ? 1 : 0.5)
                                ProfileSettingsDivider()
                            }
                            TransitActionRow(
                                icon: "arrow.counterclockwise",
                                label: "Réinitialiser la carte",
                                value: nil,
                                action: {
                                    draftPass = .empty
                                    syncDraftWithSessionNameIfNeeded()
                                    save()
                                }
                            )
                        }

                        if let walletErrorMessage {
                            Text(walletErrorMessage)
                                .font(DS.Font.bodySmall)
                                .foregroundStyle(DS.Color.statusMajor)
                                .padding(.horizontal, 4)
                                .transition(.opacity)
                        }

                        infoSection
                        formSection
                        debugSection

                        Text("MOBIB · STIB-MIVB · BRUXELLES")
                            .font(DS.Font.monoSmall)
                            .tracking(2)
                            .foregroundColor(DS.Color.inkMute)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 96)
                }
            }
        }
        .modifier(PaperGrainBackground())
        .sheet(item: Binding(
            get: { pendingPassData.map { WalletPassPayload(data: $0) } },
            set: { newValue in pendingPassData = newValue?.data }
        )) { payload in
            AddPassToWalletSheet(passData: payload.data) { result in
                pendingPassData = nil
                if case .failure(let error) = result {
                    walletErrorMessage = error.localizedDescription
                } else {
                    walletErrorMessage = nil
                }
            }
        }
        .onAppear {
            syncDraftWithSessionNameIfNeeded()
        }
        .onReceive(nfcReader.$lastScan.compactMap { $0 }) { scan in
            // Store the NFC fingerprint separately from cardNumber. We used to
            // auto-fill cardNumber with the UID, but that's confusing — the UID
            // is the chip identifier, not the human-readable serial printed on
            // the card. The user enters the printed number themselves.
            draftPass.nfcFingerprint = scan.fingerprint
            draftPass.nfcTagType = scan.tagType
            draftPass.lastScannedAt = scan.scannedAt
            save()
            triggerDetectionFeedback(isPartial: scan.isPartial)
        }
    }

    /// Flash + haptic the moment a card is detected so the user can tell at
    /// a glance the scan landed. Success haptic for a clean read, warning
    /// haptic for a partial.
    private func triggerDetectionFeedback(isPartial: Bool) {
        UINotificationFeedbackGenerator()
            .notificationOccurred(isPartial ? .warning : .success)

        withAnimation(.easeOut(duration: 0.18)) {
            detectionFlashOpacity = 0.55
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.18) {
            withAnimation(.easeOut(duration: 0.65)) {
                detectionFlashOpacity = 0
            }
        }
    }

    private var cardValidity: TransitCardValidity {
        TransitCardValidity.from(expiryDate: draftPass.expiryDate)
    }

    /// C1 fix : avant on lisait `previewPass.holderName` qui a un fallback
    /// "Titulaire" si vide → le bouton s'activait même si draftPass.holderName
    /// ET session.currentUser?.nom étaient vides, donnant un Wallet pass
    /// rejected par Apple. Désormais on vérifie strictement le draft fourni
    /// par l'utilisateur ET on signale via walletValidationIssue ce qui
    /// manque.
    /// C3 fix : si le scan NFC a renvoyé un état "partial", on bloque aussi
    /// la création du pass — l'utilisateur doit compléter manuellement
    /// avant.
    private var canAddToWallet: Bool { walletValidationIssue == nil }

    /// Première raison qui empêche d'ajouter le pass (ordre de priorité).
    /// nil quand tout est OK. Affiché dans walletButtonLabel + en hint
    /// statusBanner sous le bouton.
    private var walletValidationIssue: WalletValidationIssue? {
        if !PKPassLibrary.isPassLibraryAvailable() {
            return .walletUnavailable
        }
        if case .partial = nfcReader.scanState {
            return .nfcPartial
        }
        let trimmedCard = draftPass.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedCard.isEmpty { return .missingCardNumber }
        if trimmedCard.count < 8 { return .invalidCardNumber }
        let trimmedName = draftPass.holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        // Pour le name : on accepte le fallback session.currentUser.nom si
        // pas vide. Le "Titulaire" générique reste rejeté.
        if trimmedName.isEmpty {
            let sessionName = (session.currentUser?.nom ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if sessionName.isEmpty { return .missingHolderName }
        }
        return nil
    }

    enum WalletValidationIssue {
        case walletUnavailable
        case nfcPartial
        case missingCardNumber
        case invalidCardNumber
        case missingHolderName

        var userMessage: String {
            switch self {
            case .walletUnavailable:  return "Apple Wallet n'est pas disponible sur cet appareil."
            case .nfcPartial:         return "Le scan NFC est incomplet — complète les infos manuellement."
            case .missingCardNumber:  return "Saisis le numéro de la carte MoBIB."
            case .invalidCardNumber:  return "Le numéro de carte semble trop court."
            case .missingHolderName:  return "Indique le nom du titulaire."
            }
        }
    }

    private var walletButtonLabel: String {
        if isFetchingWalletPass { return "Génération du pass…" }
        if let issue = walletValidationIssue { return issue.userMessage }
        return "Ajouter à Apple Wallet"
    }

    @MainActor
    private func addToAppleWallet() async {
        guard !isFetchingWalletPass else { return }
        walletErrorMessage = nil
        isFetchingWalletPass = true
        defer { isFetchingWalletPass = false }

        do {
            let data = try await WalletPassService.fetchMobibPass(from: draftPass)
            pendingPassData = data
        } catch {
            walletErrorMessage = error.localizedDescription
            ErrorReporting.capture(error, tag: "wallet.fetchPass")
        }
    }

    private var previewPass: TransitPass {
        var pass = draftPass
        if pass.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            pass.holderName = session.currentUser?.nom ?? "Titulaire"
        }
        return pass
    }

    private var issuedAtLabel: String {
        let date = previewPass.lastScannedAt ?? Date()
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.dateFormat = "MM / yyyy"
        return formatter.string(from: date)
    }

    private var scanStateBanner: some View {
        let state = nfcReader.scanState
        return statusBanner(
            icon: state.icon,
            title: state.title,
            message: state.message,
            accent: Color(hex: state.accentHex)
        )
    }

    private var shouldShowManualCompletionHint: Bool {
        if case .partial = nfcReader.scanState { return true }
        return draftPass.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || draftPass.expiryDate == nil
    }

    private var header: some View {
        HStack(alignment: .top) {
            Button(action: onBack) {
                Image(systemName: "arrow.left")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: DS.Stroke.thick)
                    )
            }
            .buttonStyle(ProfileRootRowPressableStyle())

            VStack(alignment: .leading, spacing: 8) {
                Text("Carte de transport")
                    .eyebrow()
                Text("Ma carte STIB")
                    .font(DS.Font.displayH2)
                    .foregroundStyle(DS.Color.ink)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(DS.Color.ink)
                    .frame(width: 36, height: 36)
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md)
                            .stroke(DS.Color.ink.opacity(0.2), lineWidth: DS.Stroke.thick)
                    )
            }
            .buttonStyle(ProfileRootRowPressableStyle())
        }
    }

    private var manualCompletionHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(DS.Color.statusMinor)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Compléter manuellement")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Text("Si le scan ne remonte pas toutes les données, ajoute au minimum le numéro visible et la date d’expiration.")
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.statusMinor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(DS.Color.statusMinor.opacity(0.32), lineWidth: DS.Stroke.hairline)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private var infoSection: some View {
        sectionGroup(title: "Association") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Le scan NFC rattache la carte physique au profil et évite les erreurs de saisie. Oriente la carte lentement autour du haut de l’iPhone.")
                    .font(.system(size: 12.5))
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                Text("Si certaines informations ne remontent pas, tu peux compléter le formulaire manuellement.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var formSection: some View {
        sectionGroup(title: "Détails de la carte") {
            VStack(spacing: 14) {
                formField(title: "Titulaire") {
                    TextField("Nom complet", text: binding(\.holderName))
                        .textInputAutocapitalization(.words)
                }

                formField(title: "Abonnement") {
                    TextField("Ex: Abonnement annuel", text: binding(\.subscriptionLabel))
                        .textInputAutocapitalization(.words)
                }

                formField(title: "Numéro de carte") {
                    TextField("6396 5320 0000 0000", text: binding(\.cardNumber))
                        .keyboardType(.numbersAndPunctuation)
                        .textInputAutocapitalization(.never)
                }

                formField(title: "Expiration") {
                    DatePicker(
                        "",
                        selection: Binding(
                            get: { draftPass.expiryDate ?? Calendar.current.date(byAdding: .year, value: 1, to: Date()) ?? Date() },
                            set: {
                                draftPass.expiryDate = $0
                                save()
                            }
                        ),
                        displayedComponents: .date
                    )
                    .labelsHidden()
                    .datePickerStyle(.compact)
                    .tint(DS.Color.ink)
                }

                if let fingerprint = draftPass.nfcFingerprint, !fingerprint.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Empreinte NFC")
                            .font(DS.Font.monoSmall.weight(.semibold))
                            .foregroundStyle(DS.Color.inkMute)

                        Text(fingerprint)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.inkSoft)
                            .textSelection(.enabled)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(14)
                    .background(DS.Color.paper2.opacity(0.45))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.lg)
                            .stroke(DS.Color.ink.opacity(0.1), lineWidth: DS.Stroke.hairline)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                }
            }
            .padding(16)
        }
    }

    private var debugSection: some View {
        sectionGroup(title: "Diagnostic NFC") {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("Journal de lecture")
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)

                    Spacer()

                    if !nfcReader.debugEvents.isEmpty {
                        Button {
                            nfcReader.clearDebugLog()
                        } label: {
                            Text("Effacer")
                                .font(DS.Font.monoSmall.weight(.semibold))
                                .foregroundStyle(DS.Color.primary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                if nfcReader.debugEvents.isEmpty {
                    Text("Les évènements NFC apparaîtront ici pendant vos tests sur iPhone.")
                        .font(.system(size: 12))
                        .foregroundStyle(DS.Color.inkMute)
                } else {
                    VStack(spacing: 10) {
                        ForEach(nfcReader.debugEvents) { event in
                            HStack(alignment: .top, spacing: 10) {
                                Text(event.level)
                                    .font(DS.Font.monoSmall.weight(.semibold))
                                    .foregroundStyle(DS.Color.primary)
                                    .frame(width: 54, alignment: .leading)

                                VStack(alignment: .leading, spacing: 3) {
                                    Text(event.message)
                                        .font(.system(size: 11.5))
                                        .foregroundStyle(DS.Color.ink)
                                        .fixedSize(horizontal: false, vertical: true)
                                    Text(relativeDateText(from: event.date))
                                        .font(DS.Font.caption)
                                        .foregroundStyle(DS.Color.inkMute)
                                }

                                Spacer()
                            }
                            .padding(12)
                            .background(DS.Color.paper2.opacity(0.45))
                            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    private func statusBanner(icon: String, title: String, message: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Text(message)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg)
                .stroke(accent.opacity(0.35), lineWidth: DS.Stroke.thick)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
    }

    private func formField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(DS.Font.monoSmall.weight(.semibold))
                .foregroundStyle(DS.Color.inkMute)

            content()
                .font(DS.Font.body)
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: DS.Stroke.hairline)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg))
        }
    }

    @ViewBuilder
    private func sectionGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.Font.monoSmall.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(DS.Color.inkMute)
                .padding(.leading, 4)

            VStack(spacing: 0) { content() }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: DS.Stroke.thick)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }

    private func binding(_ keyPath: WritableKeyPath<TransitPass, String>) -> Binding<String> {
        Binding(
            get: { draftPass[keyPath: keyPath] },
            set: {
                draftPass[keyPath: keyPath] = $0
                save()
            }
        )
    }

    private func save() {
        TransitPassStorage.save(draftPass)
    }

    private func syncDraftWithSessionNameIfNeeded() {
        guard draftPass.holderName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        draftPass.holderName = session.currentUser?.nom ?? ""
        save()
    }

    private func relativeDateText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLocale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct WalletPassPayload: Identifiable {
    let data: Data
    var id: Int { data.hashValue }
}

enum TransitCardValidity {
    case noExpiry
    case valid(daysLeft: Int)
    case expiringSoon(daysLeft: Int)
    case expired(daysAgo: Int)

    static func from(expiryDate: Date?) -> TransitCardValidity {
        guard let expiry = expiryDate else { return .noExpiry }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let target = calendar.startOfDay(for: expiry)
        let days = calendar.dateComponents([.day], from: now, to: target).day ?? 0
        if days < 0 { return .expired(daysAgo: -days) }
        if days <= 30 { return .expiringSoon(daysLeft: days) }
        return .valid(daysLeft: days)
    }

    var label: String {
        switch self {
        case .noExpiry: return "À COMPLÉTER"
        case .valid(let days):
            if days >= 365 { return "VALIDE" }
            return "VALIDE · \(days) j"
        case .expiringSoon(let days):
            if days == 0 { return "EXPIRE AUJOURD'HUI" }
            if days == 1 { return "EXPIRE DEMAIN" }
            return "EXPIRE DANS \(days) j"
        case .expired(let days):
            if days == 0 { return "EXPIRÉE AUJOURD'HUI" }
            return "EXPIRÉE · -\(days) j"
        }
    }

    var color: Color {
        switch self {
        case .noExpiry: return DS.Color.inkMute
        case .valid: return DS.Color.statusOK
        case .expiringSoon: return DS.Color.statusMinor
        case .expired: return DS.Color.statusMajor
        }
    }
}

private struct TransitPassCardView: View {
    let pass: TransitPass
    let revealed: Bool
    let validity: TransitCardValidity
    let isScanning: Bool
    let flashOpacity: Double
    let onToggleReveal: () -> Void

    /// True when the user hasn't scanned or filled anything yet — we render
    /// a dedicated empty placeholder instead of a half-populated mock card.
    private var isEmptyState: Bool {
        pass.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && pass.lastScannedAt == nil
    }

    private var chipNumber: String {
        let digits = pass.cardNumber.filter(\.isNumber)
        let prefix = String(digits.prefix(6))
        if prefix.isEmpty { return "••••••" }
        return revealed ? prefix : "••••••"
    }

    private var serialDisplay: String {
        let raw = pass.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !raw.isEmpty else { return "•••• •••• ••••" }
        return revealed ? raw : pass.maskedCardNumber
    }

    private var holderDisplay: String {
        let value = pass.holderName.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? "TITULAIRE" : value.uppercased()
    }

    private var suffixDisplay: String {
        let digits = pass.cardNumber.filter(\.isNumber)
        return revealed && !digits.isEmpty ? String(digits.suffix(1)) : "•"
    }

    private var customerNumber: String {
        let digits = pass.cardNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return "1 123 456 789" }
        let padded = String(digits.prefix(9)).padding(toLength: 9, withPad: "0", startingAt: 0)
        return "1 \(padded.prefix(3)) \(padded.dropFirst(3).prefix(3)) \(padded.suffix(3))"
    }

    var body: some View {
        if isEmptyState {
            emptyStateCard
        } else {
            populatedCard
        }
    }

    private var emptyStateCard: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 18)
                .fill(DS.Color.paper2)
                .overlay(
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(
                            style: StrokeStyle(lineWidth: 1.5, dash: [8, 6])
                        )
                        .foregroundStyle(DS.Color.ink.opacity(0.22))
                )

            VStack(spacing: 14) {
                Image(systemName: "creditcard.viewfinder")
                    .font(.system(size: 38, weight: .light))
                    .foregroundStyle(DS.Color.inkMute)
                Text("Aucune carte enregistrée")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Text("Scanne ta MoBIB en NFC ou complète\nmanuellement les champs ci-dessous.")
                    .font(.system(size: 12))
                    .foregroundStyle(DS.Color.inkSoft)
                    .multilineTextAlignment(.center)
            }
            .padding(20)

            if isScanning {
                ScanRippleOverlay()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }
        }
        .aspectRatio(1.586, contentMode: .fit)
    }

    private var populatedCard: some View {
        ZStack(alignment: .topLeading) {
            // MoBIB green gradient — echoes the physical card without
            // photocopying its busy "M" pattern. Editorial clean look.
            RoundedRectangle(cornerRadius: 18)
                .fill(
                    LinearGradient(
                        colors: [
                            Color(red: 0.50, green: 0.72, blue: 0.39), // MoBIB green light
                            Color(red: 0.36, green: 0.58, blue: 0.28), // MoBIB green deep
                        ],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .overlay(
                    // A single thin orange hairline near the bottom — Brussels
                    // accent without screaming. Matches DS.Color.primary.
                    RoundedRectangle(cornerRadius: 18)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )

            // Diagonal sweep highlight — premium pass feel.
            GeometryReader { geo in
                Path { p in
                    p.move(to: CGPoint(x: -20, y: geo.size.height * 0.30))
                    p.addLine(to: CGPoint(x: geo.size.width + 20, y: -10))
                    p.addLine(to: CGPoint(x: geo.size.width + 20, y: geo.size.height * 0.04))
                    p.addLine(to: CGPoint(x: -20, y: geo.size.height * 0.42))
                    p.closeSubpath()
                }
                .fill(Color.white.opacity(0.05))
            }
            .clipShape(RoundedRectangle(cornerRadius: 18))
            .allowsHitTesting(false)

            // Header row : eyebrow + validity + reveal toggle
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("MOBIB · STIB-MIVB")
                            .font(.system(size: 9, weight: .bold, design: .monospaced))
                            .tracking(1.6)
                            .foregroundStyle(Color.white.opacity(0.55))
                        Text("MoBIB")
                            .font(.custom("DelaGothicOne-Regular", size: 28))
                            .foregroundStyle(.white)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 6) {
                        ValidityBadge(validity: validity)
                        Button(action: onToggleReveal) {
                            Image(systemName: revealed ? "eye.slash" : "eye")
                                .font(.system(size: 12, weight: .semibold))
                                .foregroundColor(.white)
                                .frame(width: 28, height: 28)
                                .background(Color.white.opacity(0.10))
                                .overlay(
                                    Circle().stroke(Color.white.opacity(0.18), lineWidth: 1)
                                )
                                .clipShape(Circle())
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()

                // Subscription label + holder name
                VStack(alignment: .leading, spacing: 4) {
                    Text((pass.subscriptionLabel.isEmpty ? "Abonnement STIB" : pass.subscriptionLabel).uppercased())
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(Color(red: 1.0, green: 0.49, blue: 0.13)) // DS.Color.primary tint
                    Text(holderDisplay)
                        .font(.system(size: 19, weight: .bold))
                        .tracking(0.4)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }

                Spacer().frame(height: 12)

                // Card number row
                HStack(alignment: .bottom) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("NUMÉRO CARTE")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(serialDisplay)
                            .font(.system(size: 14, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                            .lineLimit(1)
                            .minimumScaleFactor(0.6)
                    }
                    Spacer()
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("CLIENT")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(1.4)
                            .foregroundStyle(Color.white.opacity(0.45))
                        Text(customerNumber)
                            .font(.system(size: 12, weight: .medium, design: .monospaced))
                            .foregroundStyle(.white)
                    }
                }
            }
            .padding(18)

            // Ripple overlay during NFC scan — communicates "we're listening
            // for your card" without taking over the UI.
            if isScanning {
                ScanRippleOverlay()
                    .allowsHitTesting(false)
                    .clipShape(RoundedRectangle(cornerRadius: 18))
            }

            // Quick white flash on detection — works in tandem with the
            // success/warning haptic to give the user a clean "got it" cue.
            Color.white
                .opacity(flashOpacity)
                .clipShape(RoundedRectangle(cornerRadius: 18))
                .allowsHitTesting(false)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
    }
}

private struct ValidityBadge: View {
    let validity: TransitCardValidity

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(validity.color)
                .frame(width: 6, height: 6)
            Text(validity.label)
                .font(.system(size: 9, weight: .black, design: .monospaced))
                .tracking(1.0)
                .foregroundColor(.white)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(Color.black.opacity(0.38))
        .overlay(
            Capsule().stroke(validity.color.opacity(0.7), lineWidth: 1)
        )
        .clipShape(Capsule())
    }
}

private struct ScanRippleOverlay: View {
    @State private var animate = false

    var body: some View {
        ZStack {
            // Two staggered rings centered on the chip area so it reads as
            // "the iPhone is listening near the top of the card", matching
            // how MoBIB cards get tapped on the device.
            ForEach(0..<2, id: \.self) { index in
                Circle()
                    .stroke(Color.white.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 90, height: 90)
                    .scaleEffect(animate ? 2.2 : 0.6)
                    .opacity(animate ? 0 : 1)
                    .animation(
                        .easeOut(duration: 1.6)
                            .repeatForever(autoreverses: false)
                            .delay(Double(index) * 0.55),
                        value: animate
                    )
            }
            Circle()
                .fill(Color.white.opacity(0.10))
                .frame(width: 72, height: 72)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .onAppear { animate = true }
    }
}

private struct TransitMetaCell: View {
    let label: String
    let value: String
    var accent: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased())
                .font(DS.Font.monoSmall)
                .tracking(1.5)
                .foregroundColor(accent ? DS.Color.paper.opacity(0.7) : DS.Color.inkMute)
            Text(value)
                .font(.system(size: 12.5, weight: .bold))
                .foregroundColor(accent ? DS.Color.paper : DS.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(accent ? DS.Color.ink : DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(accent ? DS.Color.ink : DS.Color.ink.opacity(0.15), lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }
}

private struct TransitActionRow: View {
    let icon: String
    let label: String
    let value: String?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(DS.Color.ink)
                    .frame(width: 18)
                Text(label)
                    .font(.system(size: 13.5, weight: .medium))
                    .foregroundColor(DS.Color.ink)
                Spacer()
                if let value {
                    Text(value)
                        .font(DS.Font.mono)
                        .foregroundColor(DS.Color.inkMute)
                }
                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(DS.Color.inkMute.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRootRowPressableStyle())
    }
}

private struct ProfileSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Color.ink.opacity(0.12))
            .frame(height: 1)
    }
}

private struct ProfileRootRowPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.paper2 : DS.Color.paper)
    }
}

private struct MobibWaveShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let topY = rect.height * 0.31
        p.move(to: CGPoint(x: 0, y: topY))
        p.addQuadCurve(
            to: CGPoint(x: rect.width * 0.5, y: rect.height * 0.20),
            control: CGPoint(x: rect.width * 0.25, y: 0)
        )
        p.addQuadCurve(
            to: CGPoint(x: rect.width, y: rect.height * 0.26),
            control: CGPoint(x: rect.width * 0.75, y: rect.height * 0.40)
        )
        p.addLine(to: CGPoint(x: rect.width, y: rect.height))
        p.addLine(to: CGPoint(x: 0, y: rect.height))
        p.closeSubpath()
        return p
    }
}

private struct GoldChipLines: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        let r = rect.insetBy(dx: 3, dy: 3)
        p.addRoundedRect(in: r, cornerSize: CGSize(width: 3, height: 3))
        let midX1 = rect.width * 0.40
        let midX2 = rect.width * 0.62
        p.move(to: CGPoint(x: 3, y: rect.height * 0.35))
        p.addLine(to: CGPoint(x: midX1, y: rect.height * 0.35))
        p.move(to: CGPoint(x: 3, y: rect.height * 0.65))
        p.addLine(to: CGPoint(x: midX1, y: rect.height * 0.65))
        p.move(to: CGPoint(x: midX2, y: rect.height * 0.35))
        p.addLine(to: CGPoint(x: rect.width - 3, y: rect.height * 0.35))
        p.move(to: CGPoint(x: midX2, y: rect.height * 0.65))
        p.addLine(to: CGPoint(x: rect.width - 3, y: rect.height * 0.65))
        p.move(to: CGPoint(x: midX1, y: 3))
        p.addLine(to: CGPoint(x: midX1, y: rect.height - 3))
        p.move(to: CGPoint(x: midX2, y: 3))
        p.addLine(to: CGPoint(x: midX2, y: rect.height - 3))
        let centerRect = CGRect(x: midX1, y: rect.height * 0.35, width: midX2 - midX1, height: rect.height * 0.30)
        p.addRect(centerRect)
        return p
    }
}

private struct IrisIcon: View {
    var body: some View {
        Canvas { ctx, size in
            var p = Path()
            let w = size.width
            let h = size.height
            p.move(to: CGPoint(x: w * 0.5, y: h * 0.95))
            p.addLine(to: CGPoint(x: w * 0.1, y: h * 0.50))
            p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.30), radius: w * 0.22, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: true)
            p.addArc(center: CGPoint(x: w * 0.5, y: h * 0.30), radius: w * 0.22, startAngle: .degrees(0), endAngle: .degrees(180), clockwise: false)
            p.closeSubpath()
            ctx.fill(p, with: .color(Color(hue: 355/360, saturation: 0.82, brightness: 0.52)))
        }
    }
}

private struct MobibIconPattern: View {
    var body: some View {
        Canvas { ctx, size in
            let tile: CGFloat = 56
            let cols = Int(ceil(size.width / tile)) + 1
            let rows = Int(ceil(size.height / tile)) + 1
            for r in 0..<rows {
                for c in 0..<cols {
                    let x = CGFloat(c) * tile
                    let y = CGFloat(r) * tile
                    drawTile(in: &ctx, origin: CGPoint(x: x, y: y))
                }
            }
        }
    }

    private func drawTile(in ctx: inout GraphicsContext, origin: CGPoint) {
        let white = Color.white.opacity(0.95)
        let mRect = CGRect(x: origin.x + 40, y: origin.y + 6, width: 12, height: 12)
        ctx.draw(Text("M").font(.system(size: 10, weight: .black)).foregroundColor(white), in: mRect)

        var umbrella = Path()
        umbrella.addArc(center: CGPoint(x: origin.x + 13, y: origin.y + 12), radius: 5, startAngle: .degrees(180), endAngle: .degrees(0), clockwise: false)
        umbrella.move(to: CGPoint(x: origin.x + 13, y: origin.y + 12))
        umbrella.addLine(to: CGPoint(x: origin.x + 13, y: origin.y + 18))
        ctx.stroke(umbrella, with: .color(white), lineWidth: 0.8)

        var bike = Path()
        bike.addEllipse(in: CGRect(x: origin.x + 6, y: origin.y + 32, width: 6, height: 6))
        bike.addEllipse(in: CGRect(x: origin.x + 16, y: origin.y + 32, width: 6, height: 6))
        ctx.stroke(bike, with: .color(white), lineWidth: 0.7)

        var bag = Path()
        bag.addRoundedRect(in: CGRect(x: origin.x + 30, y: origin.y + 8, width: 8, height: 9), cornerSize: CGSize(width: 1, height: 1))
        ctx.stroke(bag, with: .color(white), lineWidth: 0.7)

        var cup = Path()
        cup.addRoundedRect(in: CGRect(x: origin.x + 30, y: origin.y + 32, width: 7, height: 8), cornerSize: CGSize(width: 1, height: 1))
        ctx.stroke(cup, with: .color(white), lineWidth: 0.7)
    }
}
