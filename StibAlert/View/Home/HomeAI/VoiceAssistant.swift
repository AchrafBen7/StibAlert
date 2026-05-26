import AVFoundation
import Foundation
import Speech

/// Hands-free voice input wrapper around `SFSpeechRecognizer` (fr-FR). Live
/// partial transcripts are published so the UI can show what's being heard;
/// `startListening(onFinal:)` fires once the user stops speaking.
@MainActor
final class VoiceAssistant: NSObject, ObservableObject {
    @Published private(set) var transcript: String = ""
    @Published private(set) var isListening: Bool = false
    @Published private(set) var lastError: String?

    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-FR"))
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
    func startListening(onFinal: @escaping (String) -> Void) {
        guard !isListening else { return }
        guard let recognizer, recognizer.isAvailable else {
            lastError = "Reconnaissance vocale indisponible."
            return
        }

        transcript = ""
        lastError = nil
        lastTranscriptUpdate = Date()

        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            lastError = "Audio session: \(error.localizedDescription)"
            return
        }

        let req = SFSpeechAudioBufferRecognitionRequest()
        req.shouldReportPartialResults = true
        req.requiresOnDeviceRecognition = false
        request = req

        let input = audioEngine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.removeTap(onBus: 0)
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
                    // "no speech detected" / cancellation → ignore
                    if code != 203 && code != 216 && code != 1110 {
                        self.lastError = "Reco: \(error.localizedDescription)"
                    }
                    self.stopListening()
                }
            }
        }

        // Silence watchdog: if no transcript update for 1.4s after the user
        // started speaking, treat the current transcript as final.
        silenceTimer?.invalidate()
        silenceTimer = Timer.scheduledTimer(withTimeInterval: 0.3, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isListening else { return }
                guard !self.transcript.isEmpty else { return }
                if Date().timeIntervalSince(self.lastTranscriptUpdate) > 1.4 {
                    let final = self.transcript
                    self.stopListening()
                    onFinal(final)
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
