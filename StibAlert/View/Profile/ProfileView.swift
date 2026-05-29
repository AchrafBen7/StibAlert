import SwiftUI
import UserNotifications
import PhotosUI

struct ProfileView: View {
    @EnvironmentObject private var nav: AppNavigation
    @EnvironmentObject private var session: AuthSession
    @EnvironmentObject private var languageStore: AppLanguageStore
    @Environment(\.openURL) private var openURL
    @State private var selectedSubpage: SettingsSubpage?
    @State private var selectedLanguageCode = "FR"
    @State private var pushNotificationsEnabled = true
    /// État réel iOS du droit notifications (UNNotificationSettings).
    /// Si l'utilisateur a accepté côté backend mais bloqué côté système,
    /// la valeur effective est "Désactivées" — on affiche ÇA, pas le
    /// backend qui dirait à tort "Activées".
    @State private var systemNotificationsAuthorized = true
    @State private var maskedTransitCardCached: String = "Non configurée"
    // P5/P6 — confirmations pour Logout + Supprimer le compte rendus
    // discoverable au root.
    @State private var showLogoutConfirm = false
    @State private var showDeleteConfirm = false
    @State private var isWorkingOnAccount = false
    @State private var accountActionError: String?
    // P10 — avatar upload
    @State private var pickedItem: PhotosPickerItem?
    @State private var isUploadingAvatar = false
    @State private var avatarError: String?
    @State private var preTripPushEnabled = true
    @State private var communityClusterPushEnabled = true
    @State private var mercisPushEnabled = true
    @State private var quietHoursEnabled = true
    // S5 — Heures de plage silencieuse éditables (backend les accepte déjà via
    // PATCH ; défaut 22h → 7h aligné sur le modèle Mongo).
    @State private var quietHoursStartHour = 22
    @State private var quietHoursEndHour = 7
    // Débit global des alertes + règles par ligne.
    @State private var notificationFrequency = "essentiel"
    @State private var notificationRules: [NotificationRuleDTO] = []
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
    /// Number of community signalements the user has made — fetched from
    /// /me/contributions. 0 for a fresh account.
    @State private var signalementCount = 0
    /// P11 — activité récente : 3 dernières contributions du user.
    @State private var recentContributions: [ContributionItem] = []
    /// Community polish — summary chargé en même temps que recent[] pour
    /// le badge de contribution score. nil tant que le 1er fetch n'a pas eu
    /// lieu (cas signed-out ou backend down).
    @State private var contributionsSummary: ContributionsSummary?

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
            syncFromSession()
            refreshMaskedTransitCard()
            await refreshSystemNotificationsAuth()
        }
        .task(id: session.currentUser?.id) {
            await loadContributionCount()
        }
        // Rafraîchit la carte MoBIB cachée quand l'utilisateur revient du
        // sous-page TransitPass (où il a pu la modifier) — P3.
        .task(id: selectedSubpage) {
            refreshMaskedTransitCard()
        }
        .onChange(of: session.currentUser?.id) { _, _ in
            syncFromSession()
        }
        .onChange(of: selectedLanguageCode) { _, newValue in
            // Apply override locally first — this triggers the env(\.locale)
            // re-render at the app root so the UI swaps language immediately.
            languageStore.setOverride(newValue)
            Task { await persistLanguageIfNeeded(newValue) }
        }
        .onChange(of: pushNotificationsEnabled) { _, newValue in
            Task { await persistNotificationsIfNeeded(newValue) }
        }
        // P10 — déclenchement upload avatar à la sélection PhotosPicker.
        .onChange(of: pickedItem) { _, item in
            guard let item else { return }
            Task { await uploadPickedAvatar(item) }
        }
        .onChange(of: preTripPushEnabled) { _, newValue in
            Task { await persistPushPreference(preTrip: newValue) }
        }
        .onChange(of: communityClusterPushEnabled) { _, newValue in
            Task { await persistPushPreference(communityCluster: newValue) }
        }
        .onChange(of: mercisPushEnabled) { _, newValue in
            Task { await persistPushPreference(mercis: newValue) }
        }
        .onChange(of: quietHoursEnabled) { _, newValue in
            Task { await persistPushPreference(quietHours: newValue) }
        }
        .onChange(of: quietHoursStartHour) { _, newValue in
            Task { await persistPushPreference(quietHoursStart: newValue) }
        }
        .onChange(of: quietHoursEndHour) { _, newValue in
            Task { await persistPushPreference(quietHoursEnd: newValue) }
        }
        .onChange(of: notificationFrequency) { _, newValue in
            Task { await persistPushPreference(notificationFrequency: newValue) }
        }
    }

    private func persistPushPreference(
        preTrip: Bool? = nil,
        communityCluster: Bool? = nil,
        mercis: Bool? = nil,
        quietHours: Bool? = nil,
        quietHoursStart: Int? = nil,
        quietHoursEnd: Int? = nil,
        notificationFrequency freq: String? = nil,
        notificationRules rules: [NotificationRuleDTO]? = nil
    ) async {
        guard AppConfig.isBackendEnabled, let user = session.currentUser else { return }
        do {
            let updated = try await UtilisateurService.mettreAJourProfil(
                userId: user.id,
                preTripPushEnabled: preTrip,
                communityClusterPushEnabled: communityCluster,
                mercisPushEnabled: mercis,
                quietHoursEnabled: quietHours,
                quietHoursStartHour: quietHoursStart,
                quietHoursEndHour: quietHoursEnd,
                notificationFrequency: freq,
                notificationRules: rules
            )
            session.applyCurrentUserUpdate(updated)
        } catch {
            print("Push preference update failed: \(error.localizedDescription)")
        }
    }

    /// Met à jour la règle de notif d'une ligne + persiste l'ensemble.
    private func setLineRule(_ line: String, level: String) {
        notificationRules.removeAll { $0.scope == "line" && $0.key.uppercased() == line.uppercased() }
        if level != "essentiel" {
            notificationRules.append(NotificationRuleDTO(scope: "line", key: line.uppercased(), level: level))
        }
        Task { await persistPushPreference(notificationRules: notificationRules) }
    }

    private func lineRuleLevel(_ line: String) -> String {
        notificationRules.first { $0.scope == "line" && $0.key.uppercased() == line.uppercased() }?.level ?? "essentiel"
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
                preTripPushEnabled: $preTripPushEnabled,
                communityClusterPushEnabled: $communityClusterPushEnabled,
                mercisPushEnabled: $mercisPushEnabled,
                quietHoursEnabled: $quietHoursEnabled,
                quietHoursStartHour: $quietHoursStartHour,
                quietHoursEndHour: $quietHoursEndHour,
                notificationFrequency: $notificationFrequency,
                favoriteLines: Array(favoriteLinesSelection).sorted(),
                lineRuleLevel: lineRuleLevel,
                onSetLineRule: setLineRule,
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
                            // P3 : on lit le cache @State au lieu de
                            // recharger UserDefaults à chaque render
                            profileRow(icon: "creditcard", label: "MOBIB", value: maskedTransitCardCached) {
                                selectedSubpage = .transitPass
                            }
                        }

                        profileGroup(title: "Préférences") {
                            // P2 : on affiche l'état EFFECTIF (backend ET
                            // autorisé par iOS) — sinon le user voit
                            // "Activées" alors qu'iOS bloque tout
                            profileRow(icon: "bell", label: "Notifications", value: effectiveNotificationsEnabled ? "Activées" : "Désactivées") {
                                selectedSubpage = .notifications
                            }
                            profileDivider
                            profileRow(icon: "globe", label: "Langue", value: profileLanguageLabel) {
                                selectedSubpage = .languages
                            }
                            profileDivider
                            // Smart Commute LITE — entrée vers les paramètres
                            // routine (sub-page Compte qui contient la
                            // section Routine quotidienne). Affiche un
                            // résumé inline (homeLabel → workLabel · 08:15)
                            // si la routine est activée, sinon "Activer".
                            profileRow(
                                icon: "tram.fill",
                                label: "Mon trajet quotidien",
                                value: commuteSummary
                            ) {
                                selectedSubpage = .account
                            }
                            profileDivider
                            profileRow(icon: "person.crop.circle", label: "Mon compte", value: username.isEmpty ? nil : "@\(username)") {
                                selectedSubpage = .account
                            }
                        }

                        // Community polish — mini-card score & impact :
                        // visible si l'utilisateur a au moins 1 contribution.
                        // Pose les bases de la gamification (level visible)
                        // sans backend changes — calcul local depuis summary.
                        if let summary = contributionsSummary,
                           summary.totalContributions > 0 {
                            contributionScoreCard(summary)
                        }

                        // P11 — Activité récente : affichée UNIQUEMENT si
                        // l'utilisateur a au moins 1 contribution, sinon on
                        // n'occupe pas l'écran avec un état vide pour les
                        // nouveaux comptes.
                        if !recentContributions.isEmpty {
                            recentActivitySection
                        }

                        profileGroup(title: "Confidentialité") {
                            profileRow(icon: "lock", label: "Données & confidentialité") {
                                selectedSubpage = .privacy
                            }
                        }

                        // P12 — Inviter un ami : partage du lien App Store
                        // de StibAlert via ShareLink. Apple recommande ce
                        // pattern pour la viralité organique. Texte du lien
                        // pré-rempli avec accroche FR.
                        profileGroup(title: "Communauté") {
                            // B3 — URL extraite dans AppConfig.shareAppURL.
                            // Pointe vers /support tant qu'on n'a pas l'App
                            // Store ID (page publique stable). Remplacer la
                            // constante dans AppConfig dès attribution.
                            ShareLink(
                                item: AppConfig.shareAppURL,
                                message: Text("Tu prends les transports à Bruxelles ? Avec StibAlert je vois les perturbations en temps réel sur STIB, SNCB, De Lijn et TEC. Essaye :")
                            ) {
                                HStack(spacing: 12) {
                                    Image(systemName: "person.2.fill")
                                        .font(.system(size: 14, weight: .regular))
                                        .foregroundColor(DS.Color.ink)
                                        .frame(width: 18)
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text("Inviter un ami")
                                            .font(.system(size: 13.5, weight: .semibold))
                                            .foregroundStyle(DS.Color.ink)
                                        Text("Partage StibAlert avec tes proches qui prennent les transports.")
                                            .font(.system(size: 11.5))
                                            .foregroundStyle(DS.Color.inkMute)
                                            .lineLimit(2)
                                    }
                                    Spacer()
                                    Image(systemName: "square.and.arrow.up")
                                        .font(.system(size: 13, weight: .semibold))
                                        .foregroundColor(DS.Color.inkMute)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(ProfileRootRowPressableStyle())
                            .simultaneousGesture(TapGesture().onEnded {
                                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                            })
                        }

                        profileGroup(title: "Support") {
                            profileRow(icon: "questionmark.circle", label: "Aide & FAQ") {
                                selectedSubpage = .support
                            }
                            profileDivider
                            // P4 : "contact@stib-alert.be" hardcodé (qui ne
                            // résolvait rien) remplacé par l'URL Support
                            // publique servie depuis le backend. La page
                            // affiche l'email de contact + FAQ + redirige
                            // si on clique l'email. URL parité avec le
                            // Support URL App Store Connect.
                            profileRow(icon: "bubble.left", label: "Contacter l'équipe") {
                                if let url = URL(string: "\(AppConfig.backendBaseURL)/support") {
                                    openURL(url)
                                }
                            }
                        }

                        // P5 / P6 — Logout + Supprimer au ROOT (visibles
                        // immédiatement, pas cachés 2 niveaux plus bas).
                        // Apple App Review reject les apps où le delete
                        // account n'est pas "easily discoverable".
                        accountActionsSection

                        Text("STIBALERT · V\(Bundle.main.shortVersion) (\(Bundle.main.buildNumber)) · BRUXELLES")
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
        // P7 : gear icon top-right SUPPRIMÉ — il dupliquait l'entrée
        // "Mon compte" plus bas dans rootContent. On garde l'entrée
        // explicite (texte) qui est plus claire qu'une icône abstraite.
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Profil")
                    .font(.system(size: 22, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Spacer()
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

    // P3 : `maskedTransitCard` (computed property qui chargeait UserDefaults
    // à chaque render) supprimée — remplacée par maskedTransitCardCached
    // refresh-é dans .task + .task(id: selectedSubpage).

    /// Résumé court de la routine pour la row "Mon trajet quotidien".
    /// `nil` si la routine est désactivée — la row affichera juste son
    /// label sans badge value à droite.
    private var commuteSummary: String? {
        guard let routine = session.currentUser?.routine, routine.enabled else {
            return "Activer"
        }
        // "Bailli → Schuman · 08:15" (sans les labels si trop longs)
        let home = String(routine.homeLabel.prefix(12))
        let work = String(routine.workLabel.prefix(12))
        return "\(home) → \(work) · \(routine.departureTime)"
    }

    private func loadContributionCount() async {
        guard AppConfig.isBackendEnabled, session.isSignedIn else {
            signalementCount = 0
            recentContributions = []
            return
        }
        do {
            let response = try await ContributionsService.mine()
            signalementCount = response.summary.totalContributions
            // P11 : capture aussi les 3 dernières contributions pour la
            // section "Activité récente" du root profile.
            recentContributions = Array(response.recent.prefix(3))
            // Community polish — summary pour le contribution score.
            contributionsSummary = response.summary
        } catch {
            // P1 fix : on ne reset PAS à 0 sur erreur réseau. Le user verrait
            // sinon son compteur tomber à 0 à chaque petit hoquet réseau,
            // puis remonter — c'est plus alarmant qu'utile. On garde
            // l'ancienne valeur jusqu'au prochain succès.
        }
    }

    /// P2 fix : vérifie si iOS autorise les notifs au niveau système. Le
    /// backend (`user.notifications`) peut dire "true" alors que l'utilisateur
    /// a bloqué dans Réglages iOS → l'app reçoit ZÉRO push mais affichait
    /// "Activées" partout. Désormais on prend le ET logique des deux.
    private func refreshSystemNotificationsAuth() async {
        let settings = await UNUserNotificationCenter.current().notificationSettings()
        await MainActor.run {
            systemNotificationsAuthorized = settings.authorizationStatus == .authorized
                || settings.authorizationStatus == .provisional
                || settings.authorizationStatus == .ephemeral
        }
    }

    /// Valeur effective combinant backend + état système iOS.
    private var effectiveNotificationsEnabled: Bool {
        pushNotificationsEnabled && systemNotificationsAuthorized
    }

    /// P3 fix : avant `maskedTransitCard` était une computed property qui
    /// faisait UN ACCÈS UserDefaults + un décodage JSON à CHAQUE render
    /// (lors de profileRow, identityCard, etc.). On lit maintenant une
    /// fois dans .task et après modification (via .task(id:selectedSubpage)
    /// quand on revient de transitPass subpage).
    private func refreshMaskedTransitCard() {
        let raw = TransitPassStorage.load().cardNumber
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: " ", with: "")
        maskedTransitCardCached = raw.count >= 4 ? "•••• \(raw.suffix(4))" : "Non configurée"
    }

    private var identityCard: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                // P10 — Avatar circulaire. PhotosPicker au tap, AsyncImage
                // si photoProfil présent, sinon initiale du prénom. Overlay
                // discret stylet quand pas d'avatar pour indiquer "tap to
                // change". Spinner pendant l'upload.
                PhotosPicker(selection: $pickedItem, matching: .images, photoLibrary: .shared()) {
                    ZStack {
                        if let urlString = session.currentUser?.photoProfil,
                           let url = URL(string: urlString) {
                            AsyncImage(url: url) { phase in
                                switch phase {
                                case .success(let img):
                                    img.resizable().scaledToFill()
                                default:
                                    Circle().fill(DS.Color.ink)
                                    Text(profileInitial)
                                        .font(DS.Font.monoLarge.weight(.bold))
                                        .foregroundColor(DS.Color.paper)
                                }
                            }
                        } else {
                            Circle().fill(DS.Color.ink)
                            Text(profileInitial)
                                .font(DS.Font.monoLarge.weight(.bold))
                                .foregroundColor(DS.Color.paper)
                        }
                        if isUploadingAvatar {
                            Color.black.opacity(0.45)
                            ProgressView()
                                .tint(.white)
                                .scaleEffect(0.85)
                        }
                    }
                    .frame(width: 48, height: 48)
                    .clipShape(Circle())
                    .overlay(
                        Image(systemName: "pencil.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(DS.Color.primary)
                            .background(Circle().fill(DS.Color.paper))
                            .offset(x: 18, y: 18)
                            .opacity(session.currentUser?.photoProfil == nil ? 1 : 0)
                    )
                }
                .buttonStyle(.plain)
                .disabled(isUploadingAvatar)

                VStack(alignment: .leading, spacing: 2) {
                    Text(displayProfileName)
                        .font(.system(size: 15, weight: .bold))
                        .foregroundColor(DS.Color.ink)
                    Text("MEMBRE STIBALERT · \(profileLanguageLabel.uppercased())")
                        .font(DS.Font.monoSmall)
                        .tracking(1.2)
                        .foregroundColor(DS.Color.inkMute)
                    if let avatarError {
                        Text(avatarError)
                            .font(.system(size: 10, weight: .medium))
                            .foregroundStyle(DS.Color.statusMajor)
                            .lineLimit(1)
                    }
                }

                Spacer()
                // P7 : bouton "Modifier" SUPPRIMÉ.
            }
                .padding(.horizontal, 16)
                .padding(.top, 16)
                .padding(.bottom, 14)

            Rectangle()
                .fill(DS.Color.ink.opacity(0.16))
                .frame(height: 1.5)
                .padding(.horizontal, 16)

            // P9 : stats clickables — tap ouvre le tab correspondant.
            // Avant elles étaient muettes (display only). Maintenant Favoris
            // → tab Favoris, Lignes → tab Favoris aussi (qui liste les lignes
            // favorites), Signalements → tab Infos trafic.
            HStack(spacing: 0) {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    nav.currentPage = .favorites
                } label: {
                    profileStatCell(icon: "star.fill", label: "Favoris", value: "\(session.currentUser?.favorisDetails?.count ?? 0)")
                }
                .buttonStyle(.plain)
                Divider().background(DS.Color.ink.opacity(0.15))
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    nav.currentPage = .favorites
                } label: {
                    profileStatCell(icon: "tram.fill", label: "Lignes", value: "\(session.currentUser?.favoriteLines?.count ?? 0)")
                }
                .buttonStyle(.plain)
                Divider().background(DS.Color.ink.opacity(0.15))
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    nav.currentPage = .reports
                } label: {
                    profileStatCell(icon: "exclamationmark.bubble.fill", label: "Signalements", value: "\(signalementCount)")
                }
                .buttonStyle(.plain)
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

    /// Score = 1*totalContributions + 3*publishedClusters + 2*firstReporterCount
    /// + 1 par tranche de 5 personnes aidées. Pondération qui valorise l'impact
    /// communauté > volume brut. Tiers : Bronze 0-50, Argent 51-150, Or 151+.
    private func contributionScore(_ s: ContributionsSummary) -> (score: Int, tier: String, tint: Color) {
        let score = s.totalContributions
            + (s.publishedClusters * 3)
            + (s.firstReporterCount * 2)
            + (s.peopleHelpedTotal / 5)
        if score >= 151 { return (score, "OR", DS.Color.statusMinor) }
        if score >= 51  { return (score, "ARGENT", DS.Color.inkSoft) }
        return (score, "BRONZE", DS.Color.statusMajor.opacity(0.7))
    }

    @ViewBuilder
    private func contributionScoreCard(_ summary: ContributionsSummary) -> some View {
        let result = contributionScore(summary)
        HStack(spacing: 14) {
            ZStack {
                Circle().fill(result.tint.opacity(0.15)).frame(width: 50, height: 50)
                Image(systemName: "rosette")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(result.tint)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text("\(result.score) pts · niveau \(result.tier)")
                    .font(.system(size: 14.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                HStack(spacing: 6) {
                    miniStat(label: "Validés", value: "\(summary.publishedClusters)")
                    Text("·")
                        .foregroundStyle(DS.Color.inkMute)
                    miniStat(label: "Aidés", value: "\(summary.peopleHelpedTotal)")
                    Text("·")
                        .foregroundStyle(DS.Color.inkMute)
                    miniStat(label: "1ers", value: "\(summary.firstReporterCount)")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.10), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }

    @ViewBuilder
    private func miniStat(label: String, value: String) -> some View {
        Text("\(value) \(label.lowercased())")
            .font(.system(size: 10.5, weight: .semibold, design: .monospaced))
            .tracking(0.5)
            .foregroundStyle(DS.Color.inkMute)
    }

    private var recentActivitySection: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("Activité récente")
                    .font(.system(size: 13, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(DS.Color.inkMute)
                Spacer()
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    nav.currentPage = .reports
                } label: {
                    Text("Tout voir")
                        .font(.system(size: 11.5, weight: .bold))
                        .foregroundStyle(DS.Color.primary)
                        .underline()
                }
                .buttonStyle(.plain)
            }

            VStack(spacing: 8) {
                ForEach(recentContributions) { item in
                    recentActivityRow(item)
                }
            }
        }
    }

    @ViewBuilder
    private func recentActivityRow(_ item: ContributionItem) -> some View {
        let (icon, tint) = roleIconAndTint(for: item.role)
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 13, weight: .bold))
                .foregroundStyle(tint)
                .frame(width: 30, height: 30)
                .background(tint.opacity(0.12))
                .clipShape(Circle())

            VStack(alignment: .leading, spacing: 2) {
                Text(activityTitle(for: item))
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .lineLimit(1)
                Text(activitySubtitle(for: item))
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
            VStack(alignment: .trailing, spacing: 3) {
                // #2 — Statut vivant du signalement (À vérifier/Confirmé/Résolu…).
                if let badge = item.statusBadge {
                    Text(badge.label)
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(statusColor(badge.systemColor))
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(statusColor(badge.systemColor).opacity(0.12))
                        .clipShape(Capsule())
                }
                if let helped = item.peopleHelped, helped > 0 {
                    Text("+\(helped)")
                        .font(.system(size: 11, weight: .bold, design: .monospaced))
                        .foregroundStyle(DS.Color.statusOK)
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.08), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
    }

    private func statusColor(_ token: String) -> Color {
        switch token {
        case "ok": return DS.Color.statusOK
        case "primary": return DS.Color.primary
        case "warning": return DS.Color.warning
        default: return DS.Color.inkMute
        }
    }

    private func roleIconAndTint(for role: String) -> (String, Color) {
        switch role {
        case "first_reporter":      return ("exclamationmark.bubble.fill", DS.Color.statusMajor)
        case "confirmer":           return ("checkmark.circle.fill", DS.Color.primary)
        case "resolver":            return ("checkmark.seal.fill", DS.Color.statusOK)
        case "still_blocked_voter": return ("exclamationmark.octagon.fill", DS.Color.statusMinor)
        default:                    return ("dot.radiowaves.left.and.right", DS.Color.inkMute)
        }
    }

    private func activityTitle(for item: ContributionItem) -> String {
        let role = item.roleLabel
        if let ligne = item.ligne, !ligne.isEmpty {
            return "\(role) · Ligne \(ligne)"
        }
        return role
    }

    private func activitySubtitle(for item: ContributionItem) -> String {
        let type = item.typeProbleme ?? "Incident"
        let when = item.createdAt.map { Self.relativeFormatter.localizedString(for: $0, relativeTo: .now) } ?? ""
        return when.isEmpty ? type : "\(type) · \(when)"
    }

    private static let relativeFormatter: RelativeDateTimeFormatter = {
        let f = RelativeDateTimeFormatter()
        f.locale = Locale(identifier: "fr_BE")
        f.unitsStyle = .short
        return f
    }()

    private var accountActionsSection: some View {
        VStack(spacing: 10) {
            // Logout — neutre, action réversible (l'utilisateur peut se
            // reconnecter immédiatement). Lance la confirmation.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showLogoutConfirm = true
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Se déconnecter")
                        .font(.system(size: 14, weight: .bold))
                }
                .foregroundStyle(DS.Color.ink)
                .frame(maxWidth: .infinity)
                .frame(height: 50)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
            .disabled(isWorkingOnAccount)

            // Supprimer le compte — action destructive, demande double
            // confirmation. App Store reviewer doit pouvoir trouver cette
            // option en ≤ 2 taps depuis le launch — ici c'est 1 tap (root
            // profile). Texte explicite "définitivement" + couleur rouge.
            Button {
                UIImpactFeedbackGenerator(style: .light).impactOccurred()
                showDeleteConfirm = true
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .semibold))
                    Text("Supprimer mon compte")
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(DS.Color.statusMajor)
                .frame(maxWidth: .infinity)
                .frame(height: 42)
            }
            .buttonStyle(.plain)
            .disabled(isWorkingOnAccount)

            if let accountActionError {
                Text(accountActionError)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(DS.Color.statusMajor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 8)
            }
        }
        // Alert Logout — réversible
        .alert("Se déconnecter ?", isPresented: $showLogoutConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Se déconnecter", role: .destructive) {
                Task { await performLogout() }
            }
        } message: {
            Text("Tes favoris et préférences locales restent sur cet appareil. Tu peux te reconnecter à tout moment.")
        }
        // Alert Supprimer — IRRÉVERSIBLE
        .alert("Supprimer le compte définitivement ?", isPresented: $showDeleteConfirm) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer définitivement", role: .destructive) {
                Task { await performDeleteAccount() }
            }
        } message: {
            Text("Cette action est IRRÉVERSIBLE. Toutes tes données (profil, signalements, favoris) seront supprimées de nos serveurs sous 30 jours conformément au RGPD.")
        }
    }

    @MainActor
    private func uploadPickedAvatar(_ item: PhotosPickerItem) async {
        avatarError = nil
        guard let data = try? await item.loadTransferable(type: Data.self),
              let image = UIImage(data: data) else {
            avatarError = "Impossible de lire l'image."
            pickedItem = nil
            return
        }
        isUploadingAvatar = true
        do {
            _ = try await AvatarService.upload(image)
            // B5 — check cancellation avant de toucher au state UI : si la
            // view a été dismissée pendant l'upload (Profile → autre tab),
            // ne pas tenter refresh ni haptic. `defer` synchrone aurait
            // reset les flags immédiatement, laissant le callback success
            // tomber dans le vide. On reset manuellement APRÈS le do/catch.
            if !Task.isCancelled {
                await session.refreshCurrentUser()
                UINotificationFeedbackGenerator().notificationOccurred(.success)
            }
        } catch {
            if !Task.isCancelled {
                avatarError = (error as? LocalizedError)?.errorDescription
                    ?? "Upload impossible."
            }
        }
        isUploadingAvatar = false
        pickedItem = nil
    }

    @MainActor
    private func performLogout() async {
        isWorkingOnAccount = true
        accountActionError = nil
        await session.deconnexion()
        isWorkingOnAccount = false
        // Retour automatique au signedOut → AppRoot rebascule sur AuthFlow.
    }

    @MainActor
    private func performDeleteAccount() async {
        isWorkingOnAccount = true
        accountActionError = nil
        do {
            try await session.supprimerCompte()
        } catch {
            accountActionError = (error as? LocalizedError)?.errorDescription
                ?? "Suppression impossible. Réessaie dans un instant."
        }
        isWorkingOnAccount = false
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
                .tracking(1.4)
                .foregroundColor(DS.Color.inkMute)
                .lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 2)
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
        // Priority: in-app override > backend-persisted choice > current system language.
        selectedLanguageCode = languageStore.languageOverride?.uppercased()
            ?? user.langue
            ?? AppLocale.languageCode.uppercased()
        pushNotificationsEnabled = user.notifications ?? true
        preTripPushEnabled = user.preTripPushEnabled ?? true
        communityClusterPushEnabled = user.communityClusterPushEnabled ?? true
        mercisPushEnabled = user.mercisPushEnabled ?? true
        quietHoursEnabled = user.quietHoursEnabled ?? true
        quietHoursStartHour = user.quietHoursStartHour ?? 22
        quietHoursEndHour = user.quietHoursEndHour ?? 7
        notificationFrequency = user.notificationFrequency ?? "essentiel"
        notificationRules = user.notificationRules ?? []
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

}

private struct ProfileRootRowPressableStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.paper2 : DS.Color.paper)
    }
}

// SettingsTile + SettingsTileItem retirés (jamais référencés) — voir note
// dans SettingsMockData ci-dessous.

private enum SettingsSubpage {
    case account
    case languages
    case notifications
    case privacy
    case support
    case transitPass
}

// SettingsMockData / SettingsTile / SettingsTileItem ont été retirés —
// reliquat d'un ancien design de page Settings sous forme de tuiles, jamais
// référencé après la migration vers le rootContent en liste (l. 175+).

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
                        // U6 — bouton xmark "close" SUPPRIMÉ car onClose et
                        // onBack appellent tous deux closeToProfile() (même
                        // résultat fonctionnel). 2 boutons distincts pour la
                        // même action → confusion utilisateur. On garde back
                        // qui est le pattern iOS standard. Le `onClose:`
                        // paramètre de l'init reste pour compat ascendante.
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
    @Binding var preTripPushEnabled: Bool
    @Binding var communityClusterPushEnabled: Bool
    @Binding var mercisPushEnabled: Bool
    @Binding var quietHoursEnabled: Bool
    @Binding var quietHoursStartHour: Int
    @Binding var quietHoursEndHour: Int
    @Binding var notificationFrequency: String
    var favoriteLines: [String] = []
    var lineRuleLevel: (String) -> String = { _ in "essentiel" }
    var onSetLineRule: (String, String) -> Void = { _, _ in }
    let onBack: () -> Void
    let onClose: () -> Void

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Préférences",
            title: "Notifications",
            onBack: onBack,
            onClose: onClose
        ) {
            VStack(alignment: .leading, spacing: 16) {
                Text("Choisis quels types de notifications tu reçois. StibAlert ne t'enverra rien d'autre.")
                    .font(.system(size: 12.5))
                    .foregroundColor(DS.Color.inkSoft)

                frequencySelectorSection

                ProfileSettingsSection(title: "Types d'alertes") {
                    NotificationToggleRow(
                        icon: "sparkles",
                        title: "Brief pré-trajet",
                        description: "15 min avant ton départ habituel, un verdict actionable",
                        payloadExample: "Ligne 92 OK ce matin — départ habituel 8h40 conseillé.",
                        isOn: $preTripPushEnabled
                    )
                    ProfileSettingsDivider()
                    NotificationToggleRow(
                        icon: "exclamationmark.triangle.fill",
                        title: "Alertes communauté",
                        description: "Quand un cluster touche une de tes lignes favorites",
                        payloadExample: "Ligne 92 perturbée à Bailli — 3 confirmations.",
                        isOn: $communityClusterPushEnabled
                    )
                    ProfileSettingsDivider()
                    NotificationToggleRow(
                        icon: "hands.sparkles.fill",
                        title: "Mercis",
                        description: "Quand ton signalement aide d'autres voyageurs",
                        payloadExample: "Merci ! 12 voyageurs ont vu ton signalement.",
                        isOn: $mercisPushEnabled
                    )
                }
                .opacity(pushEnabled ? 1 : 0.45)
                .disabled(!pushEnabled)

                HStack(spacing: 6) {
                    Image(systemName: "lock.shield.fill")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(DS.Color.statusOK)
                    Text("Jamais de marketing — uniquement des événements de transport.")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .padding(.horizontal, 4)
                .padding(.top, -4)
                .padding(.bottom, 8)

                if !favoriteLines.isEmpty {
                    lineRulesSection
                }

                ProfileSettingsSection(title: "Plage silencieuse") {
                    NotificationToggleRow(
                        icon: "moon.zzz.fill",
                        title: quietHoursWindowLabel,
                        description: "Aucune push pendant ces heures, sauf urgences critiques",
                        payloadExample: "Accident bloque ligne 92 cette nuit (urgence — exception silence).",
                        isOn: $quietHoursEnabled
                    )
                    if quietHoursEnabled {
                        ProfileSettingsDivider()
                        quietHoursRangeRow
                    }
                }

                ProfileSettingsSection(title: "Canaux") {
                    NotificationToggleRow(
                        icon: "bell.fill",
                        title: "Push principal",
                        description: "Master switch pour toutes les notifications iOS",
                        isOn: $pushEnabled
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

    // Sélecteur de débit global des alertes (#3).
    private let frequencyOptions: [(value: String, label: String, desc: String)] = [
        ("tout", "Tout", "Toutes les alertes pertinentes"),
        ("essentiel", "Essentiel", "Perturbations + confirmées (recommandé)"),
        ("critique", "Critique", "Uniquement accident / agression / coupure"),
        ("digest", "Résumé", "Un seul récap, pas d'alerte en direct"),
    ]

    private var frequencySelectorSection: some View {
        ProfileSettingsSection(title: "Fréquence des alertes") {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(frequencyOptions, id: \.value) { opt in
                    Button {
                        withAnimation(.easeInOut(duration: 0.15)) { notificationFrequency = opt.value }
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: notificationFrequency == opt.value ? "largecircle.fill.circle" : "circle")
                                .font(.system(size: 16))
                                .foregroundStyle(notificationFrequency == opt.value ? DS.Color.primary : DS.Color.inkMute.opacity(0.5))
                            VStack(alignment: .leading, spacing: 1) {
                                Text(opt.label)
                                    .font(.system(size: 13.5, weight: .semibold))
                                    .foregroundStyle(DS.Color.ink)
                                Text(opt.desc)
                                    .font(.system(size: 11))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            Spacer()
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 9)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.vertical, 4)
        }
    }

    // #4 — Affinage par ligne favorite (Tout/Essentiel/Critique/Off).
    private let ruleLevels: [(value: String, label: String)] = [
        ("tout", "Tout"), ("essentiel", "Essentiel"), ("critique", "Critique seul"), ("off", "Désactivé"),
    ]

    private var lineRulesSection: some View {
        ProfileSettingsSection(title: "Affiner par ligne") {
            VStack(spacing: 0) {
                ForEach(Array(favoriteLines.enumerated()), id: \.element) { index, line in
                    if index > 0 { ProfileSettingsDivider() }
                    HStack(spacing: 12) {
                        Text("Ligne \(line)")
                            .font(.system(size: 13.5, weight: .semibold))
                            .foregroundStyle(DS.Color.ink)
                        Spacer()
                        Menu {
                            Picker("Niveau", selection: Binding(
                                get: { lineRuleLevel(line) },
                                set: { onSetLineRule(line, $0) }
                            )) {
                                ForEach(ruleLevels, id: \.value) { lvl in
                                    Text(lvl.label).tag(lvl.value)
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Text(ruleLevels.first { $0.value == lineRuleLevel(line) }?.label ?? "Essentiel")
                                    .font(.system(size: 12.5, weight: .bold))
                                    .foregroundStyle(lineRuleLevel(line) == "off" ? DS.Color.inkMute : DS.Color.primary)
                                Image(systemName: "chevron.up.chevron.down")
                                    .font(.system(size: 9, weight: .bold))
                                    .foregroundStyle(DS.Color.inkMute)
                            }
                            .padding(.horizontal, 10)
                            .padding(.vertical, 6)
                            .background(DS.Color.paper2)
                            .clipShape(Capsule())
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 11)
                }
            }
        }
    }

    // S5 — Libellé dynamique de la fenêtre silencieuse (ex. "22h → 7h").
    private var quietHoursWindowLabel: String {
        "\(quietHoursStartHour)h → \(quietHoursEndHour)h"
    }

    /// Deux sélecteurs d'heure (0–23) pour la plage silencieuse. Persistés au
    /// changement via le PATCH push prefs côté ProfileView.
    private var quietHoursRangeRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "clock.fill")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 18)

            Text("Plage")
                .font(.system(size: 13.5, weight: .semibold))
                .foregroundStyle(DS.Color.ink)

            Spacer()

            hourPicker(selection: $quietHoursStartHour, label: "Début")
            Image(systemName: "arrow.right")
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(DS.Color.inkMute)
            hourPicker(selection: $quietHoursEndHour, label: "Fin")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func hourPicker(selection: Binding<Int>, label: String) -> some View {
        Menu {
            Picker(label, selection: selection) {
                ForEach(0..<24, id: \.self) { hour in
                    Text("\(hour)h").tag(hour)
                }
            }
        } label: {
            HStack(spacing: 4) {
                Text("\(selection.wrappedValue)h")
                    .font(.system(size: 13.5, weight: .bold))
                    .foregroundStyle(DS.Color.ink)
                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 9, weight: .bold))
                    .foregroundStyle(DS.Color.inkMute)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(DS.Color.paper2)
            .clipShape(Capsule())
            .overlay(Capsule().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
        }
        .accessibilityLabel("\(label) de la plage silencieuse : \(selection.wrappedValue) heures")
    }
}

private struct NotificationToggleRow: View {
    let icon: String
    let title: String
    let description: String
    /// N7 — Exemple concret du payload reçu pour que le user sache à quoi
    /// ressemble la notification AVANT de l'activer. Affiché en italique
    /// très subtil sous la description.
    var payloadExample: String? = nil
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
                if let payloadExample {
                    Text("Ex : « \(payloadExample) »")
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(DS.Color.inkMute.opacity(0.75))
                        .italic()
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 1)
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
    let onBack: () -> Void
    let onClose: () -> Void
    @Environment(\.openURL) private var openURL
    @EnvironmentObject private var session: AuthSession
    @State private var showDeleteAlert = false

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

            ProfileSettingsSection(title: "Ce que StibAlert collecte") {
                PrivacySummaryRow(
                    icon: "location.fill",
                    title: "Localisation",
                    detail: "Uniquement en temps réel pour afficher les arrêts proches et calculer ton itinéraire. Jamais stockée sur nos serveurs."
                )
                ProfileSettingsDivider()
                PrivacySummaryRow(
                    icon: "person.fill",
                    title: "Compte",
                    detail: "Email, nom et préférences pour synchroniser tes favoris et alertes entre tes appareils."
                )
                ProfileSettingsDivider()
                PrivacySummaryRow(
                    icon: "person.2.fill",
                    title: "Signalements",
                    detail: "Contenu de tes signalements communautaires, conservé tant que ton compte existe. Tu peux supprimer ton compte à tout moment."
                )
            }

            ProfileSettingsSection(title: "Tes droits") {
                PrivacyActionRow(
                    title: "Supprimer votre compte",
                    description: "Efface définitivement le compte et les données associées.",
                    actionLabel: "Supprimer",
                    danger: true,
                    action: { showDeleteAlert = true }
                )
            }
        }
        .alert("Supprimer votre compte", isPresented: $showDeleteAlert) {
            Button("Annuler", role: .cancel) {}
            Button("Supprimer", role: .destructive) {
                Task { try? await session.supprimerCompte() }
            }
        } message: {
            Text("Cette action est irréversible. Votre compte et toutes vos données seront définitivement supprimés.")
        }
    }
}

private struct PrivacySummaryRow: View {
    let icon: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(DS.Color.ink)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.system(size: 13.5, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)

                Text(detail)
                    .font(.system(size: 11.5))
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
    }
}

private struct PrivacyActionRow: View {
    let title: String
    let description: String
    let actionLabel: String
    var learnMoreURL: URL? = nil
    var danger: Bool = false
    var action: (() -> Void)? = nil
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

            Button(actionLabel) { action?() }
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

    @State private var showFeatureTour = false

    var body: some View {
        ProfileSubpageScaffold(
            eyebrow: "Profil · Assistance",
            title: "Support",
            onBack: onBack,
            onClose: onClose
        ) {
            // Nouvelle section "Démarrage" — rejouer le tour 3-cards explique
            // carte/signalement/voix. Visible AVANT "Aide & contact" parce
            // qu'on a constaté que les nouveaux utilisateurs qui skippent
            // l'onboarding initial cherchent souvent ces explications dans
            // le profil.
            ProfileSettingsSection(title: "Démarrage") {
                Button {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    showFeatureTour = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 15, weight: .regular))
                            .foregroundColor(DS.Color.primary)
                            .frame(width: 18)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Revoir la visite guidée")
                                .font(.system(size: 13.5, weight: .semibold))
                                .foregroundColor(DS.Color.ink)
                            Text("3 cartes : carte, signalement, voix")
                                .font(.system(size: 11.5))
                                .foregroundColor(DS.Color.inkMute)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(DS.Color.inkMute)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .contentShape(Rectangle())
                }
                .buttonStyle(ProfileRootRowPressableStyle())
            }

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

            // Disclaimer App Store (parité avec Splash + Auth) — Apple peut
            // rejeter une app qui s'affiche comme officielle STIB-MIVB sans
            // mention claire d'indépendance.
            ProfileSettingsSection(title: "À propos") {
                VStack(alignment: .leading, spacing: 10) {
                    Text("StibAlert est une application indépendante développée par un étudiant. Elle n'est ni produite, ni endossée, ni affiliée à STIB-MIVB, SNCB, De Lijn ou TEC.")
                        .font(.system(size: 12.5))
                        .foregroundColor(DS.Color.ink)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Les données affichées proviennent des portails publics open data de ces opérateurs, ainsi que des signalements de la communauté StibAlert. Les marques citées appartiennent à leurs propriétaires respectifs.")
                        .font(.system(size: 12))
                        .foregroundColor(DS.Color.inkSoft)
                        .fixedSize(horizontal: false, vertical: true)
                    Text("Version \(Bundle.main.shortVersion) · Build \(Bundle.main.buildNumber)")
                        .font(.system(size: 11, weight: .medium, design: .monospaced))
                        .foregroundColor(DS.Color.inkMute)
                        .padding(.top, 4)
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 14)
            }
        }
        .fullScreenCover(isPresented: $showFeatureTour) {
            // À la demande — n'écrit PAS hasSeenFeatureTour : si l'utilisateur
            // l'a déjà vu une fois, c'est juste un replay manuel ; pas
            // besoin de toucher au flag global.
            FeatureTourView { showFeatureTour = false }
        }
    }
}

private extension Bundle {
    var shortVersion: String { infoDictionary?["CFBundleShortVersionString"] as? String ?? "?" }
    var buildNumber: String { infoDictionary?["CFBundleVersion"] as? String ?? "?" }
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
