import SwiftUI

struct AppRoot: View {
    @StateObject private var nav = AppNavigation()
    @StateObject private var session = AuthSession()
    @StateObject private var stibi = StibiCenter()
    @StateObject private var stibiSpeech = StibiSpeechSynthesizer()
    @AppStorage(AppStorageKeys.hasSeenOnboarding) private var hasSeenOnboarding = false
    @AppStorage(AppStorageKeys.onboardingPendingPushPermission) private var onboardingPendingPushPermission = false

    var body: some View {
        ZStack(alignment: .bottomTrailing) {
            content

            if case .signedIn = session.state, let brief = stibi.brief {
                StibiOverlay(
                    data: AssistantViewAdapters.presentationData(from: brief),
                    message: brief.message,
                    actions: brief.actions,
                    isExpanded: $stibi.isExpanded,
                    isConversationPresented: stibi.isConversationPresented,
                    onTap: { stibi.toggleExpanded() },
                    onOpenConversation: { stibi.openConversation() },
                    onDismiss: { stibi.dismiss() },
                    onAction: handleStibiAction
                )
                .padding(.trailing, 18)
                .padding(.bottom, 26)
                .transition(.move(edge: .trailing).combined(with: .opacity))
                .zIndex(20)
            }

            if case .signedIn = session.state, stibi.isConversationPresented {
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
            if signedIn { nav.showAuthFlow = false }
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
                    case "open_lines", "view_reports":
                        nav.currentPage = .signalements
                        stibi.closeConversation()
                    case "open_profile":
                        nav.currentPage = .profile
                        stibi.closeConversation()
                    case "open_report", "continue_report":
                        nav.currentPage = .home
                        nav.showReportSheet = true
                        stibi.closeConversation()
                    case "open_home", "open_search", "view_map", "view_route", "compare_routes":
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
            case .signalements, .line, .signalementDetail:
                nav.currentPage = .signalements
                stibi.closeConversation()
            case .favorites:
                nav.currentPage = .favorites
                stibi.closeConversation()
            case .profile:
                nav.currentPage = .profileMain
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
            .padding(10)
            .background(Color(hex: "#0D1320").opacity(0.96))
            .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 24, style: .continuous)
                    .stroke(Color.white.opacity(0.08), lineWidth: 1)
            )
            .onTapGesture(perform: onTap)
    }

    private var expandedOverlay: some View {
        HStack(alignment: .top, spacing: 12) {
            AnimatedStibiOrb(visualState: effectiveVisualState)

            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 8) {
                    Text(data.name)
                        .font(.custom("DelaGothicOne-Regular", size: 13))
                        .foregroundStyle(.white)

                    Text(data.severityLabel)
                        .font(.custom("Montserrat-SemiBold", size: 10))
                        .foregroundStyle(Color.white.opacity(0.72))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.white.opacity(0.08))
                        .clipShape(Capsule())

                    Spacer()

                    Button(action: onDismiss) {
                        Image(systemName: "xmark")
                            .font(.system(size: 11, weight: .bold))
                            .foregroundStyle(Color.white.opacity(0.7))
                    }
                    .buttonStyle(.plain)
                }

                Text(data.title)
                    .font(.custom("DelaGothicOne-Regular", size: 15))
                    .foregroundStyle(.white)

                Text(message)
                    .font(.custom("Montserrat-Regular", size: 12))
                    .foregroundStyle(Color.white.opacity(0.82))
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(data.confidenceLabel)
                        .font(.custom("Montserrat-SemiBold", size: 11))
                        .foregroundStyle(glowColor)

                    Spacer()

                    Button(action: onOpenConversation) {
                        HStack(spacing: 6) {
                            Image(systemName: "waveform.circle.fill")
                                .font(.system(size: 12))
                            Text("Parler")
                                .font(.custom("Montserrat-SemiBold", size: 11))
                        }
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 8)
                        .background(glowColor)
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }

                if let primaryAction = actions.first {
                    Button(action: { onAction(primaryAction) }) {
                        HStack(spacing: 8) {
                            Text(primaryAction.label)
                                .font(.custom("Montserrat-SemiBold", size: 12))
                            Spacer()
                            Image(systemName: "arrow.right")
                                .font(.system(size: 11, weight: .bold))
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                        .frame(height: 40)
                        .background(Color.white.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .padding(14)
        .frame(width: 292, alignment: .leading)
        .background(Color(hex: "#0D1320").opacity(0.97))
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
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
        case "alert": return 58
        case "guiding": return 56
        case "speaking": return 60
        default: return 52
        }
    }

    private var innerSize: CGFloat {
        visualState == "speaking" ? 20 : 18
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
            Circle()
                .fill(glowColor.opacity(0.18))
                .frame(width: outerSize, height: outerSize)
                .blur(radius: 9)
                .scaleEffect(isAnimating ? pulseScale : 0.9)

            Circle()
                .stroke(glowColor.opacity(0.35), lineWidth: visualState == "alert" ? 2 : 1)
                .frame(width: outerSize - 10, height: outerSize - 10)
                .scaleEffect(isAnimating ? pulseScale - 0.04 : 0.92)
                .opacity(visualState == "idle" ? 0.45 : 0.9)

            Circle()
                .fill(Color(hex: "#10151F"))
                .frame(width: 38, height: 38)
                .overlay(
                    Circle()
                        .stroke(Color.white.opacity(0.14), lineWidth: 1)
                )

            Circle()
                .fill(
                    RadialGradient(
                        colors: [glowColor, glowColor.opacity(0.32)],
                        center: .center,
                        startRadius: 2,
                        endRadius: 14
                    )
                )
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

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 12) {
                AnimatedStibiOrb(visualState: "speaking")

                VStack(alignment: .leading, spacing: 4) {
                    Text("Stibi")
                        .font(.custom("DelaGothicOne-Regular", size: 18))
                        .foregroundStyle(.white)
                    Text(headerSubtitle)
                        .font(.custom("Montserrat-Regular", size: 12))
                        .foregroundStyle(Color.white.opacity(0.68))
                }

                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.72))
                }
                .buttonStyle(.plain)

                Button(action: onSpeak) {
                    Image(systemName: isSpeaking ? "speaker.slash.fill" : "speaker.wave.2.fill")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white.opacity(0.82))
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 16)
            .padding(.top, 16)

            ScrollView(showsIndicators: false) {
                VStack(alignment: .leading, spacing: 12) {
                    if let brief, history.isEmpty {
                        StibiBubble(text: brief.message, role: .assistant)
                    }

                    ForEach(history) { entry in
                        StibiBubble(text: entry.text, role: entry.role)
                    }

                    if let brief, !brief.actions.isEmpty {
                        ScrollView(.horizontal, showsIndicators: false) {
                            HStack(spacing: 8) {
                                ForEach(brief.actions) { action in
                                    Button(action.label) {
                                        onAction(action)
                                    }
                                    .font(.custom("Montserrat-SemiBold", size: 12))
                                    .foregroundStyle(.white)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 10)
                                    .background(Color.white.opacity(0.08))
                                    .clipShape(Capsule())
                                    .buttonStyle(.plain)
                                }
                            }
                            .padding(.horizontal, 16)
                        }
                    }

                    if currentScreen == "favorites" || currentScreen == "home" {
                        Button {
                            onLoadCommuteBrief()
                        } label: {
                            HStack(spacing: 8) {
                                Image(systemName: "figure.walk.motion")
                                Text("Mon trajet quotidien")
                                    .font(.custom("Montserrat-SemiBold", size: 12))
                                Spacer()
                                Image(systemName: "arrow.up.right")
                                    .font(.system(size: 11, weight: .bold))
                            }
                            .foregroundStyle(.white)
                            .padding(.horizontal, 12)
                            .padding(.vertical, 12)
                            .background(Color(hex: "#151E2C"))
                            .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                        }
                        .buttonStyle(.plain)
                        .padding(.horizontal, 16)
                    }

                    if !suggestions.isEmpty {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Commandes utiles")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .foregroundStyle(Color.white.opacity(0.68))
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) {
                                    onSend(suggestion)
                                }
                                .font(.custom("Montserrat-Regular", size: 13))
                                .foregroundStyle(.white)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 12)
                                .background(Color.white.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal, 16)
                    }

                    if voiceManager.authorizationDenied {
                        Text("Active le micro et la reconnaissance vocale pour utiliser les commandes vocales de Stibi.")
                            .font(.custom("Montserrat-Regular", size: 12))
                            .foregroundStyle(Color.white.opacity(0.62))
                            .padding(.horizontal, 16)
                    } else if voiceManager.isListening || !voiceManager.transcript.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text(voiceManager.isListening ? "Stibi écoute..." : "Commande vocale")
                                .font(.custom("Montserrat-SemiBold", size: 12))
                                .foregroundStyle(Color(hex: "#73F0D2"))
                            Text(voiceManager.transcript.isEmpty ? "Parle maintenant." : voiceManager.transcript)
                                .font(.custom("Montserrat-Regular", size: 13))
                                .foregroundStyle(.white)
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
                    .font(.custom("Montserrat-Regular", size: 14))
                    .foregroundStyle(.white)
                    .textInputAutocapitalization(.sentences)
                    .autocorrectionDisabled()

                Button {
                    Task {
                        await voiceManager.toggleListening { finalText in
                            onSend(finalText)
                            voiceManager.reset()
                        }
                    }
                } label: {
                    Image(systemName: voiceManager.isListening ? "waveform" : "mic.fill")
                        .font(.system(size: 13, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Color(hex: "#B5CFF8"))
                .clipShape(Circle())
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
                .foregroundStyle(.black)
                .frame(width: 38, height: 38)
                .background(Color(hex: "#73F0D2"))
                .clipShape(Circle())
                .buttonStyle(.plain)
                .disabled(isSending || input.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
            .padding(.horizontal, 16)
            .padding(.top, 12)
            .padding(.bottom, 16)
            .background(Color.white.opacity(0.03))
        }
        .background(Color(hex: "#0B111E").opacity(0.98))
        .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 28, style: .continuous)
                .stroke(Color.white.opacity(0.08), lineWidth: 1)
        )
        .frame(maxWidth: .infinity)
        .frame(maxHeight: 540, alignment: .bottom)
    }

    private var headerSubtitle: String {
        switch currentScreen {
        case "favorites": return "veille favorites"
        case "signalements": return "lecture réseau"
        case "profile", "profile_main": return "profil et habitudes"
        case "report": return "aide au signalement"
        default: return "copilote mobilité"
        }
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
        Text(text)
            .font(.custom("Montserrat-Regular", size: 13))
            .foregroundStyle(role == .assistant ? .white : .black)
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(role == .assistant ? Color.white.opacity(0.08) : Color(hex: "#73F0D2"))
            .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }
}
