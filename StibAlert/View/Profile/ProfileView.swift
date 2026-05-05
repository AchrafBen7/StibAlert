import SwiftUI

struct ProfileView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var stibi: StibiCenter
    @Environment(\.openURL) private var openURL
    @State private var selectedSubpage: SettingsSubpage?
    @State private var selectedLanguageCode = "FR"
    @State private var pushNotificationsEnabled = true
    @State private var weeklyDigestEnabled = true
    @State private var emailNotificationsEnabled = false
    @State private var smsNotificationsEnabled = false
    @State private var dataSharingEnabled = true
    @State private var locationTrackingEnabled = false
    @State private var adsPersonalizationEnabled = false
    @State private var firstName = ""
    @State private var lastName = ""
    @State private var email = ""
    @State private var username = ""
    @State private var commuteEnabled = false
    @State private var homeLabel = "Domicile"
    @State private var workLabel = "Travail"
    @State private var departureTime = "08:15"
    @State private var homeStopId: String?
    @State private var workStopId: String?
    @State private var favoriteLinesSelection: Set<String> = []
    @State private var isSavingSettings = false

    var body: some View {
        ZStack {
            if session.isGuest {
                GuestTabPlaceholder(
                    reason: .profile,
                    onSignIn: {
                        nav.authInitialRoute = .signIn
                        nav.showAuthFlow = true
                    },
                    onSignUp: {
                        nav.authInitialRoute = .signUp
                        nav.showAuthFlow = true
                    }
                )
            } else {
                if selectedSubpage != nil {
                    subpageContent
                } else {
                    rootContent
                }
            }
        }
        .toolbar(.hidden, for: .navigationBar)
        .task {
            stibi.setCurrentScreen("profile")
            syncFromSession()
            await loadStibiContext()
        }
        .onChange(of: session.currentUser?.id) { _, _ in
            syncFromSession()
        }
        .onChange(of: selectedLanguageCode) { _, newValue in
            Task { await persistLanguageIfNeeded(newValue) }
        }
        .onChange(of: pushNotificationsEnabled) { _, newValue in
            Task { await persistNotificationsIfNeeded(newValue) }
        }
        .onChange(of: weeklyDigestEnabled) { _, newValue in
            Task { await persistWeeklyDigestIfNeeded(newValue) }
        }
    }

    @ViewBuilder
    private var subpageContent: some View {
        switch selectedSubpage {
        case .languages:
            LanguageSettingsView(
                selectedLanguage: $selectedLanguageCode,
                onBack: { selectedSubpage = nil },
                onClose: closeToProfile
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .account:
            AccountSettingsView(
                firstName: $firstName,
                lastName: $lastName,
                email: $email,
                username: $username,
                commuteEnabled: $commuteEnabled,
                homeLabel: $homeLabel,
                workLabel: $workLabel,
                departureTime: $departureTime,
                homeStopId: $homeStopId,
                workStopId: $workStopId,
                favoriteLinesSelection: $favoriteLinesSelection,
                favoriteStops: session.currentUser?.favorisDetails ?? [],
                isSaving: isSavingSettings,
                onSave: saveAccount,
                onBack: { selectedSubpage = nil },
                onClose: closeToProfile
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .privacy:
            PrivacySettingsView(
                dataSharingEnabled: $dataSharingEnabled,
                locationTrackingEnabled: $locationTrackingEnabled,
                adsPersonalizationEnabled: $adsPersonalizationEnabled,
                onBack: { selectedSubpage = nil },
                onClose: closeToProfile
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .support:
            SupportSettingsView(
                onBack: { selectedSubpage = nil },
                onClose: closeToProfile
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .notifications:
            NotificationSettingsView(
                pushEnabled: $pushNotificationsEnabled,
                weeklyDigestEnabled: $weeklyDigestEnabled,
                emailEnabled: $emailNotificationsEnabled,
                smsEnabled: $smsNotificationsEnabled,
                onBack: { selectedSubpage = nil },
                onClose: closeToProfile
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .transitPass:
            TransitPassSettingsView(
                onBack: { selectedSubpage = nil },
                onClose: closeToProfile
            )
            .transition(.move(edge: .trailing).combined(with: .opacity))
        case .none:
            EmptyView()
        }
    }

    private var rootContent: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
                    profileHeader
                        .padding(.horizontal, 20)
                        .padding(.top, 18)

                    VStack(spacing: 22) {
                        identityCard

                        profileGroup(title: "Carte de transport") {
                            profileRow(icon: "creditcard", label: "MOBIB", value: maskedTransitCard) {
                                selectedSubpage = .transitPass
                            }
                        }

                        profileGroup(title: "Préférences") {
                            profileRow(icon: "bell", label: "Notifications", value: pushNotificationsEnabled ? "Activées" : "Désactivées") {
                                selectedSubpage = .notifications
                            }
                            profileDivider
                            profileRow(icon: "globe", label: "Langue", value: profileLanguageLabel) {
                                selectedSubpage = .languages
                            }
                            profileDivider
                            profileRow(icon: "person.crop.circle", label: "Mon compte", value: username.isEmpty ? nil : "@\(username)") {
                                selectedSubpage = .account
                            }
                        }

                        profileGroup(title: "Confidentialité") {
                            profileRow(icon: "lock", label: "Données & confidentialité") {
                                selectedSubpage = .privacy
                            }
                        }

                        profileGroup(title: "Support") {
                            profileRow(icon: "questionmark.circle", label: "Aide & FAQ") {
                                selectedSubpage = .support
                            }
                            profileDivider
                            profileRow(icon: "bubble.left", label: "Contacter l'équipe") {
                                if let url = URL(string: "mailto:contact@stib-alert.be?subject=Avis%20StibAlert") {
                                    openURL(url)
                                }
                            }
                        }

                        Text("STIBALERT · V1.0.0 · BRUXELLES")
                            .font(DS.Font.monoSmall)
                            .tracking(2)
                            .foregroundStyle(DS.Color.inkMute)
                            .padding(.top, 6)
                            .padding(.bottom, 96)
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 18)
                }
            }
        }
        .modifier(PaperGrainBackground())
    }

    private func closeToProfile() {
        selectedSubpage = nil
        nav.currentPage = .profile
    }

    private var profileHeader: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Compte StibAlert")
                        .eyebrow()
                    Text("Profil")
                        .font(DS.Font.displayH1)
                        .foregroundStyle(DS.Color.ink)
                }

                Spacer()

                Button {
                    selectedSubpage = .account
                } label: {
                    Image(systemName: "gearshape")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(DS.Color.ink)
                        .frame(width: 36, height: 36)
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(DS.Color.ink.opacity(0.20), lineWidth: 1.5)
                        )
                }
                .buttonStyle(.plain)
            }

            Rectangle()
                .fill(DS.Color.ink.opacity(0.14))
                .frame(height: 2)
        }
    }

    private var profileLanguageLabel: String {
        switch selectedLanguageCode.uppercased() {
        case "FR": return "Français"
        case "GB", "EN": return "English"
        case "BE", "NL": return "Nederlands"
        case "MA", "AR": return "العربية"
        case "ES": return "Español"
        case "PT": return "Português"
        default: return selectedLanguageCode.uppercased()
        }
    }

    private var maskedTransitCard: String {
        let raw = TransitPassStorage.load().cardNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        guard !raw.isEmpty else { return "Non liée" }
        return "•••• \(raw.suffix(4))"
    }

    private var activeAlertCount: Int {
        [pushNotificationsEnabled, weeklyDigestEnabled, emailNotificationsEnabled, smsNotificationsEnabled]
            .filter { $0 }
            .count
    }

    private var identityCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                ZStack {
                    Circle().fill(DS.Color.ink)
                    Text(profileInitial)
                        .font(DS.Font.monoLarge.weight(.bold))
                        .foregroundColor(DS.Color.paper)
                }
                .frame(width: 48, height: 48)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayProfileName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Color.ink)
                    Text("MEMBRE STIBALERT · \(profileLanguageLabel.uppercased())")
                        .font(DS.Font.monoSmall)
                        .tracking(1.2)
                        .foregroundColor(DS.Color.inkMute)
                }

                Spacer()

                Button {
                    selectedSubpage = .account
                } label: {
                    Text("Modifier")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundColor(DS.Color.ink)
                        .underline()
                }
                .buttonStyle(.plain)
            }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.16))
                .frame(height: 1.5)
                .padding(.horizontal, 16)

            HStack(spacing: 0) {
                profileStatCell(icon: "star.fill", label: "Favoris", value: "\(session.currentUser?.favorisDetails?.count ?? 0)")
                Divider().background(DS.Color.ink.opacity(0.15))
                profileStatCell(icon: "tram.fill", label: "Lignes", value: "\(favoriteLinesSelection.count)")
                Divider().background(DS.Color.ink.opacity(0.15))
                profileStatCell(icon: "bell.fill", label: "Alertes", value: "\(activeAlertCount)")
            }
            .frame(height: 72)
        }
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 6)
                .stroke(DS.Color.ink, lineWidth: 1.5)
        )
        .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    private var displayProfileName: String {
        session.currentUser?.nom ?? "Profil"
    }

    private var profileInitial: String {
        String(displayProfileName.trimmingCharacters(in: .whitespacesAndNewlines).prefix(1)).uppercased()
    }

    @ViewBuilder
    private func profileGroup<Content: View>(title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(2.2)
                .foregroundColor(DS.Color.ink)
                .padding(.leading, 4)

            VStack(spacing: 0) { content() }
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }

    private func profileStatCell(icon: String, label: String, value: String) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundColor(DS.Color.inkMute)
            Text(value)
                .font(DS.Font.monoLarge.weight(.bold))
                .foregroundColor(DS.Color.ink)
            Text(label.uppercased())
                .font(DS.Font.monoSmall.weight(.semibold))
                .tracking(1.8)
                .foregroundColor(DS.Color.inkMute)
        }
        .frame(maxWidth: .infinity)
    }

    private func profileRow(icon: String, label: String, value: String? = nil, action: (() -> Void)? = nil) -> some View {
        Button {
            action?()
        } label: {
            HStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 15, weight: .regular))
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

    private var profileDivider: some View {
        Rectangle()
            .fill(DS.Color.ink.opacity(0.12))
            .frame(height: 1)
    }

    private func syncFromSession() {
        guard let user = session.currentUser else { return }
        let parts = user.nom.split(separator: " ", maxSplits: 1).map(String.init)
        firstName = parts.first ?? user.nom
        lastName = parts.count > 1 ? parts[1] : ""
        email = user.email
        username = String(user.email.split(separator: "@").first ?? "user")
        selectedLanguageCode = user.langue ?? AppLocale.languageCode.uppercased()
        pushNotificationsEnabled = user.notifications ?? true
        weeklyDigestEnabled = user.weeklyDigestEnabled ?? true
        commuteEnabled = user.routine?.enabled ?? false
        homeLabel = user.routine?.homeLabel ?? "Domicile"
        workLabel = user.routine?.workLabel ?? "Travail"
        departureTime = user.routine?.departureTime ?? "08:15"
        homeStopId = user.routine?.homeStopId
        workStopId = user.routine?.workStopId
        favoriteLinesSelection = Set(user.favoriteLines ?? [])
    }

    private func persistLanguageIfNeeded(_ code: String) async {
        guard AppConfig.isBackendEnabled else { return }
        guard let user = session.currentUser, user.langue != code else { return }
        do {
            let updated = try await UtilisateurService.modifierLangue(userId: user.id, langue: code)
            session.applyCurrentUserUpdate(updated)
        } catch {
            print("Language update failed: \(error.localizedDescription)")
        }
    }

    private func persistNotificationsIfNeeded(_ enabled: Bool) async {
        guard AppConfig.isBackendEnabled else { return }
        guard let user = session.currentUser, user.notifications != enabled else { return }
        do {
            let updated = try await UtilisateurService.mettreAJourProfil(userId: user.id, notifications: enabled)
            session.applyCurrentUserUpdate(updated)
            if enabled {
                await PushNotificationManager.current?.requestAuthorizationAndRegister()
            }
        } catch {
            print("Notifications update failed: \(error.localizedDescription)")
        }
    }

    private func persistWeeklyDigestIfNeeded(_ enabled: Bool) async {
        guard AppConfig.isBackendEnabled else { return }
        guard let user = session.currentUser, user.weeklyDigestEnabled != enabled else { return }
        do {
            let updated = try await UtilisateurService.mettreAJourProfil(
                userId: user.id,
                weeklyDigestEnabled: enabled
            )
            session.applyCurrentUserUpdate(updated)
        } catch {
            print("Weekly digest update failed: \(error.localizedDescription)")
        }
    }

    private func saveAccount() {
        guard AppConfig.isBackendEnabled else { return }
        guard let user = session.currentUser else { return }
        isSavingSettings = true
        let nom = [firstName.trimmingCharacters(in: .whitespacesAndNewlines), lastName.trimmingCharacters(in: .whitespacesAndNewlines)]
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        Task {
            defer { isSavingSettings = false }
            do {
                let updated = try await UtilisateurService.mettreAJourProfil(
                    userId: user.id,
                    nom: nom,
                    favoriteLines: favoriteLinesSelection.sorted(),
                    routine: CommuteRoutineDTO(
                        enabled: commuteEnabled,
                        homeLabel: homeLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Domicile" : homeLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        workLabel: workLabel.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "Travail" : workLabel.trimmingCharacters(in: .whitespacesAndNewlines),
                        departureTime: departureTime.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "08:15" : departureTime.trimmingCharacters(in: .whitespacesAndNewlines),
                        homeStopId: homeStopId,
                        workStopId: workStopId
                    )
                )
                session.applyCurrentUserUpdate(updated)
            } catch {
                print("Account update failed: \(error.localizedDescription)")
            }
        }
    }

    private func loadStibiContext() async {
        guard AppConfig.isBackendEnabled else { return }
        do {
            let context = try await AssistantService.context()
            stibi.pushContextInsight(for: "profile", context: context)
        } catch {
            print("Profile Stibi context failed: \(error.localizedDescription)")
        }
    }
}

private struct ProfileRootRowPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.paper2 : DS.Color.paper)
    }
}

private struct SettingsTile: View {
    let item: SettingsTileItem
    let action: () -> Void
    @State private var isPressed = false

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(alignment: .top) {
                    Text(item.title)
                        .font(.custom("DelaGothicOne-Regular", size: 20))
                        .foregroundStyle(.black)

                    Spacer()

                    Circle()
                        .fill(Color(hex: "#7CB2FF"))
                        .frame(width: 12, height: 12)
                }

                Text(item.description)
                    .font(.custom("Montserrat-Regular", size: 11))
                    .foregroundStyle(.black)
                    .multilineTextAlignment(.leading)
                    .padding(.top, 10)

                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.top, 14)
            .frame(maxWidth: .infinity, minHeight: 120, maxHeight: 120, alignment: .topLeading)
            .background(isPressed || item.isInitiallyHighlighted ? Color(hex: "#BBDCFF") : .white)
            .clipShape(RoundedRectangle(cornerRadius: 17, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 17, style: .continuous)
                    .stroke(Color(hex: "#81B7FF"), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .pressEvents {
            withAnimation(.easeInOut(duration: 0.12)) { isPressed = true }
        } onRelease: {
            withAnimation(.easeInOut(duration: 0.12)) { isPressed = false }
        }
    }
}

private struct SettingsTileItem: Identifiable {
    let id = UUID()
    let title: String
    let description: String
    let isInitiallyHighlighted: Bool
    let subpage: SettingsSubpage?
}

private enum SettingsSubpage {
    case account
    case languages
    case notifications
    case privacy
    case support
    case transitPass
}

private enum SettingsMockData {
    static let items: [SettingsTileItem] = [
        .init(title: "Compte", description: "Gérer vos informations\npersonnelles et préférences.", isInitiallyHighlighted: true, subpage: .account),
        .init(title: "Ma carte STIB", description: "Associer votre carte\net retrouver votre abonnement.", isInitiallyHighlighted: false, subpage: .transitPass),
        .init(title: "Notifications", description: "Choisir quand et comment\nrecevoir des alertes.", isInitiallyHighlighted: false, subpage: .notifications),
        .init(title: "Langues", description: "Sélectionner votre langue\npréférée dans l’app.", isInitiallyHighlighted: false, subpage: .languages),
        .init(title: "A propos", description: "Découvrir la mission et\nl’équipe derrière l’application", isInitiallyHighlighted: false, subpage: nil),
        .init(title: "Privé", description: "Contrôler vos données et\nparamètres de confidentialité.", isInitiallyHighlighted: false, subpage: .privacy),
        .init(title: "Support", description: "Obtenir de l’aide ou signaler\nun problème.", isInitiallyHighlighted: false, subpage: .support)
    ]
}

private struct ProfileSubpageScaffold<Content: View>: View {
    let eyebrow: String
    let title: String
    let onBack: () -> Void
    let onClose: () -> Void
    let content: () -> Content

    init(
        eyebrow: String,
        title: String,
        onBack: @escaping () -> Void,
        onClose: @escaping () -> Void,
        @ViewBuilder content: @escaping () -> Content
    ) {
        self.eyebrow = eyebrow
        self.title = title
        self.onBack = onBack
        self.onClose = onClose
        self.content = content
    }

    var body: some View {
        ZStack {
            DS.Color.paper.ignoresSafeArea()

            ScrollView(showsIndicators: false) {
                VStack(spacing: 0) {
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
                            Text(eyebrow)
                                .eyebrow()
                            Text(title)
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
                    .padding(.horizontal, 20)
                    .padding(.top, 16)

                    VStack(alignment: .leading, spacing: 24) {
                        content()
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 16)
                    .padding(.bottom, 96)
                }
            }
        }
        .modifier(PaperGrainBackground())
    }
}

private struct ProfileSettingsSection<Content: View>: View {
    let title: String
    let content: () -> Content

    init(title: String, @ViewBuilder content: @escaping () -> Content) {
        self.title = title
        self.content = content
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(DS.Font.monoSmall.weight(.semibold))
                .tracking(1.5)
                .foregroundColor(DS.Color.inkMute)
                .padding(.horizontal, 4)

            VStack(spacing: 0) {
                content()
            }
            .background(DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md)
                    .stroke(DS.Color.ink.opacity(0.15), lineWidth: DS.Stroke.thick)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
        }
    }
}

private struct ProfileSettingsDivider: View {
    var body: some View {
        Rectangle()
            .fill(DS.Color.ink.opacity(0.12))
            .frame(height: 1)
    }
}

private struct ProfileSettingsSwitch: View {
    let isOn: Bool

    var body: some View {
        ZStack(alignment: isOn ? .trailing : .leading) {
            RoundedRectangle(cornerRadius: 12)
                .fill(isOn ? DS.Color.ink : DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(DS.Color.ink, lineWidth: DS.Stroke.thick)
                )
                .frame(width: 40, height: 24)
            Circle()
                .fill(isOn ? DS.Color.paper : DS.Color.ink)
                .frame(width: 18, height: 18)
                .padding(.horizontal, 2)
        }
        .animation(.easeInOut(duration: 0.18), value: isOn)
    }
}

private struct ProfileSettingsToggleRow: View {
    let label: String
    var description: String? = nil
    @Binding var value: Bool
    var disabled: Bool = false

    var body: some View {
        Button {
            guard !disabled else { return }
            withAnimation(.easeInOut(duration: 0.15)) {
                value.toggle()
            }
        } label: {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(DS.Color.ink)
                    if let description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Color.inkMute)
                    }
                }
                Spacer(minLength: 8)
                ProfileSettingsSwitch(isOn: value)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .opacity(disabled ? 0.4 : 1)
        }
        .buttonStyle(ProfileRootRowPressableStyle())
        .disabled(disabled)
    }
}

private struct ProfileSettingsChoiceRow: View {
    let label: String
    let subtitle: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundColor(DS.Color.ink)
                    if let subtitle {
                        Text(subtitle.uppercased())
                            .font(DS.Font.mono)
                            .tracking(1)
                            .foregroundColor(DS.Color.inkMute)
                    }
                }
                Spacer()
                if selected {
                    ZStack {
                        Circle().fill(DS.Color.ink).frame(width: 24, height: 24)
                        Image(systemName: "checkmark")
                            .font(.system(size: 12, weight: .heavy))
                            .foregroundColor(DS.Color.paper)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRootRowPressableStyle())
    }
}

private struct ProfileSettingsActionRow: View {
    let label: String
    var description: String? = nil
    var value: String? = nil
    var danger: Bool = false
    var inert: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundColor(danger ? DS.Color.destructive : DS.Color.ink)
                    if let description {
                        Text(description)
                            .font(.system(size: 11))
                            .foregroundColor(DS.Color.inkMute)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                if let value {
                    Text(value)
                        .font(DS.Font.mono)
                        .monospacedDigit()
                        .foregroundColor(DS.Color.inkMute)
                }
                if !inert {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(DS.Color.inkMute.opacity(0.6))
                        .padding(.top, 2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRootRowPressableStyle())
        .disabled(inert)
    }
}

private struct LanguageSettingsView: View {
    @Binding var selectedLanguage: String
    let onBack: () -> Void
    let onClose: () -> Void

    @State private var query = ""

    private var languages: [LanguageItem] {
        let all = LanguageMockData.items
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return all }
        return all.filter {
            $0.title.localizedCaseInsensitiveContains(trimmed)
            || $0.subtitle.localizedCaseInsensitiveContains(trimmed)
            || $0.code.localizedCaseInsensitiveContains(trimmed)
        }
    }

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Préférences",
            title: "Langues",
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DS.Color.inkMute)
                    TextField("Rechercher une langue…", text: $query)
                        .font(DS.Font.body)
                        .foregroundColor(DS.Color.ink)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                }
                .padding(.horizontal, 12)
                .frame(height: 40)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink.opacity(0.25), lineWidth: DS.Stroke.thick)
                )

                ProfileSettingsSection(title: "Choix de langue") {
                    ForEach(Array(languages.enumerated()), id: \.element.id) { idx, language in
                        Button {
                            selectedLanguage = language.code
                        } label: {
                            LanguageRow(language: language, isSelected: selectedLanguage == language.code)
                        }
                        .buttonStyle(ProfileRootRowPressableStyle())

                        if idx < languages.count - 1 {
                            ProfileSettingsDivider()
                        }
                    }
                }

                Text("L’app suit d’abord la langue du téléphone. Cette préférence aide aussi les contenus éditoriaux disponibles.")
                    .font(.system(size: 11.5))
                    .foregroundColor(DS.Color.inkSoft)
                    .padding(.horizontal, 4)
            }
        }
    }
}

private struct LanguageRow: View {
    let language: LanguageItem
    let isSelected: Bool

    var body: some View {
        HStack(spacing: 16) {
            Text(language.code)
                .font(DS.Font.monoLarge)
                .foregroundStyle(DS.Color.ink)
                .frame(width: 38, alignment: .leading)

            VStack(alignment: .leading, spacing: 3) {
                Text(language.title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)

                Text(language.subtitle)
                    .font(DS.Font.caption)
                    .foregroundStyle(DS.Color.inkMute)
            }

            Spacer()

            if isSelected {
                ZStack {
                    Circle().fill(DS.Color.ink).frame(width: 24, height: 24)
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .heavy))
                        .foregroundColor(DS.Color.paper)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(isSelected ? DS.Color.paper2.opacity(0.7) : DS.Color.paper)
    }
}

private struct LanguageItem: Identifiable {
    let id = UUID()
    let code: String
    let title: String
    let subtitle: String
}

private enum LanguageMockData {
    static let items: [LanguageItem] = [
        .init(code: "FR", title: "Français", subtitle: "Belgique"),
        .init(code: "NL", title: "Nederlands", subtitle: "België")
    ]
}

private struct NotificationSettingsView: View {
    @Binding var pushEnabled: Bool
    @Binding var weeklyDigestEnabled: Bool
    @Binding var emailEnabled: Bool
    @Binding var smsEnabled: Bool
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Préférences",
            title: "Notifications",
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Choisis comment recevoir les alertes liées à tes favoris, au réseau et aux résumés de service.")
                    .font(.system(size: 12.5))
                    .foregroundColor(DS.Color.inkSoft)

                ProfileSettingsSection(title: "Canaux") {
                    NotificationToggleRow(
                        icon: "bell.fill",
                        title: "Push",
                        description: "Alertes temps réel sur l’appareil",
                        isOn: $pushEnabled
                    )
                    ProfileSettingsDivider()
                    NotificationToggleRow(
                        icon: "calendar.badge.clock",
                        title: "Digest hebdo",
                        description: "Résumé éditorial chaque semaine",
                        isOn: $weeklyDigestEnabled
                    )
                    ProfileSettingsDivider()
                    NotificationToggleRow(
                        icon: "envelope.fill",
                        title: "Email",
                        description: "Récaps et confirmations longues",
                        isOn: $emailEnabled
                    )
                    ProfileSettingsDivider()
                    NotificationToggleRow(
                        icon: "message.fill",
                        title: "SMS",
                        description: "Canal court pour alertes critiques",
                        isOn: $smsEnabled
                    )
                }

                Text("STIBALERT · V1.0.0")
                    .font(DS.Font.monoSmall)
                    .tracking(2)
                    .foregroundColor(DS.Color.inkMute)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.top, 4)
            }
        }
    }
}

private struct NotificationToggleRow: View {
    let icon: String
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.ink)
            }
            .frame(width: 18)

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
            }

            Spacer()

            ProfileSettingsSwitch(isOn: isOn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        }
    }
}

private struct AccountSettingsView: View {
    @Binding var firstName: String
    @Binding var lastName: String
    @Binding var email: String
    @Binding var username: String
    @Binding var commuteEnabled: Bool
    @Binding var homeLabel: String
    @Binding var workLabel: String
    @Binding var departureTime: String
    @Binding var homeStopId: String?
    @Binding var workStopId: String?
    @Binding var favoriteLinesSelection: Set<String>
    let favoriteStops: [FavoriDetailDTO]
    let isSaving: Bool
    let onSave: () -> Void
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Compte",
            title: "Mon compte",
            onBack: onBack,
            onClose: onClose
        ) {
            avatarSection

            ProfileSettingsSection(title: "Infos personnelles") {
                AccountTextRow(icon: "person", text: $firstName, placeholder: "Prénom")
                ProfileSettingsDivider()
                AccountTextRow(icon: "person.crop.circle", text: $lastName, placeholder: "Nom")
            }

            ProfileSettingsSection(title: "Connexion") {
                AccountTextRow(icon: "envelope", text: $email, placeholder: "Email", keyboard: .emailAddress)
                ProfileSettingsDivider()
                AccountTextRow(icon: "at", text: $username, placeholder: "Pseudo")
                ProfileSettingsDivider()
                PasswordRow()
            }

            ProfileSettingsSection(title: "Routine quotidienne") {
                ToggleRow(
                    title: "Activer le mode trajet quotidien",
                    subtitle: "Prépare le trajet domicile-travail et les alertes utiles",
                    isOn: $commuteEnabled
                )
                ProfileSettingsDivider()
                AccountTextRow(icon: "house", text: $homeLabel, placeholder: "Domicile")
                ProfileSettingsDivider()
                AccountTextRow(icon: "clock", text: $departureTime, placeholder: "08:15")
                ProfileSettingsDivider()
                FavoriteStopPickerRow(
                    title: "Arrêt domicile",
                    selection: $homeStopId,
                    options: favoriteStops
                )
                ProfileSettingsDivider()
                AccountTextRow(icon: "briefcase", text: $workLabel, placeholder: "Travail")
                ProfileSettingsDivider()
                FavoriteStopPickerRow(
                    title: "Arrêt travail",
                    selection: $workStopId,
                    options: favoriteStops
                )
                ProfileSettingsDivider()
                FavoriteLinesSelector(
                    selection: $favoriteLinesSelection,
                    options: availableLines
                )
            }

            Button(action: onSave) {
                Group {
                    if isSaving {
                        ProgressView()
                            .tint(DS.Color.primaryForeground)
                    } else {
                        Text("Enregistrer")
                            .font(.system(size: 14, weight: .bold))
                            .tracking(0.6)
                    }
                }
                .foregroundStyle(DS.Color.primaryForeground)
                .frame(maxWidth: .infinity)
                .frame(height: 48)
                .background(DS.Color.primary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink, lineWidth: DS.Stroke.thick)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md))
                .shadow(DS.Shadow.floating)
            }
            .buttonStyle(.plain)
            .disabled(isSaving)
            .opacity(isSaving ? 0.7 : 1)

            Text("STIBALERT · V1.0.0 · BRUXELLES")
                .font(DS.Font.monoSmall)
                .tracking(2)
                .foregroundColor(DS.Color.inkMute)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding(.top, 4)
        }
    }

    private var avatarSection: some View {
        HStack(spacing: 12) {
            ZStack(alignment: .bottomTrailing) {
                Circle()
                    .fill(DS.Color.ink)
                    .frame(width: 56, height: 56)
                    .overlay(
                        Text(profileInitial)
                            .font(DS.Font.monoLarge.weight(.bold))
                            .foregroundStyle(DS.Color.paper)
                    )

                Circle()
                    .fill(DS.Color.primary)
                    .frame(width: 22, height: 22)
                    .overlay(
                        Image(systemName: "pencil")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Color.primaryForeground)
                    )
                    .overlay(
                        Circle()
                            .stroke(DS.Color.ink, lineWidth: 1)
                    )
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(displayName)
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Text(handleText)
                    .font(DS.Font.monoSmall)
                    .tracking(1.2)
                    .foregroundStyle(DS.Color.inkMute)
            }

            Spacer()
        }
    }

    private var availableLines: [String] {
        let lines = favoriteStops
            .flatMap { $0.lignesDesservies ?? [] }
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines).uppercased() }
            .filter { !$0.isEmpty }
        return Array(Set(lines)).sorted()
    }

    private var displayName: String {
        let value = [firstName, lastName]
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return value.isEmpty ? "Profil" : value
    }

    private var profileInitial: String {
        String(displayName.prefix(1)).uppercased()
    }

    private var handleText: String {
        let trimmed = username.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "COMPTE STIBALERT" : "@\(trimmed.uppercased())"
    }
}

private struct AccountTextRow: View {
    let icon: String
    @Binding var text: String
    var placeholder: String = ""
    var keyboard: UIKeyboardType = .default

    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 18)

            TextField(placeholder, text: $text)
                .font(.system(size: 13.5))
                .foregroundStyle(DS.Color.ink)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(keyboard)

            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct FavoriteLinesSelector: View {
    @Binding var selection: Set<String>
    let options: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(DS.Color.ink)

                Text("Lignes favorites")
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)

            if options.isEmpty {
                Text("Ajoute d’abord des arrêts favoris pour sélectionner des lignes utiles.")
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 62), spacing: 8)],
                    alignment: .leading,
                    spacing: 8
                ) {
                    ForEach(options, id: \.self) { line in
                        let isSelected = selection.contains(line)
                        Button {
                            if isSelected {
                                selection.remove(line)
                            } else {
                                selection.insert(line)
                            }
                            AppHaptics.soft()
                        } label: {
                            Text(line)
                                .font(DS.Font.mono)
                                .foregroundStyle(isSelected ? DS.Color.ink : DS.Color.paper)
                                .padding(.horizontal, 12)
                                .frame(height: 34)
                                .background(isSelected ? DS.Color.paper2 : DS.Color.ink)
                                .clipShape(Capsule())
                                .overlay(
                                    Capsule()
                                        .stroke(isSelected ? DS.Color.ink.opacity(0.2) : DS.Color.ink, lineWidth: 1)
                                )
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Ligne favorite \(line)")
                        .accessibilityValue(isSelected ? "Sélectionnée" : "Non sélectionnée")
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 12)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct ToggleRow: View {
    let title: String
    let subtitle: String?
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMute)
                }
            }
            Spacer()
            ProfileSettingsSwitch(isOn: isOn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        }
    }
}

private struct FavoriteStopPickerRow: View {
    let title: String
    @Binding var selection: String?
    let options: [FavoriDetailDTO]

    private var selectedName: String {
        options.first(where: { $0.id == selection })?.nom ?? "Aucun"
    }

    var body: some View {
        Menu {
            Button("Aucun") { selection = nil }
            ForEach(options) { stop in
                Button(stop.nom) { selection = stop.id }
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(DS.Color.inkMute)
                    Text(selectedName)
                        .font(.system(size: 13.5, weight: .medium))
                        .foregroundStyle(DS.Color.ink)
                        .lineLimit(1)
                }
                Spacer()
                Image(systemName: "chevron.down")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .buttonStyle(.plain)
    }
}

private struct PasswordRow: View {
    var body: some View {
        HStack(spacing: 13) {
            Image(systemName: "key")
                .font(.system(size: 15, weight: .regular))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 18)

            Text("Mots de passe")
                .font(.system(size: 13.5, weight: .medium))
                .foregroundStyle(DS.Color.ink)

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(DS.Color.inkMute.opacity(0.6))
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }
}

private struct PrivacySettingsView: View {
    @Binding var dataSharingEnabled: Bool
    @Binding var locationTrackingEnabled: Bool
    @Binding var adsPersonalizationEnabled: Bool
    let onBack: () -> Void
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL

    private let privacyPolicyURL = URL(string: "https://stib-alert-backend.onrender.com/privacy")!

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Données",
            title: "Confidentialité",
            onBack: onBack,
            onClose: onClose
        ) {
            ProfileSettingsSection(title: "Documents") {
                Button {
                    openURL(privacyPolicyURL)
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "doc.text")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(DS.Color.ink)
                            .frame(width: 18)
                        Text("Lire la politique de confidentialité complète")
                            .font(.system(size: 13.5, weight: .medium))
                            .foregroundColor(DS.Color.ink)
                        Spacer()
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.Color.inkMute)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ProfileRootRowPressableStyle())
            }

            ProfileSettingsSection(title: "Paramètres") {
                PrivacyToggleRow(
                    title: "Partage de données",
                    description: "Aide à améliorer l’app en envoyant des données d’usage anonymes.",
                    isOn: $dataSharingEnabled
                )
                ProfileSettingsDivider()
                PrivacyToggleRow(
                    title: "Suivi de localisation",
                    description: "Permet d’identifier les arrêts proches pour signaler plus vite.",
                    isOn: $locationTrackingEnabled
                )
                ProfileSettingsDivider()
                PrivacyToggleRow(
                    title: "Personnalisation des annonces",
                    description: "Utilise vos données pour adapter les publicités.",
                    isOn: $adsPersonalizationEnabled
                )
            }

            ProfileSettingsSection(title: "Gestion du compte") {
                PrivacyActionRow(
                    title: "Applications tierces",
                    description: "Certaines fonctionnalités s’appuient sur des services externes.",
                    actionLabel: "Voir",
                    learnMoreURL: URL(string: "https://stib-alert-backend.onrender.com/privacy")
                )
                ProfileSettingsDivider()
                PrivacyActionRow(
                    title: "Télécharger vos données",
                    description: "Obtenez une copie des données personnelles enregistrées.",
                    actionLabel: "Exporter"
                )
                ProfileSettingsDivider()
                PrivacyActionRow(
                    title: "Supprimer votre compte",
                    description: "Efface définitivement le compte et les données associées.",
                    actionLabel: "Supprimer",
                    danger: true
                )
            }
        }
    }
}

private struct PrivacyToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 12)

            ProfileSettingsSwitch(isOn: isOn)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .contentShape(Rectangle())
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                isOn.toggle()
            }
        }
    }
}

private struct PrivacyActionRow: View {
    let title: String
    let description: String
    let actionLabel: String
    var learnMoreURL: URL? = nil
    var danger: Bool = false
    @Environment(\.openURL) private var openURL

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(danger ? DS.Color.destructive : DS.Color.ink)

                Text(description)
                    .font(.system(size: 11))
                    .foregroundStyle(DS.Color.inkMute)
                    .fixedSize(horizontal: false, vertical: true)

                if let url = learnMoreURL {
                    Button("En savoir plus") { openURL(url) }
                        .buttonStyle(.plain)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(DS.Color.primary)
                        .padding(.top, 2)
                }
            }

            Spacer(minLength: 12)

            Button(actionLabel) {}
                .buttonStyle(.plain)
                .font(DS.Font.monoSmall.weight(.bold))
                .foregroundStyle(danger ? DS.Color.destructiveForeground : DS.Color.paper)
                .padding(.horizontal, 12)
                .frame(height: 24)
                .background(danger ? DS.Color.destructive : DS.Color.ink)
                .clipShape(RoundedRectangle(cornerRadius: 5))
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .padding(.bottom, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SupportSettingsView: View {
    private let items = SupportMockData.items
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Assistance",
            title: "Support",
            onBack: onBack,
            onClose: onClose
        ) {
            ProfileSettingsSection(title: "Aide & contact") {
                ForEach(Array(items.enumerated()), id: \.element.id) { idx, item in
                    SupportRow(item: item)

                    if idx < items.count - 1 {
                        ProfileSettingsDivider()
                    }
                }
            }

            Text("Réponse par email selon disponibilité de l’équipe StibAlert.")
                .font(.system(size: 11.5))
                .foregroundColor(DS.Color.inkSoft)
                .padding(.horizontal, 4)
        }
    }
}

private struct SupportRow: View {
    let item: SupportItem
    @Environment(\.openURL) private var openURL

    var body: some View {
        Button {
            if let url = item.url { openURL(url) }
        } label: {
            HStack(spacing: 12) {
                Image(systemName: item.highlighted ? "bubble.left.and.bubble.right.fill" : "questionmark.circle")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(item.highlighted ? DS.Color.primary : DS.Color.ink)
                    .frame(width: 18)

                VStack(alignment: .leading, spacing: 3) {
                    Text(item.title)
                        .font(.system(size: 13.5, weight: .semibold))
                        .foregroundStyle(DS.Color.ink)

                    Text(item.subtitle)
                        .font(.system(size: 11))
                        .foregroundStyle(DS.Color.inkMute)
                        .multilineTextAlignment(.leading)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(DS.Color.inkMute.opacity(0.6))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(ProfileRootRowPressableStyle())
    }
}

private struct SupportItem: Identifiable {
    let url: URL?
    let id = UUID()
    let title: String
    let subtitle: String
    let highlighted: Bool
}

private enum SupportMockData {
    static let items: [SupportItem] = [
        .init(url: URL(string: "mailto:support@stib-alert.be?subject=Aide%20StibAlert"), title: "Centre d’aide", subtitle: "Trouvez rapidement une\nsolution ici.", highlighted: false),
        .init(url: URL(string: "mailto:support@stib-alert.be?subject=Bug%20StibAlert"), title: "Signaler un bug", subtitle: "Un souci technique ?\nOn est là pour vous écouter.", highlighted: false),
        .init(url: URL(string: "mailto:community@stib-alert.be"), title: "Communauté", subtitle: "Faites partie du changement.", highlighted: false),
        .init(url: URL(string: "mailto:contact@stib-alert.be?subject=Contact%20StibAlert"), title: "Nous contacter", subtitle: "Trouvez rapidement une\nsolution ici.", highlighted: true)
    ]
}

private struct PressEventsModifier: ViewModifier {
    let onPress: () -> Void
    let onRelease: () -> Void

    func body(content: Content) -> some View {
        content.simultaneousGesture(
            DragGesture(minimumDistance: 0)
                .onChanged { _ in onPress() }
                .onEnded { _ in onRelease() }
        )
    }
}

private extension View {
    func pressEvents(onPress: @escaping () -> Void, onRelease: @escaping () -> Void) -> some View {
        modifier(PressEventsModifier(onPress: onPress, onRelease: onRelease))
    }
}
