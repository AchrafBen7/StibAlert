import SwiftUI

struct AppRoot: View {
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = AuthSession()
    @StateObject private var stibi = StibiCenter()
    @StateObject private var stibiSpeech = StibiSpeechSynthesizer()
    @AppStorage(AppStorageKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppStorageKeys.onboardingPendingPushPermission) private var onboardingPendingPushPermission = false

    private var shouldShowStibi: Bool {
        guard case .signedIn = session.state else { return false }
        return nav.currentPage == .home && !nav.showReportSheet
    }

    private var shouldHideStibi: Bool {
        nav.showReportSheet
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            content

            if shouldShowStibi, let brief = stibi.brief, !shouldHideStibi {
                StibiOverlay(
                    data: AssistantViewAdapters.presentationData(from: brief),
                    message: brief.message,
                    actions: brief.actions,
                    isExpanded: $stibi.isExpanded,
                    isConversationPresented: stibi.isConversationPresented,
                    onTap: { stibi.toggleExpanded() },
                    onOpenConversation: { stibi.openConversationAndListen() },
                    onDismiss: { stibi.dismiss() },
                    onAction: handleStibiAction
                )
                .padding(.leading, 18)
                .padding(.bottom, 80)
                .transition(.move(edge: .leading).combined(with: .opacity))
                .zIndex(20)
            }

            if shouldShowStibi, stibi.isConversationPresented, !shouldHideStibi {
                Color.black.opacity(0.42)
                    .ignoresSafeArea()
                    .transition(.opacity)
                    .zIndex(29)
                    .onTapGesture {
                        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                            stibi.closeConversation()
                        }
                    }

                StibiConversationPanel(
                    brief: stibi.brief,
                    history: stibi.history,
                    currentScreen: stibi.currentScreen,
                    autoStartVoiceRequestID: stibi.voiceInputRequestID,
                    suggestions: AssistantViewAdapters.suggestedPrompts(
                        for: stibi.currentScreen,
                        context: stibi.context
                    ),
                    isSending: stibi.isSendingCommand,
                    onClose: { stibi.closeConversation() },
                    onSend: { prompt in
                        Task { await stibi.sendCommand(prompt) }
                    },
                    onLoadCommuteBrief: {
                        Task { await stibi.loadCommuteBrief() }
                    },
                    isSpeaking: stibiSpeech.isSpeaking,
                    onSpeak: {
                        if stibiSpeech.isSpeaking {
                            stibiSpeech.stop()
                        } else if let brief = stibi.brief {
                            stibiSpeech.speak(brief: brief)
                        }
                    },
                    onAction: handleStibiAction
                )
                .padding(.horizontal, 14)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .zIndex(30)
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: stibi.isConversationPresented)
        .environmentObject(nav)
        .environmentObject(session)
        .environmentObject(stibi)
        .sheet(isPresented: $nav.showAuthFlow) {
            AuthFlowView()
                .environmentObject(session)
                .presentationDragIndicator(.visible)
        }
        .onChange(of: session.isSignedIn) { _, signedIn in
            guard signedIn else { return }
            if session.activationSuccessVisible {
                Task { @MainActor in
                    try? await Task.sleep(nanoseconds: 1_200_000_000)
                    session.activationSuccessVisible = false
                    nav.showAuthFlow = false
                }
            } else {
                nav.showAuthFlow = false
            }
        }
        .task { await session.bootstrap() }
        .task(id: session.currentUser?.id) {
            await applyOnboardingPreferencesIfNeeded()
        }
        .task(id: session.isSignedIn) {
            guard session.isSignedIn else { return }
            while !Task.isCancelled {
                await stibi.refreshProgressiveCommuteIfNeeded()
                try? await Task.sleep(for: .seconds(300))
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .stibiPushOpened)) { output in
            handlePush(userInfo: output.userInfo)
        }
        .onOpenURL { url in
            guard session.state != .unknown, let link = DeepLinkRouter.parse(url) else { return }
            applyDeepLink(link)
        }
        .onChange(of: stibi.brief?.speechTriggerKey) { _, _ in
            guard let brief = stibi.brief else { return }
            if brief.type == "guide" || brief.type == "commute_brief" {
                stibiSpeech.speak(brief: brief)
            }
        }
        .onChange(of: nav.showReportSheet) { _, isPresented in
            guard isPresented else { return }
            stibi.dismiss()
            stibiSpeech.stop()
        }
        .onChange(of: nav.currentPage) { _, page in
            guard page != .home else { return }
            stibi.dismiss()
            stibiSpeech.stop()
        }
    }

    @ViewBuilder
    private var content: some View {
        switch session.state {
        case .unknown:
            ZStack {
                AppTheme.Colors.onboardingBackground.ignoresSafeArea()
                ProgressView().tint(.white)
            }
        case .signedOut:
            if !hasSeenOnboarding {
                OnboardingView {
                    hasSeenOnboarding = true
                }
            } else {
                HomeView()
            }
        case .signedIn:
            HomeView()
        }
    }

    private func handleStibiAction(_ action: AssistantActionDTO) {
        Task {
            if await stibi.performTargetedAction(id: action.id) {
                return
            }

            await MainActor.run {
                if let prompt = stibi.handleAction(id: action.id) {
                    Task { await stibi.sendCommand(prompt) }
                    return
                }

                withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
                    switch action.id {
                    case "open_favorites":
                        nav.currentPage = .favorites
                        stibi.closeConversation()
                    case "open_commute_brief":
                        stibi.openConversation()
                        Task { await stibi.loadCommuteBrief() }
                    case "open_lines":
                        nav.currentPage = .signalements
                        stibi.closeConversation()
                    case "view_reports":
                        nav.currentPage = .reports
                        stibi.closeConversation()
                    case "open_profile":
                        nav.currentPage = .profile
                        stibi.closeConversation()
                    case "open_report", "continue_report":
                        nav.currentPage = .home
                        nav.showReportSheet = true
                        stibi.closeConversation()
                    case "view_map":
                        nav.currentPage = .home
                        stibi.dismiss()
                    case "open_home", "open_search", "view_route", "compare_routes":
                        nav.currentPage = .home
                        stibi.closeConversation()
                    default:
                        stibi.openConversation()
                    }
                }
            }
        }
    }

    private func handlePush(userInfo: [AnyHashable: Any]?) {
        guard case .signedIn = session.state else { return }
        let raw = DeepLinkRouter.extractRawDeepLink(from: userInfo)
        let link = DeepLinkRouter.parse(raw) ?? .stibi
        applyDeepLink(link)
    }

    func applyDeepLink(_ link: DeepLink) {
        withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) {
            switch link {
            case .home:
                nav.currentPage = .home
                stibi.closeConversation()
            case .line:
                nav.currentPage = .signalements
                stibi.closeConversation()
            case .signalements, .signalementDetail:
                nav.currentPage = .reports
                stibi.closeConversation()
            case .favorites:
                nav.currentPage = .favorites
                stibi.closeConversation()
            case .profile:
                nav.currentPage = .profile
                stibi.closeConversation()
            case .report:
                nav.currentPage = .home
                nav.showReportSheet = true
                stibi.closeConversation()
            case .stibiCommute:
                nav.currentPage = .home
                stibi.openConversation()
                Task { await stibi.loadCommuteBrief() }
            case .stibi:
                nav.currentPage = .home
                stibi.openConversation()
            case .route(let fromName, let fromLat, let fromLng, let toName, let toLat, let toLng):
                nav.currentPage = .home
                stibi.closeConversation()
                NotificationCenter.default.post(
                    name: .stibiRouteDeepLink,
                    object: nil,
                    userInfo: [
                        "fromName": fromName, "fromLat": fromLat, "fromLng": fromLng,
                        "toName": toName, "toLat": toLat, "toLng": toLng
                    ]
                )
            }
        }
    }

    private func applyOnboardingPreferencesIfNeeded() async {
        guard let user = session.currentUser else { return }
        guard OnboardingPreferenceStore.shouldApply(for: user.id) else { return }

        let preferences = OnboardingPreferenceStore.load()
        guard preferences.hasUsefulData else {
            OnboardingPreferenceStore.markApplied(for: user.id)
            return
        }

        do {
            let updated = try await UtilisateurService.mettreAJourProfil(
                userId: user.id,
                favoriteLines: preferences.favoriteLines,
                routine: CommuteRoutineDTO(
                    enabled: true,
                    homeLabel: preferences.homeLabel.isEmpty ? "Domicile" : preferences.homeLabel,
                    workLabel: user.routine?.workLabel ?? "Travail",
                    departureTime: preferences.departureTime,
                    homeStopId: user.routine?.homeStopId,
                    workStopId: user.routine?.workStopId
                )
            )
            session.applyCurrentUserUpdate(updated)
            OnboardingPreferenceStore.markApplied(for: user.id)
            await requestDeferredPushPermissionIfNeeded()
        } catch {
            print("Onboarding preference sync failed: \(error.localizedDescription)")
        }
    }

    private func requestDeferredPushPermissionIfNeeded() async {
        guard session.isSignedIn else { return }
        await PushNotificationManager.current?.requestAuthorizationAndRegister()
    }
}

private struct StibiOverlay: View {
    let data: StibiPresentationData
    let message: String
    let actions: [AssistantActionDTO]
    @Binding var isExpanded: Bool
    let isConversationPresented: Bool
    let onTap: () -> Void
    let onOpenConversation: () -> Void
    let onDismiss: () -> Void
    let onAction: (AssistantActionDTO) -> Void

    private var effectiveVisualState: String {
        isConversationPresented ? "speaking" : data.visualState
    }

    private var glowColor: Color {
        AssistantViewAdapters.glowColor(for: effectiveVisualState)
    }

    var body: some View {
        Group {
            if isExpanded {
                expandedOverlay
            } else {
                compactOverlay
            }
        }
        .animation(.spring(response: 0.3, dampingFraction: 0.86), value: isExpanded)
    }

    private var compactOverlay: some View {
        AnimatedStibiOrb(visualState: effectiveVisualState)
            .frame(width: 56, height: 56)
            .background(DS.Color.paper.opacity(0.98))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
            )
            .shadow(DS.Shadow.floating)
            .onTapGesture(perform: onTap)
    }

    private var expandedOverlay: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimatedStibiOrb(visualState: effectiveVisualState)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(data.name)
                        .font(DS.Font.sectionTitle)
                        .foregroundStyle(DS.Color.ink)

                    Text(data.severityLabel)
                        .font(DS.Font.eyebrow)
                        .foregroundStyle(DS.Color.inkMute)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(DS.Color.paper2.opacity(0.85))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(DS.Color.inkMute)
                    }
                    .buttonStyle(.plain)
                }

                Text(data.title)
                    .font(DS.Font.displayH3)
                    .foregroundStyle(DS.Color.ink)

                Text(message)
                    .font(DS.Font.bodySmall)
                    .foregroundStyle(DS.Color.inkSoft)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(data.confidenceLabel)
                        .font(DS.Font.monoSmall)
                        .foregroundStyle(glowColor)

                    Spacer()

                    Button(action: onOpenConversation) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 12))
                            Text("Parler")
                                .font(DS.Font.bodyBold)
                        }
                        .foregroundStyle(DS.Color.primaryForeground)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(DS.Color.primary)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if let primaryAction = actions.first {
                    Button(action: { onAction(primaryAction) }) {
                        HStack(spacing: 8) {
                            Text(primaryAction.label)
                                .font(DS.Font.bodyBold)
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(DS.Color.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(DS.Color.paper2.opacity(0.85))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 292, alignment: .leading)
        .background(DS.Color.paper.opacity(0.985))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
        )
        .shadow(DS.Shadow.floating)
        .onTapGesture(perform: onTap)
    }
}

private struct AnimatedStibiOrb: View {
    let visualState: String
    @State private var isAnimating = false

    private var glowColor: Color {
        AssistantViewAdapters.glowColor(for: visualState)
    }

    private var outerSize: CGFloat {
        switch visualState {
        case "alert": return 50
        case "guiding": return 48
        case "speaking": return 52
        default: return 44
        }
    }

    private var innerSize: CGFloat {
        visualState == "speaking" ? 24 : 22
    }

    private var pulseScale: CGFloat {
        switch visualState {
        case "alert": return 1.12
        case "guiding": return 1.08
        case "speaking": return 1.16
        case "watching": return 1.06
        default: return 1.03
        }
    }

    var body: some View {
        ZStack {
            if visualState != "idle" {
                Circle()
                    .fill(glowColor.opacity(0.16))
                    .frame(width: outerSize, height: outerSize)
                    .blur(radius: 9)
                    .scaleEffect(isAnimating ? pulseScale : 0.92)
            }

            StibiMascotView(visualState: visualState)
                .frame(width: innerSize, height: innerSize)
        }
        .onAppear { isAnimating = true }
        .animation(
            .easeInOut(duration: visualState == "alert" ? 0.85 : 1.25)
                .repeatForever(autoreverses: true),
            value: isAnimating
        )
    }
}

private struct StibiConversationPanel: View {
    let brief: AssistantBriefDTO?
    let history: [StibiConversationEntry]
    let currentScreen: String
    let autoStartVoiceRequestID: Int
    let suggestions: [String]
    let isSending: Bool
    let onClose: () -> Void
    let onSend: (String) -> Void
    let onLoadCommuteBrief: () -> Void
    let isSpeaking: Bool
    let onSpeak: () -> Void
    let onAction: (AssistantActionDTO) -> Void

    @State private var input = ""
    @StateObject private var voiceManager = StibiVoiceCommandManager()
    @State private var showVoiceSentConfirmation = false

    private var hasInlineActions: Bool {
        !(brief?.actions.isEmpty ?? true)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AnimatedStibiOrb(visualState: "speaking")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Stibi")
                        .font(DS.Font.displayH3)
                        .foregroundStyle(DS.Color.ink)
                    Text(headerSubtitle)
                        .font(DS.Font.eyebrow)
                        .foregroundStyle(DS.Color.inkMute)
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.inkMute)
                }
                .buttonStyle(.plain)

                Button(action: onSpeak) {
                    Image(systemName: isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let brief, history.isEmpty {
                        sectionHeader("ÉDITION EN COURS")
                        StibiBubble(text: brief.message, role: .assistant)
                    }

                    if !history.isEmpty {
                        sectionHeader("FIL DE CONVERSATION")

                        ForEach(history) { entry in
                            StibiBubble(text: entry.text, role: entry.role)
                        }
                    }

                    if let brief, hasInlineActions {
                        sectionHeader("RACCOURCIS")

                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(brief.actions) { action in
                                    Button(action.label) {
                                        onAction(action)
                                    }
                                    .font(DS.Font.bodyBold)
                                    .foregroundStyle(DS.Color.ink)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(DS.Color.paper2.opacity(0.85))
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if currentScreen == "favorites" || currentScreen == "home" {
                        sectionHeader("ROUTINE")

                        Button {
                            onLoadCommuteBrief()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.walk.motion")
                                Text("Brief trajet du jour")
                                    .font(DS.Font.bodyBold)
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(DS.Color.ink)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(DS.Color.paper2.opacity(0.85))
                            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    if !suggestions.isEmpty {
                        sectionHeader("QUESTIONS UTILES")

                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    onSend(suggestion)
                                }
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.ink)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(DS.Color.paper2.opacity(0.72))
                                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if voiceManager.authorizationDenied {
                        Text("Active le micro et la reconnaissance vocale pour utiliser les commandes vocales de Stibi.")
                            .font(DS.Font.bodySmall)
                            .foregroundStyle(DS.Color.inkMute)
                            .padding(.horizontal, 16)
                    } else if voiceManager.isListening || !voiceManager.transcript.isEmpty {
                        sectionHeader("DICTÉE")

                        VStack(alignment: .leading, spacing: 8) {
                            HStack(spacing: 8) {
                                ListeningPill(isListening: voiceManager.isListening)
                                Text(voiceManager.isListening ? "Stibi écoute…" : "Commande vocale prête")
                                    .font(DS.Font.eyebrow)
                                    .foregroundStyle(voiceManager.isListening ? Color(hex: "#1B8F73") : DS.Color.inkMute)
                            }
                            Text(voiceManager.transcript.isEmpty ? "Parle maintenant." : voiceManager.transcript)
                                .font(DS.Font.body)
                                .foregroundStyle(DS.Color.ink)
                        }
                        .padding(.horizontal, 16)
                    }
                }
                .padding(.top, 14)
                .padding(.bottom, 18)
            }
            .frame(maxHeight: 320)

            HStack(spacing: 10) {
                TextField("Demande-moi une action utile", text: $input)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.ink)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()
                    .padding(.horizontal, 12)
                    .frame(height: 40)
                    .background(DS.Color.paper2.opacity(0.72))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Button {
                    Task {
                        await voiceManager.toggleListening { finalText in
                            onSend(finalText)
                            showVoiceSentFeedback()
                            voiceManager.reset()
                        }
                    }
                } label: {
                    ZStack {
                        if voiceManager.isListening {
                            Circle()
                                .fill(Color(hex: "#73F0D2").opacity(0.18))
                                .scaleEffect(1.22)
                        }
                        Image(systemName: voiceManager.isListening ? "waveform" : "mic.fill")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundStyle(voiceManager.isListening ? Color(hex: "#1B8F73") : DS.Color.ink)
                .frame(width: 38, height: 38)
                .background(voiceManager.isListening ? Color(hex: "#73F0D2").opacity(0.16) : DS.Color.paper2)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: voiceManager.isListening)
                .buttonStyle(.plain)

                Button {
                    let prompt = input
                    input = ""
                    onSend(prompt)
                } label: {
                    if isSending {
                        ProgressView().tint(.black)
                    } else {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 13, weight: .bold))
                    }
                }
                .foregroundStyle(DS.Color.primaryForeground)
                .frame(width: 38, height: 38)
                .background(DS.Color.primary)
                .clipShape(Circle())
                .overlay(Circle().stroke(DS.Color.ink.opacity(0.12), lineWidth: 1))
                .buttonStyle(.plain)
                .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(DS.Color.paper.opacity(0.7))

            if showVoiceSentConfirmation {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 13, weight: .bold))
                    Text("Question envoyée")
                        .font(DS.Font.eyebrow)
                }
                .foregroundStyle(Color(hex: "#1B8F73"))
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .background(DS.Color.paper.opacity(0.985))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1.5)
        )
        .shadow(DS.Shadow.overlay)
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 540, alignment: .bottom)
        .onChange(of: autoStartVoiceRequestID) { _, newValue in
            guard newValue > 0 else { return }
            Task {
                await voiceManager.beginListening {
                    onSend($0)
                    showVoiceSentFeedback()
                    voiceManager.reset()
                }
            }
        }
    }

    private var headerSubtitle: String {
        switch currentScreen {
        case "favorites": return "VEILLE FAVORIS"
        case "signalements": return "LECTURE RÉSEAU"
        case "profile", "profile_main": return "PROFIL & HABITUDES"
        case "report": return "AIDE AU SIGNALEMENT"
        default: return "ÉDITION MOBILITÉ"
        }
    }

    private func sectionHeader(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(text)
                .font(DS.Font.eyebrow)
                .foregroundStyle(DS.Color.inkMute)
            Rectangle()
                .fill(DS.Color.ink.opacity(0.1))
                .frame(height: 1)
        }
        .padding(.horizontal, 16)
        .padding(.top, 4)
    }

    private func showVoiceSentFeedback() {
        withAnimation(.easeInOut(duration: 0.2)) {
            showVoiceSentConfirmation = true
        }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 1_200_000_000)
            withAnimation(.easeInOut(duration: 0.2)) {
                showVoiceSentConfirmation = false
            }
        }
    }
}

private struct ListeningPill: View {
    let isListening: Bool
    @State private var pulse = false

    var body: some View {
        HStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(Color(hex: "#73F0D2").opacity(isListening ? 0.22 : 0.10))
                    .frame(width: 16, height: 16)
                    .scaleEffect(isListening && pulse ? 1.22 : 1)
                Circle()
                    .fill(Color(hex: "#1B8F73"))
                    .frame(width: 7, height: 7)
            }

            Text(isListening ? "LIVE" : "PRÊT")
                .font(DS.Font.monoSmall.weight(.bold))
                .tracking(1.2)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(Color(hex: "#73F0D2").opacity(0.12))
        .clipShape(Capsule())
        .onAppear { pulse = true }
        .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulse)
    }
}

private struct StibiBubble: View {
    let text: String
    let role: StibiConversationEntry.Role

    var body: some View {
        HStack {
            if role == .assistant {
                content
                Spacer(minLength: 28)
            } else {
                Spacer(minLength: 28)
                content
            }
        }
        .padding(.horizontal, 16)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(role == .assistant ? "STIBI" : "VOUS")
                .font(DS.Font.eyebrow)
                .foregroundStyle(role == .assistant ? DS.Color.inkMute : DS.Color.primaryForeground.opacity(0.85))

            Text(text)
                .font(DS.Font.bodySmall)
                .foregroundStyle(role == .assistant ? DS.Color.ink : DS.Color.primaryForeground)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(role == .assistant ? DS.Color.paper2.opacity(0.82) : DS.Color.primary)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(DS.Color.ink.opacity(role == .assistant ? 0.08 : 0), lineWidth: 1)
        )
    }
}
