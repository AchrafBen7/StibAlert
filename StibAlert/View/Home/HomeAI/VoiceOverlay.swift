import SwiftUI
import UIKit

/// The "Hey Mobi" voice modal — full-screen overlay launched from the map mic
/// button. Listens, asks the AI in one shot, speaks the reply, and (when the
/// AI returns a destination) hands it back to HomeView via `onDestination` so
/// the trip pipeline kicks in.
struct VoiceOverlay: View {
    let contextProvider: (String) async -> STIBAIContext
    /// Returns `true` if the destination was geocoded + handed to the trip
    /// pipeline; `false` if MKLocalSearch found nothing. On `false` we keep the
    /// overlay open and surface an error so the user can rephrase.
    let onDestination: (String) async -> Bool
    let onClose: () -> Void

    @StateObject private var voice = VoiceAssistant()
    @StateObject private var player = VoicePlayer()

    @State private var phase: Phase = .idle
    @State private var reply: String = ""
    @State private var displayReply: String = ""
    @State private var pendingDestination: String?
    @State private var errorText: String?
    @State private var pulse = false

    enum Phase {
        case idle, listening, thinking, speaking, error
    }

    var body: some View {
        ZStack {
            DS.Color.background.opacity(0.96).ignoresSafeArea()

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
        .preferredColorScheme(.dark)
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
                    .stroke(phaseColor.opacity(0.35 - Double(i) * 0.10), lineWidth: 2)
                    .frame(width: 180 + CGFloat(i) * 60, height: 180 + CGFloat(i) * 60)
                    .scaleEffect(pulse ? 1.08 : 0.94)
                    .animation(
                        .easeInOut(duration: 1.5 + Double(i) * 0.25).repeatForever(autoreverses: true),
                        value: pulse
                    )
            }
            Circle()
                .fill(phaseColor.opacity(0.18))
                .frame(width: 160, height: 160)
            Image(systemName: phaseIcon)
                .font(.system(size: 56, weight: .black))
                .foregroundStyle(.white)
                .symbolEffect(.pulse, options: phase == .listening || phase == .speaking ? .repeating : .nonRepeating, value: phase)
        }
        .onAppear { pulse = true }
    }

    private var statusLine: some View {
        Text(statusText)
            .font(.system(size: 22, weight: .black))
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 24)
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
                        .fill(Color(hex: "#FF5A5F"))
                        .frame(width: 8, height: 8)
                        .scaleEffect(pulse ? 1.3 : 0.85)
                        .animation(.easeInOut(duration: 0.7).repeatForever(autoreverses: true), value: pulse)
                    Text("EN ÉCOUTE")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.5)
                        .foregroundStyle(Color(hex: "#FF5A5F"))
                }
                if voice.transcript.isEmpty {
                    Text("Vas-y, parle…")
                        .font(.system(size: 19, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.55))
                } else {
                    // Big live transcript — same vibe as ChatGPT's voice mode.
                    Text(voice.transcript)
                        .font(.system(size: 24, weight: .bold))
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 22)
                        .lineLimit(5)
                        .animation(.easeOut(duration: 0.18), value: voice.transcript)
                }
            }
        case .idle:
            Text("Appuie sur Parler et pose ta question.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        case .speaking, .thinking:
            if !displayReply.isEmpty {
                // Rich reply with line badges (parses `[[L:NUM]]` markers via
                // STIBAIResponseRenderer) — same look as the typed STIB AI
                // chat. Wrapped in a dark card on top of the overlay halo so
                // it reads cleanly.
                ScrollView(showsIndicators: false) {
                    STIBAIResponseRenderer(text: displayReply)
                        .environment(\.colorScheme, .light)
                        .padding(16)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(Color.white)
                        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
                }
                .frame(maxHeight: 260)
                .padding(.horizontal, 18)
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            } else if !reply.isEmpty {
                Text(reply)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity)
            }
        case .error:
            if let errorText {
                Text(errorText)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(DS.Color.statusMinor)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    private var bottomBar: some View {
        // When we have a route destination from the AI's reply, the primary
        // action becomes "Voir la route sur la carte" (the trip pipeline takes
        // over and closes the overlay). Otherwise the standard
        // listen/send/cancel button is shown.
        if pendingDestination != nil && phase != .listening {
            VStack(spacing: 10) {
                Button {
                    let dest = pendingDestination ?? ""
                    player.stop()
                    voice.stopListening()
                    Task {
                        let ok = await onDestination(dest)
                        if ok {
                            // HomeView closes the overlay on success.
                            pendingDestination = nil
                        } else {
                            phase = .error
                            errorText = "Je n'ai pas trouvé \"\(dest)\" sur la carte. Essaie de reformuler (adresse, place, monument…) ou ouvre le planner."
                        }
                    }
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
                    .background(Color(hex: "#5FB8FF"))
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
                .foregroundStyle(.white)
                .frame(width: 56, height: 56)
                .background(Color.white.opacity(0.12))
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
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity)
            .frame(height: 56)
            .background(Color.white.opacity(0.18))
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
        if hasSpeechReady { return Color(hex: "#5FB8FF") }
        return .white
    }

    private var actionForeground: Color {
        if hasSpeechReady { return .white }
        return .black
    }

    // MARK: - Visual helpers

    private var phaseColor: Color {
        switch phase {
        case .listening: return Color(hex: "#FF5A5F")
        case .thinking:  return Color(hex: "#FFB85F")
        case .speaking:  return Color(hex: "#5FB8FF")
        case .error:     return DS.Color.statusMinor
        default:         return Color.white
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

    private func start() async {
        let granted = await voice.requestAuthorization()
        guard granted else {
            phase = .error
            errorText = "Autorise le micro et la reconnaissance vocale dans Réglages pour parler à Mobi."
            return
        }
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
        errorText = nil
        phase = .listening
        // Haptic cue so the user knows the mic is hot and they can talk now —
        // visual "Je t'écoute…" alone wasn't unambiguous in testing.
        UINotificationFeedbackGenerator().notificationOccurred(.success)
        voice.startListening { final in
            Task { await handleTranscript(final) }
        }
    }

    @MainActor
    private func handleTranscript(_ text: String) async {
        guard !text.isEmpty else {
            phase = .idle
            return
        }
        phase = .thinking
        let context = await contextProvider(text)
        do {
            let result = try await STIBAIVoiceClient.ask(text: text, context: context)
            reply = result.spokenReply
            displayReply = result.displayReply ?? result.spokenReply
            // Stash the destination — we don't fire `onDestination` automatically
            // anymore. The user reads/listens to the response, then taps
            // "Voir la route sur la carte" to actually navigate.
            pendingDestination = result.destination?.isEmpty == false ? result.destination : nil
            phase = .speaking
            player.speak(result.spokenReply)
        } catch {
            phase = .error
            errorText = error.localizedDescription
        }
    }
}

/// Compact round mic button on the map — launches the `VoiceOverlay`.
/// Same size as the other small map FABs (location, AI) so the row reads
/// cleanly, with the brand red as the only colour cue.
struct MapVoiceFloatingButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "mic.fill")
                .font(.system(size: 17, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 46, height: 46)
                .background(
                    Circle().fill(LinearGradient(
                        colors: [Color(hex: "#FF5A5F"), Color(hex: "#D63A3F")],
                        startPoint: .top, endPoint: .bottom
                    ))
                )
                .overlay(Circle().stroke(Color.white.opacity(0.35), lineWidth: 1))
                .shadow(color: Color(hex: "#FF5A5F").opacity(0.30), radius: 6, y: 2)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parler à Mobi")
    }
}
