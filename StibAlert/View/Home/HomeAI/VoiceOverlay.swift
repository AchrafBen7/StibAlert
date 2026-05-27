import SwiftUI

/// The "Hey Mobi" voice modal — full-screen overlay launched from the map mic
/// button. Listens, asks the AI in one shot, speaks the reply, and (when the
/// AI returns a destination) hands it back to HomeView via `onDestination` so
/// the trip pipeline kicks in.
struct VoiceOverlay: View {
    let contextProvider: (String) async -> STIBAIContext
    let onDestination: (String) -> Void
    let onClose: () -> Void

    @StateObject private var voice = VoiceAssistant()
    @StateObject private var player = VoicePlayer()

    @State private var phase: Phase = .idle
    @State private var reply: String = ""
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
            if !voice.transcript.isEmpty {
                Text("« \(voice.transcript) »")
                    .font(.system(size: 17, weight: .medium))
                    .foregroundStyle(.white.opacity(0.85))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity)
            } else {
                Text("Vas-y, parle…")
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(.white.opacity(0.55))
            }
        case .idle:
            Text("Appuie sur le micro et parle.")
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.white.opacity(0.55))
        case .speaking, .thinking:
            if !reply.isEmpty {
                Text(reply)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
                    .transition(.opacity.combined(with: .move(edge: .bottom)))
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

    private var bottomBar: some View {
        HStack(spacing: 14) {
            Button(action: {
                voice.stopListening()
                player.stop()
                onClose()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 18, weight: .bold))
                    .foregroundStyle(.white)
                    .frame(width: 64, height: 64)
                    .background(Color.white.opacity(0.12))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)

            Button(action: { Task { await restart() } }) {
                HStack(spacing: 10) {
                    Image(systemName: phase == .listening ? "stop.fill" : "mic.fill")
                        .font(.system(size: 18, weight: .black))
                    Text(phase == .listening ? "Arrêter" : "Reparler")
                        .font(.system(size: 16, weight: .bold))
                }
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .frame(height: 64)
                .background(Color.white)
                .clipShape(Capsule())
            }
            .buttonStyle(.plain)
            .disabled(phase == .thinking || phase == .speaking)
        }
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

    private func restart() async {
        // If we're actively listening, the user wants to stop.
        if phase == .listening || voice.isListening {
            player.stop()
            voice.stopListening()
            phase = .idle
            return
        }
        // Otherwise (idle, error, after-speaking) → start a fresh listen.
        player.stop()
        // Small breath so the audio session has time to switch from playback
        // back to record after a TTS reply finished.
        try? await Task.sleep(nanoseconds: 200_000_000)
        beginListening()
    }

    private func beginListening() {
        reply = ""
        errorText = nil
        phase = .listening
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
            phase = .speaking
            player.speak(result.spokenReply)
            if let destination = result.destination, !destination.isEmpty {
                onDestination(destination)
            }
        } catch {
            phase = .error
            errorText = error.localizedDescription
        }
    }
}

/// Big animated mic button on the map — launches the `VoiceOverlay`. Sits next
/// to the STIB AI chat button.
struct MapVoiceFloatingButton: View {
    let action: () -> Void
    @State private var pulse = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(LinearGradient(
                        colors: [Color(hex: "#FF5A5F"), Color(hex: "#D63A3F")],
                        startPoint: .top, endPoint: .bottom
                    ))
                    .frame(width: 60, height: 60)
                Circle()
                    .stroke(Color.white.opacity(0.7), lineWidth: 2)
                    .frame(width: 70, height: 70)
                    .scaleEffect(pulse ? 1.10 : 0.95)
                    .opacity(pulse ? 0 : 0.7)
                    .animation(.easeOut(duration: 1.6).repeatForever(autoreverses: false), value: pulse)
                Image(systemName: "mic.fill")
                    .font(.system(size: 22, weight: .black))
                    .foregroundStyle(.white)
            }
            .shadow(color: Color(hex: "#FF5A5F").opacity(0.45), radius: 10, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("Parler à Mobi")
        .onAppear { pulse = true }
    }
}
