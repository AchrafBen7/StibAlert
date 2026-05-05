import SwiftUI

struct TransitPassSettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @StateObject private var nfcReader = MobibNFCReader()

    let onBack: () -> Void
    let onClose: () -> Void

    @State private var draftPass = TransitPassStorage.load()
    @State private var revealed = false

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    header
                        .padding(.horizontal, 20)
                        .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 20) {
                        TransitPassCardView(pass: previewPass, revealed: revealed) {
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
        .onAppear {
            syncDraftWithSessionNameIfNeeded()
        }
        .onReceive(nfcReader.$lastScan.compactMap { $0 }) { scan in
            draftPass.nfcFingerprint = scan.fingerprint
            draftPass.nfcTagType = scan.tagType
            draftPass.lastScannedAt = scan.scannedAt
            if draftPass.cardNumber.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                draftPass.cardNumber = String(scan.fingerprint.prefix(16))
            }
            save()
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

private struct TransitPassCardView: View {
    let pass: TransitPass
    let revealed: Bool
    let onToggleReveal: () -> Void

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
        ZStack {
            RoundedRectangle(cornerRadius: 14)
                .fill(
                    RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hue: 205/360, saturation: 0.85, brightness: 0.62),
                            Color(hue: 210/360, saturation: 0.80, brightness: 0.50),
                            Color(hue: 215/360, saturation: 0.78, brightness: 0.38)
                        ]),
                        center: UnitPoint(x: 0.30, y: 0.35),
                        startRadius: 10,
                        endRadius: 320
                    )
                )

            GeometryReader { geo in
                let w = geo.size.width
                let h = geo.size.height

                MobibIconPattern()
                    .opacity(0.18)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                MobibWaveShape()
                    .fill(Color.white)
                    .frame(height: h * 0.26)
                    .offset(y: h * 0.74)
                    .clipShape(RoundedRectangle(cornerRadius: 14))

                HStack(spacing: 1) {
                    Text("M")
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(Color(hue: 220/360, saturation: 0.30, brightness: 0.20))
                        .tracking(-1.4)
                    ZStack {
                        Circle()
                            .fill(Color(hue: 355/360, saturation: 0.82, brightness: 0.52))
                            .frame(width: 18, height: 18)
                        Circle()
                            .fill(Color.white)
                            .frame(width: 6, height: 6)
                    }
                    Text("BIB")
                        .font(.system(size: 34, weight: .black))
                        .foregroundColor(.white)
                        .tracking(-1.4)
                }
                .position(x: 50, y: 30)

                Text("STIB · MIVB")
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .tracking(2)
                    .foregroundColor(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
                    .background(Color(hue: 220/360, saturation: 0.80, brightness: 0.32))
                    .rotationEffect(.degrees(-90))
                    .position(x: 16, y: h * 0.55)

                ZStack {
                    RoundedRectangle(cornerRadius: 6)
                        .fill(
                            LinearGradient(
                                gradient: Gradient(colors: [
                                    Color(hue: 45/360, saturation: 0.80, brightness: 0.78),
                                    Color(hue: 40/360, saturation: 0.75, brightness: 0.55),
                                    Color(hue: 32/360, saturation: 0.65, brightness: 0.38)
                                ]),
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                    GoldChipLines()
                        .stroke(Color(hue: 35/360, saturation: 0.55, brightness: 0.25).opacity(0.7), lineWidth: 0.6)
                }
                .frame(width: 52, height: 40)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(Color(hue: 35/360, saturation: 0.50, brightness: 0.30), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.2), radius: 2, y: 1)
                .position(x: 46, y: h * 0.52)

                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(chipNumber)
                            .font(.system(size: 10.5, weight: .medium, design: .monospaced))
                        Text("/")
                            .opacity(0.7)
                            .font(.system(size: 10.5, design: .monospaced))
                    }
                    HStack(spacing: 4) {
                        Text(serialDisplay)
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .underline()
                        Text("/ \(suffixDisplay)")
                            .font(.system(size: 13, weight: .bold, design: .monospaced))
                            .opacity(0.8)
                    }
                }
                .foregroundColor(.white)
                .position(x: 152, y: h * 0.54)

                VStack(alignment: .leading, spacing: 2) {
                    Text(pass.subscriptionLabel.isEmpty ? "ABONNEMENT STIB" : pass.subscriptionLabel.uppercased())
                        .font(.system(size: 9, weight: .bold))
                        .tracking(1.4)
                        .opacity(0.9)
                    Text(holderDisplay)
                        .font(.system(size: 13, weight: .bold))
                        .tracking(0.5)
                }
                .foregroundColor(.white)
                .position(x: 132, y: h * 0.72)

                HStack {
                    HStack(spacing: 3) {
                        Text(".brussels")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                        IrisIcon()
                            .frame(width: 10, height: 9)
                    }
                    .foregroundColor(Color(hue: 220/360, saturation: 0.80, brightness: 0.25))

                    Spacer()

                    HStack(spacing: 8) {
                        Image(systemName: "bus.fill")
                            .font(.system(size: 11))
                        Image(systemName: "tram.fill")
                            .font(.system(size: 11))
                        Text(customerNumber)
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                    }
                    .foregroundColor(Color(hue: 220/360, saturation: 0.80, brightness: 0.25))
                }
                .padding(.horizontal, 14)
                .frame(height: h * 0.20)
                .position(x: w / 2, y: h - (h * 0.10))
            }

            VStack {
                HStack {
                    Spacer()
                    Button(action: onToggleReveal) {
                        Image(systemName: revealed ? "eye.slash" : "eye")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(DS.Color.ink)
                            .frame(width: 32, height: 32)
                            .background(DS.Color.paper.opacity(0.9))
                            .overlay(
                                RoundedRectangle(cornerRadius: 6)
                                    .stroke(DS.Color.ink.opacity(0.30), lineWidth: 1.5)
                            )
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                }
                Spacer()
            }
            .padding(8)
        }
        .aspectRatio(1.586, contentMode: .fit)
        .shadow(color: .black.opacity(0.18), radius: 16, y: 8)
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
