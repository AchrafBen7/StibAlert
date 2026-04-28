import SwiftUI

struct TransitPassSettingsView: View {
    @EnvironmentObject private var session: AuthSession
    @StateObject private var nfcReader = MobibNFCReader()

    let onBack: () -> Void
    let onClose: () -> Void

    @State private var draftPass = TransitPassStorage.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 21)
                .padding(.top, 12)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 18) {
                    TransitPassCardView(pass: previewPass)
                        .padding(.top, 24)

                    scanStateBanner

                    if shouldShowManualCompletionHint {
                        manualCompletionHint
                    }

                    actionButtons

                    infoSection
                    formSection
                    debugSection

                    VStack(alignment: .leading, spacing: 10) {
                        Text("Note importante")
                            .font(.custom("DelaGothicOne-Regular", size: 14))
                            .foregroundStyle(.white)

                        Text("Cette carte reste informative. Elle vous aide a retrouver votre abonnement rapidement, mais ne remplace pas la validation officielle STIB/MoBIB.")
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(.white.opacity(0.75))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.horizontal, 17)
                    .padding(.bottom, 24)
                }
            }
        }
        .background(AppTheme.Palette.screen)
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
        ZStack {
            HStack {
                Button(action: onBack) {
                    Image(systemName: "arrow.left")
                        .font(.system(size: 18, weight: .medium))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 16, weight: .regular))
                        .foregroundStyle(.white)
                }
                .buttonStyle(.plain)
            }

            Text("Ma carte STIB")
                .font(.custom("Montserrat-SemiBold", size: 20))
                .foregroundStyle(.white)
        }
    }

    private var actionButtons: some View {
        HStack(spacing: 12) {
            Button {
                nfcReader.beginScan()
            } label: {
                HStack(spacing: 8) {
                    if nfcReader.isScanning {
                        ProgressView()
                            .tint(.black)
                    } else {
                        Image(systemName: "wave.3.right.circle.fill")
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(nfcReader.isScanning ? "Lecture..." : "Scanner en NFC")
                        .font(.custom("Montserrat-SemiBold", size: 13))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            }
            .buttonStyle(.plain)

            Button {
                draftPass = .empty
                syncDraftWithSessionNameIfNeeded()
                save()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.counterclockwise")
                        .font(.system(size: 14, weight: .semibold))
                    Text("Reinitialiser")
                        .font(.custom("Montserrat-SemiBold", size: 13))
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .frame(height: 49)
                .background(Color.white.opacity(0.08))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 16, style: .continuous)
                        .stroke(Color.white.opacity(0.18), lineWidth: 1)
                )
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, 17)
    }

    private var manualCompletionHint: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "square.and.pencil")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Color(hex: "#FFB347"))
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text("Completer manuellement")
                    .font(.custom("Montserrat-SemiBold", size: 13))
                    .foregroundStyle(.white)
                Text("Si le scan ne remonte pas toutes les donnees, ajoutez au minimum le numero visible et la date d'expiration de la carte.")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(Color(hex: "#FFB347").opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 17)
    }

    private var infoSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Associez votre carte")
                .font(.custom("DelaGothicOne-Regular", size: 14))
                .foregroundStyle(.white)

            Text("Le scan NFC sert a rattacher votre carte physique a votre profil et a eviter les erreurs de saisie. Orientez la carte lentement autour du haut de l'iPhone. Si certaines informations ne remontent pas, vous pouvez les completer manuellement ci-dessous.")
                .font(.custom("Montserrat-Regular", size: 12))
                .foregroundStyle(.white.opacity(0.72))
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 17)
    }

    private var formSection: some View {
        VStack(spacing: 14) {
            formField(title: "Titulaire") {
                TextField("Nom complet", text: binding(\.holderName))
                    .textInputAutocapitalization(.words)
            }

            formField(title: "Abonnement") {
                TextField("Ex: Abonnement annuel", text: binding(\.subscriptionLabel))
                    .textInputAutocapitalization(.words)
            }

            formField(title: "Numero de carte") {
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
                .tint(.white)
            }

            if let fingerprint = draftPass.nfcFingerprint, !fingerprint.isEmpty {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Empreinte NFC")
                        .font(.custom("Montserrat-SemiBold", size: 11))
                        .foregroundStyle(.white.opacity(0.6))

                    Text(fingerprint)
                        .font(.custom("Montserrat-Regular", size: 11))
                        .foregroundStyle(.white.opacity(0.78))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.top, 4)
            }
        }
        .padding(.horizontal, 17)
        .padding(.bottom, 10)
    }

    private var debugSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Diagnostic NFC")
                    .font(.custom("DelaGothicOne-Regular", size: 14))
                    .foregroundStyle(.white)

                Spacer()

                if !nfcReader.debugEvents.isEmpty {
                    Button {
                        nfcReader.clearDebugLog()
                    } label: {
                        Text("Effacer")
                            .font(.custom("Montserrat-SemiBold", size: 11))
                            .foregroundStyle(Color(hex: "#7CB2FF"))
                    }
                    .buttonStyle(.plain)
                }
            }

            if nfcReader.debugEvents.isEmpty {
                Text("Les evenements NFC apparaitront ici pendant vos tests sur iPhone.")
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.55))
            } else {
                VStack(spacing: 10) {
                    ForEach(nfcReader.debugEvents) { event in
                        HStack(alignment: .top, spacing: 10) {
                            Text(event.level)
                                .font(.custom("Montserrat-SemiBold", size: 10))
                                .foregroundStyle(Color(hex: "#7CB2FF"))
                                .frame(width: 54, alignment: .leading)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(event.message)
                                    .font(.custom("Montserrat-Regular", size: 11))
                                    .foregroundStyle(.white.opacity(0.82))
                                    .fixedSize(horizontal: false, vertical: true)
                                Text(relativeDateText(from: event.date))
                                    .font(.custom("Montserrat-Regular", size: 10))
                                    .foregroundStyle(.white.opacity(0.42))
                            }

                            Spacer()
                        }
                        .padding(12)
                        .background(Color.white.opacity(0.04))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                }
            }
        }
        .padding(.horizontal, 17)
    }

    private func statusBanner(icon: String, title: String, message: String, accent: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(accent)
                .padding(.top, 2)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.custom("Montserrat-SemiBold", size: 13))
                    .foregroundStyle(.white)
                Text(message)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(.white.opacity(0.74))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.05))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(accent.opacity(0.28), lineWidth: 1)
        )
        .padding(.horizontal, 17)
    }

    private func formField<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.custom("Montserrat-SemiBold", size: 12))
                .foregroundStyle(.white.opacity(0.72))

            content()
                .font(.custom("Montserrat-Regular", size: 14))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .frame(height: 52)
                .background(Color.white.opacity(0.04))
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .stroke(Color.white.opacity(0.1), lineWidth: 1)
                )
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
        formatter.locale = Locale(identifier: "fr_BE")
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

private struct TransitPassCardView: View {
    let pass: TransitPass

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("MOBIB")
                        .font(.custom("DelaGothicOne-Regular", size: 28))
                        .foregroundStyle(.white)

                    Text(pass.subscriptionLabel.isEmpty ? "Abonnement STIB" : pass.subscriptionLabel)
                        .font(.custom("Montserrat-SemiBold", size: 12))
                        .foregroundStyle(Color.white.opacity(0.88))
                }

                Spacer()

                Text(pass.statusLabel)
                    .font(.custom("Montserrat-SemiBold", size: 11))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Color.white.opacity(0.92))
                    .clipShape(Capsule())
            }

            Spacer(minLength: 24)

            HStack(alignment: .bottom) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(pass.maskedCardNumber)
                        .font(.custom("Montserrat-SemiBold", size: 20))
                        .foregroundStyle(.white)

                    HStack(spacing: 18) {
                        cardMeta(title: "Titulaire", value: pass.holderName.isEmpty ? "A completer" : pass.holderName)
                        cardMeta(title: "Expiration", value: pass.formattedExpiryDate)
                    }
                }

                Spacer()

                VStack(alignment: .trailing, spacing: 8) {
                    Text("stib")
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                    Text(".brussels")
                        .font(.custom("Montserrat-SemiBold", size: 11))
                }
                .foregroundStyle(.white.opacity(0.92))
            }
        }
        .padding(20)
        .frame(maxWidth: .infinity)
        .frame(height: 218)
        .background(
            ZStack {
                LinearGradient(
                    colors: [
                        Color(hex: "#9ACD32"),
                        Color(hex: "#71A819"),
                        Color(hex: "#4E7F0C")
                    ],
                    startPoint: .topLeading,
                    endPoint: .bottomTrailing
                )

                Circle()
                    .fill(Color.white.opacity(0.10))
                    .frame(width: 180, height: 180)
                    .offset(x: 110, y: -75)

                RoundedRectangle(cornerRadius: 30, style: .continuous)
                    .stroke(Color.white.opacity(0.14), lineWidth: 1)
            }
        )
        .clipShape(RoundedRectangle(cornerRadius: 30, style: .continuous))
        .overlay(alignment: .bottomTrailing) {
            if pass.nfcFingerprint != nil {
                HStack(spacing: 6) {
                    Image(systemName: "wave.3.right")
                    Text("NFC")
                }
                .font(.custom("Montserrat-SemiBold", size: 11))
                .foregroundStyle(.black.opacity(0.86))
                .padding(.horizontal, 10)
                .padding(.vertical, 8)
                .background(Color.white.opacity(0.92))
                .clipShape(Capsule())
                .padding(16)
            }
        }
        .padding(.horizontal, 17)
    }

    private func cardMeta(title: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title.uppercased())
                .font(.custom("Montserrat-SemiBold", size: 10))
                .foregroundStyle(Color.white.opacity(0.55))
            Text(value)
                .font(.custom("Montserrat-SemiBold", size: 12))
                .foregroundStyle(.white)
        }
    }
}
