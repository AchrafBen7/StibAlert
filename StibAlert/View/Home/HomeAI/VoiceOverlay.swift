import SwiftUI
import UIKit

/// The "Hey Mobi" voice modal — full-screen overlay launched from the map mic
/// button. Two-call flow:
///   1) ask backend with the transcript to extract `destination`.
///   2) iOS geocodes + computes the real trip via `prepareTrip`, then asks
///      the backend AGAIN with `proposedRoutes` populated → backend describes
///      the real trip with line badges (same renderer as the typed chat).
/// "Voir la route sur la carte" then applies the already-computed trip via
/// `applyTrip` — no extra search/planning happens at button time.
struct VoiceOverlay: View {
    let contextProvider: (String) async -> STIBAIContext
    /// Geocode `name` + compute trip options. Returns the proposedRoutes for
    /// the backend's 2nd call (or nil if geocoding/planning failed). The host
    /// view also stashes the planned trip internally so `applyTrip` can use it.
    let prepareTrip: (String) async -> [ProposedRoute]?
    /// Apply the trip planned by the most recent `prepareTrip`. Closes the
    /// overlay and shows the route on the map.
    let applyTrip: () -> Void
    let onClose: () -> Void
    /// N12 — Si le user a refusé l'autorisation micro, on lui propose de
    /// basculer vers le chat texte STIB·AI sans devoir naviguer manuellement.
    var onSwitchToText: () -> Void = {}

    @StateObject private var voice = VoiceAssistant()
    @StateObject private var player = VoicePlayer()

    @State private var phase: Phase = .idle
    @State private var reply: String = ""
    @State private var displayReply: String = ""
    @State private var pendingDestination: String?
    @State private var errorText: String?
    @State private var pulse = false
    /// Optional sub-line shown under the main "Je réfléchis…" status during the
    /// `prepareTrip` step ("Je calcule le meilleur trajet vers X…"). Lets the
    /// user know we're not stuck during the 3-5s round-trip for geocoding +
    /// planning + describing.
    @State private var thinkingDetail: String?

    enum Phase {
        case idle, listening, thinking, speaking, error
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [
                    DS.Color.paper,
                    DS.Color.paper2.opacity(0.88),
                    DS.Color.paper
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()

            VStack(spacing: 28) {
                Spacer()
                halo
                statusLine
                transcriptOrReply
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 38)
        }
        .preferredColorScheme(.light)
        .task {
            await start()
        }
        .onDisappear {
            voice.stopListening()
            player.stop()
        }
        // Surface any recogniser error (audio session blocked, no speech
        // detected, recognizer offline…) so the user knows what's happening
        // instead of staring at a stuck "Parle à Mobi".
        .onChange(of: voice.lastError) { _, newError in
            guard let newError, !newError.isEmpty else { return }
            phase = .error
            errorText = newError
        }
        // Sync phase with the recogniser: if listening was ended (silence
        // detected, error), and we hadn't already transitioned to thinking/
        // speaking/error, drop back to idle so the button re-engages cleanly.
        .onChange(of: voice.isListening) { _, listening in
            if !listening && phase == .listening && errorText == nil {
                phase = .idle
            }
        }
    }

    // MARK: - Animations

    private var halo: some View {
        ZStack {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .stroke(phaseColor.opacity(0.22 - Double(i) * 0.05), lineWidth: 2)
                    .frame(width: 180 + CGFloat(i) * 60, height: 180 + CGFloat(i) * 60)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                    .animation(
                        .easeInOut(duration: 1.5 + Double(i) * 0.25).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
            Circle()
                .fill(phaseColor.opacity(0.14))
                .frame(width: 160, height: 160)
                .overlay(
                    Circle()
                        .stroke(phaseColor.opacity(0.45), lineWidth: 2)
                )
            Image(systemName: phaseIcon)
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(phaseColor)
                .symbolEffect(.pulse, options: phase == .listening || phase == .speaking ? .repeating : .nonRepeating, value: phase)
        }
        .onAppear { pulse = true }
    }

    private var statusLine: some View {
        VStack(spacing: 6) {
            Text(statusText)
                .font(.system(size: 22, weight: .black))
                .foregroundStyle(DS.Color.ink)
                .multilineTextAlignment(.center)
            if phase == .thinking {
                // Dots animées sous "Je réfléchis…" pour montrer que ça bouge
                // (sans ça l'utilisateur voit un écran figé pendant 5-8 s).
                ThinkingDotsIndicator()
                    .padding(.top, 4)
            }
            if phase == .thinking, let detail = thinkingDetail {
                Text(detail)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(DS.Color.inkMute)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .transition(.opacity)
            }
        }
        .padding(.horizontal, 24)
        .animation(.easeOut(duration: 0.2), value: thinkingDetail)
    }

    @ViewBuilder
    private var transcriptOrReply: some View {
        switch phase {
        case .listening:
            VStack(spacing: 10) {
                // Live "EN ÉCOUTE" indicator with pulsing red dot — like
                // ChatGPT/Siri: the user instantly knows the mic is hot.
                HStack(spacing: 6) {
                    Circle()
                        .fill(DS.Color.danger)
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 1.3 : 0.85)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    Text("EN ÉCOUTE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(DS.Color.danger)
                }
                if voice.transcript.isEmpty {
                    Text("Vas-y, parle…")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                } else {
                    // Big live transcript — same vibe as ChatGPT's voice mode.
                    // N11 — minimumScaleFactor + lineLimit 7 + fixedSize pour les
                    // longues phrases ("Comment je vais de Forest Centenaire vers
                    // chaussée de Mons en passant par Gare du Midi").
                    Text(voice.transcript)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(DS.Color.ink)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                        .padding(.vertical, 16)
                        .background(DS.Color.paper)
                        .overlay(
                            RoundedRectangle(cornerRadius: 16, style: .continuous)
                                .stroke(DS.Color.border, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .lineLimit(7)
                        .minimumScaleFactor(0.7)
                        .fixedSize(horizontal: false, vertical: true)
                        .animation(.easeOut(duration: 0.18), value: voice.transcript)
                }
            }
        case .idle:
            Text("Appuie sur Parler et pose ta question.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(DS.Color.inkMute)
        case .speaking, .thinking:
            if !displayReply.isEmpty {
                // Rich reply with line badges (parses `[[L:NUM]]` markers via
                // STIBAIResponseRenderer) — same look as the typed STIB AI
                // chat. Background is on the OUTER frame so the white card
                // covers the full scroll area even when content is short, and
                // shows a thin scrollbar when the user needs to scroll.
                ScrollView(.vertical, showsIndicators: true) {
                    STIBAIResponseRenderer(text: displayReply)
                        .environment(\.colorScheme, .light)
                        .padding(18)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: 380)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                .padding(.horizontal, 14)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !reply.isEmpty {
                Text(reply)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(DS.Color.ink)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity)
            }
        case .error:
            if let errorText {
                Text(errorText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Color.statusMajor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 18)
                    .padding(.vertical, 14)
                    .background(DS.Color.statusMajor.opacity(0.08))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(DS.Color.statusMajor.opacity(0.22), lineWidth: 1)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .padding(.horizontal, 28)
            }
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        // N12 — Mic refusé : pas de retry possible, on offre un switch vers
        // le mode texte (STIBAIView) en 1 tap au lieu de bloquer le user.
        if micPermissionDenied {
            VStack(spacing: 10) {
                Button {
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    voice.stopListening()
                    player.stop()
                    onSwitchToText()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "keyboard")
                            .font(.system(size: 18, weight: .bold))
                        Text("Continuer en mode texte")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(DS.Color.info)
                    .shadow(color: DS.Color.info.opacity(0.20), radius: 18, y: 8)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Continuer en mode texte avec STIB·AI")

                HStack(spacing: 14) {
                    secondaryCloseButton
                    Button {
                        UIImpactFeedbackGenerator(style: .light).impactOccurred()
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    } label: {
                        HStack(spacing: 8) {
                            Image(systemName: "gearshape.fill")
                                .font(.system(size: 14, weight: .bold))
                            Text("Régler le micro")
                                .font(.system(size: 14, weight: .bold))
                        }
                        .foregroundStyle(DS.Color.ink)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(DS.Color.paper)
                        .overlay(
                            Capsule()
                                .stroke(DS.Color.border, lineWidth: 1)
                        )
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        // "Voir la route sur la carte" n'apparaît QUE quand on a réellement
        // décrit un trajet à l'utilisateur (phase = .speaking ET on a un
        // displayReply non vide). Avant on l'affichait dès qu'une destination
        // était détectée → le user voyait le bouton pendant le "Je calcule…"
        // et même quand prepareTrip échouait, sans qu'aucun trajet n'ait
        // été décrit. C'était trompeur.
        else if pendingDestination != nil && phase == .speaking && !displayReply.isEmpty {
            VStack(spacing: 10) {
                Button {
                    // Trip is already planned by prepareTrip during the AI
                    // call, so applying is instant — no spinner needed.
                    player.stop()
                    voice.stopListening()
                    UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                    pendingDestination = nil
                    applyTrip()
                } label: {
                    HStack(spacing: 10) {
                        Image(systemName: "map.fill")
                            .font(.system(size: 18, weight: .black))
                        Text("Voir la route sur la carte")
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(.white)
                    .frame(maxWidth: .infinity)
                    .frame(height: 60)
                    .background(DS.Color.info)
                    .shadow(color: DS.Color.info.opacity(0.20), radius: 18, y: 8)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)

                HStack(spacing: 14) {
                    secondaryCloseButton
                    secondaryAskAgainButton
                }
            }
        } else {
            HStack(spacing: 14) {
                secondaryCloseButton

                Button(action: { Task { await handleAction() } }) {
                    HStack(spacing: 10) {
                        Image(systemName: actionIcon)
                            .font(.system(size: 18, weight: .black))
                        Text(actionLabel)
                            .font(.system(size: 16, weight: .bold))
                    }
                    .foregroundStyle(actionForeground)
                    .frame(maxWidth: .infinity)
                    .frame(height: 64)
                    .background(actionBackground)
                    .overlay(
                        Capsule()
                            .stroke(actionBorder, lineWidth: 1)
                    )
                    .shadow(color: actionShadow, radius: 18, y: 8)
                    .clipShape(Capsule())
                }
                .buttonStyle(.plain)
                .disabled(phase == .thinking || phase == .speaking)
            }
        }
    }

    private var secondaryCloseButton: some View {
        Button(action: {
            voice.stopListening()
            player.stop()
            onClose()
        }) {
            Image(systemName: "xmark")
                .font(.system(size: 18, weight: .bold))
                .foregroundStyle(DS.Color.ink)
                .frame(width: 56, height: 56)
                .background(DS.Color.paper)
                .overlay(
                    Circle()
                        .stroke(DS.Color.border, lineWidth: 1)
                )
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var secondaryAskAgainButton: some View {
        Button(action: { Task { await handleAction() } }) {
            HStack(spacing: 8) {
                Image(systemName: "mic.fill")
                    .font(.system(size: 14, weight: .bold))
                Text("Reparler")
                    .font(.system(size: 14, weight: .bold))
            }
            .foregroundStyle(DS.Color.ink)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(DS.Color.paper)
            .overlay(
                Capsule()
                    .stroke(DS.Color.border, lineWidth: 1)
            )
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .disabled(phase == .thinking)
    }

    /// Whether the user has spoken something we can send right now.
    private var hasSpeechReady: Bool {
        voice.isListening && !voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var actionIcon: String {
        if hasSpeechReady { return "paperplane.fill" }
        if voice.isListening { return "stop.fill" }
        return "mic.fill"
    }

    private var actionLabel: String {
        if hasSpeechReady { return "Envoyer" }
        if voice.isListening { return "Arrêter" }
        return "Parler"
    }

    private var actionBackground: Color {
        if hasSpeechReady { return DS.Color.info }
        if voice.isListening { return DS.Color.statusMajor.opacity(0.12) }
        return DS.Color.paper
    }

    private var actionForeground: Color {
        if hasSpeechReady { return .white }
        if voice.isListening { return DS.Color.statusMajor }
        return DS.Color.ink
    }

    private var actionBorder: Color {
        if hasSpeechReady { return DS.Color.info.opacity(0.2) }
        if voice.isListening { return DS.Color.statusMajor.opacity(0.32) }
        return DS.Color.border
    }

    private var actionShadow: Color {
        if hasSpeechReady { return DS.Color.info.opacity(0.20) }
        return Color.black.opacity(0.05)
    }

    // MARK: - Visual helpers

    private var phaseColor: Color {
        switch phase {
        case .listening: return DS.Color.danger
        case .thinking:  return DS.Color.warning
        case .speaking:  return DS.Color.info
        case .error:     return DS.Color.statusMinor
        default:         return DS.Color.ink
        }
    }

    private var phaseIcon: String {
        switch phase {
        case .listening: return "mic.fill"
        case .thinking:  return "ellipsis"
        case .speaking:  return "waveform"
        case .error:     return "exclamationmark.triangle.fill"
        default:         return "mic"
        }
    }

    private var statusText: String {
        switch phase {
        case .idle:      return "Parle à Mobi"
        case .listening: return "Je t'écoute…"
        case .thinking:  return "Je réfléchis…"
        case .speaking:  return "Mobi"
        case .error:     return "Oups"
        }
    }

    // MARK: - Flow

    @State private var micPermissionDenied = false

    private func start() async {
        let granted = await voice.requestAuthorization()
        guard granted else {
            phase = .error
            micPermissionDenied = true
            errorText = L10n.Voice.micDeniedMessage
            return
        }
        micPermissionDenied = false
        beginListening()
    }

    /// Smart bottom-button handler:
    /// - Listening + transcript non-empty → **send** what was heard now (no
    ///   need to wait for the silence watchdog).
    /// - Listening + nothing heard      → cancel (back to idle).
    /// - Not listening (idle/error/after-speaking) → start a fresh listen.
    private func handleAction() async {
        if voice.isListening {
            let current = voice.transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            player.stop()
            voice.stopListening()
            if !current.isEmpty {
                await handleTranscript(current)
            } else {
                phase = .idle
            }
            return
        }
        player.stop()
        // Small breath so the audio session has time to switch from playback
        // back to record after a TTS reply finished.
        try? await Task.sleep(nanoseconds: 250_000_000)
        beginListening()
    }

    private func beginListening() {
        reply = ""
        displayReply = ""
        pendingDestination = nil
        errorText = nil
        phase = .listening
        // Haptic cue so the user knows the mic is hot and they can talk now —
        // visual "Je t'écoute…" alone wasn't unambiguous in testing.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        // Defer the heavy AVAudioEngine setup by one frame so SwiftUI gets
        // to render the .listening phase (red halo + "EN ÉCOUTE") BEFORE the
        // main thread blocks on audioSession.setActive + audioEngine.start
        // (~100-300ms on first tap). Without this the overlay looked frozen.
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 30_000_000) // ~2 frames
            guard phase == .listening else { return }
            voice.startListening { final in
                Task { await handleTranscript(final) }
            }
        }
    }

    @MainActor
    private func handleTranscript(_ text: String) async {
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        // B2 — reset systématique des états dérivés AVANT chaque tentative.
        // Sans ça, après un .error d'un précédent appel, pendingDestination
        // pouvait rester pollué + le bouton "Voir la route" apparaissait
        // brièvement quand on chaînait vers .speaking sans nouvel destination.
        pendingDestination = nil
        displayReply = ""
        reply = ""
        errorText = nil
        phase = .thinking
        thinkingDetail = nil
        let context = await contextProvider(text)
        do {
            // Fast path : regex client-side. Si on extrait une destination
            // tout de suite, on saute l'appel #1 (extraction) et on va
            // directement plan + appel #2 (description riche). Économise
            // 1-2 sec sur les phrases simples type "trajet vers Delacroix".
            if let regexDest = STIBAIDestinationExtractor.extract(from: text) {
                pendingDestination = regexDest
                // Étape 1/2 : recherche du trajet (MKLocalSearch + planner)
                withAnimation(.easeOut(duration: 0.2)) {
                    thinkingDetail = "🔎 Je cherche le trajet vers \(regexDest)…"
                }

                guard let proposedRoutes = await prepareTrip(regexDest), !proposedRoutes.isEmpty else {
                    pendingDestination = nil
                    phase = .error
                    errorText = "Je n'ai pas trouvé de trajet vers \"\(regexDest)\". Essaie une adresse plus précise ou ouvre le planner."
                    return
                }

                // Étape 2/2 : description par l'IA
                withAnimation(.easeOut(duration: 0.2)) {
                    thinkingDetail = "✨ Je prépare ta réponse…"
                }

                var enrichedContext = context
                enrichedContext.proposedRoutes = proposedRoutes
                enrichedContext.proposedDestination = regexDest

                let richResult = try await STIBAIVoiceClient.ask(text: text, context: enrichedContext)
                reply = richResult.spokenReply
                displayReply = richResult.displayReply ?? richResult.spokenReply
                thinkingDetail = nil
                phase = .speaking
                player.speak(richResult.spokenReply)
                return
            }

            // Pas de regex → flow 2-calls classique.
            withAnimation(.easeOut(duration: 0.2)) {
                thinkingDetail = "💭 Je comprends ta demande…"
            }

            let firstResult = try await STIBAIVoiceClient.ask(text: text, context: context)
            let dest = firstResult.destination?.trimmingCharacters(in: .whitespacesAndNewlines)

            guard let dest, !dest.isEmpty else {
                // Question hors trajet → on joue directement.
                reply = firstResult.spokenReply
                displayReply = firstResult.displayReply ?? firstResult.spokenReply
                pendingDestination = nil
                phase = .speaking
                player.speak(firstResult.spokenReply)
                return
            }

            pendingDestination = dest
            withAnimation(.easeOut(duration: 0.2)) {
                thinkingDetail = "🔎 Je cherche le trajet vers \(dest)…"
            }

            guard let proposedRoutes = await prepareTrip(dest), !proposedRoutes.isEmpty else {
                pendingDestination = nil
                phase = .error
                errorText = "Je n'ai pas trouvé de trajet vers \"\(dest)\". Essaie une adresse plus précise ou ouvre le planner."
                return
            }

            withAnimation(.easeOut(duration: 0.2)) {
                thinkingDetail = "✨ Je prépare ta réponse…"
            }

            var enrichedContext = context
            enrichedContext.proposedRoutes = proposedRoutes
            enrichedContext.proposedDestination = dest

            let richResult = try await STIBAIVoiceClient.ask(text: text, context: enrichedContext)
            reply = richResult.spokenReply
            displayReply = richResult.displayReply ?? richResult.spokenReply
            thinkingDetail = nil
            phase = .speaking
            player.speak(richResult.spokenReply)
        } catch {
            phase = .error
            errorText = error.localizedDescription
        }
    }
}

/// 3 dots that pulse in sequence — classic "typing" indicator used in
/// chat apps. Apparaît sous le statusText pendant la phase .thinking pour
/// éviter que l'utilisateur ait l'impression que l'app est figée pendant
/// les 5-8 s de pipeline AI (extraction → planner → description).
private struct ThinkingDotsIndicator: View {
    @State private var phase: Int = 0

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<3) { i in
                Circle()
                    .fill(DS.Color.primary.opacity(phase == i ? 0.95 : 0.30))
                    .frame(width: 7, height: 7)
                    .scaleEffect(phase == i ? 1.15 : 1.0)
            }
        }
        .animation(.easeInOut(duration: 0.35), value: phase)
        .task {
            // Task est automatiquement annulée quand la vue est démontée —
            // pas de Timer qui survit comme avec scheduledTimer.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 450_000_000) // 0.45 s
                if Task.isCancelled { return }
                phase = (phase + 1) % 3
            }
        }
    }
}

/// Compact mic button on the map — launches the `VoiceOverlay`.
/// Matches the squared header controls so the bottom actions don't drift into
/// a separate visual language.
struct MapVoiceFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 48, height: 48)
                .background(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .fill(LinearGradient(
                            colors: [DS.Color.danger, DS.Color.danger.opacity(0.78)],
                            startPoint: .top,
                            endPoint: .bottom
                        ))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                        .stroke(DS.Color.ink.opacity(0.22), lineWidth: 1)
                )
                .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                .shadow(color: DS.Color.danger.opacity(0.30), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parler à Mobi")
    }
}
