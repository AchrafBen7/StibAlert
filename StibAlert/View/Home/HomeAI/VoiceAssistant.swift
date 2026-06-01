import AVFoundation
import Foundation
import Speech

/// Hands-free voice input wrapper around `SFSpeechRecognizer`. Live
/// partial transcripts are published so the UI can show what's being heard;
/// `startListening(onFinal:)` fires once the user stops speaking.
@MainActor
final class VoiceAssistant: NSObject, ObservableObject {
    /// Pre-warm utilisé au démarrage de l'app : charge le modèle SFSpeechRecognizer
    /// hors thread main avant le premier tap micro. Sans ça, le 1er
    /// `startListening()` doit JIT-charger les ressources Speech.framework
    /// (~200-300 ms perçu comme un freeze de l'overlay). Idempotent.
    nonisolated static func prewarm() {
        Task.detached(priority: .utility) {
            // Instancier un SFSpeechRecognizer + s'assurer que availability
            // est connue charge le datastore Speech en background. Peut
            // échouer en silence si la locale n'est pas dispo offline.
            _ = SFSpeechRecognizer(locale: Locale(identifier: AppLocale.speechIdentifier))?.isAvailable
        }
    }

    @Published private(set) var transcript: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var lastError: String?

    private var recognizer: SFSpeechRecognizer? {
        SFSpeechRecognizer(locale: Locale(identifier: AppLocale.speechIdentifier))
    }
    private let audioEngine = AVAudioEngine()
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var task: SFSpeechRecognitionTask?
    private var silenceTimer: Timer?
    private var lastTranscriptUpdate: Date = .distantPast

    /// Requests both Speech and microphone authorisations up-front. Safe to
    /// call multiple times.
    func requestAuthorization() async -> Bool {
        let speechOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            SFSpeechRecognizer.requestAuthorization { status in
                cont.resume(returning: status == .authorized)
            }
        }
        let micOK = await withCheckedContinuation { (cont: CheckedContinuation<Bool, Never>) in
            AVAudioApplication.requestRecordPermission { granted in
                cont.resume(returning: granted)
            }
        }
        return speechOK && micOK
    }

    /// Starts a recognition task. `onFinal` is called once the user stops
    /// talking (silence > 1.4s) OR when the recognizer marks the result final.
    /// Always cleans up any prior session first so a re-tap is reliable.
    func startListening(onFinal: @escaping (String) -> Void) {
        // Defensive: force-tear-down any stale session before starting a new
        // one (e.g. after a failed first attempt or after TTS). Without this,
        // tapping "Reparler" sometimes fell into the !isListening guard
        // because state was inconsistent across the engine + recognizer.
        cleanupAudio()
        isListening = false

        guard let recognizer else {
            lastError = "Reconnaissance vocale indisponible sur cet appareil."
            return
        }
        guard recognizer.isAvailable else {
            lastError = "Reconnaissance vocale indisponible (vérifie ta connexion)."
            return
        }

        transcript = ""
        lastError = nil
        lastTranscriptUpdate = Date()
        let listenStart = Date()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "Audio: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        request = req

        let input = audioEngine.inputNode
        input.removeTap(onBus: 0)
        // outputFormat / inputFormat can return a zero-sampleRate format on
        // the iOS simulator (no real audio hardware) — installing a tap with
        // that crashes inside CoreAudio with
        // `IsFormatSampleRateAndChannelCountValid`. We validate first and
        // fail with a clear message instead of aborting the whole app.
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            lastError = "Micro indisponible (simulateur ?). Teste sur un vrai iPhone, ou autorise l'entrée audio Mac dans les réglages du simulateur."
            cleanupAudio()
            return
        }
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
            self?.request?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
        } catch {
            lastError = "Micro: \(error.localizedDescription)"
            cleanupAudio()
            return
        }

        isListening = true

        task = recognizer.recognitionTask(with: req) { [weak self] result, error in
            guard let self else { return }
            Task { @MainActor in
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    self.lastTranscriptUpdate = Date()
                    if result.isFinal {
                        let final = self.transcript
                        self.stopListening()
                        if !final.isEmpty { onFinal(final) }
                    }
                }
                if let error {
                    let code = (error as NSError).code
                    // Ignored codes — all are normal cancellations triggered
                    // by us stopping listening, not real failures:
                    //   203, 216, 301 → "recognition request was cancelled"
                    //   1110          → "no speech detected"
                    let cancellations: Set<Int> = [203, 216, 301, 1110]
                    if !cancellations.contains(code) {
                        self.lastError = "Reco (\(code)): \(error.localizedDescription)"
                    }
                    self.stopListening()
                }
            }
        }

        // Combined watchdog:
        // - silence-after-speech: 2.5s of no transcript update once started →
        //   final (more forgiving than 1.4s: gives time to breathe mid-sentence).
        // - no-speech-at-all: 12s with empty transcript → surface "Je n'entends
        //   rien" (was 7s, but the recogniser sometimes takes 2-3s to warm up
        //   on a fresh tap so the user thought it wasn't listening).
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                if !self.transcript.isEmpty {
                    if Date().timeIntervalSince(self.lastTranscriptUpdate) > 2.5 {
                        let final = self.transcript
                        self.stopListening()
                        onFinal(final)
                    }
                } else if Date().timeIntervalSince(listenStart) > 12 {
                    self.lastError = "Je n'ai rien entendu. Vérifie le micro et réessaie."
                    self.stopListening()
                }
            }
        }
    }

    func stopListening() {
        guard isListening else { return }
        cleanupAudio()
        isListening = false
    }

    private func cleanupAudio() {
        silenceTimer?.invalidate()
        silenceTimer = nil
        if audioEngine.isRunning { audioEngine.stop() }
        audioEngine.inputNode.removeTap(onBus: 0)
        request?.endAudio()
        request = nil
        task?.cancel()
        task = nil
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }
}
