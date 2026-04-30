import Foundation
import AVFoundation
import Speech

@MainActor
final class StibiVoiceCommandManager: NSObject, ObservableObject {
    @Published private(set) var transcript = ""
    @Published private(set) var isListening = false
    @Published private(set) var authorizationDenied = false

    private let audioEngine = AVAudioEngine()
    private let recognizer = SFSpeechRecognizer(locale: Locale(identifier: "fr-BE"))
    private var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?
    private let audioSession = AVAudioSession.sharedInstance()
    private var finalTextHandler: ((String) -> Void)?

    func toggleListening(onFinalText: @escaping (String) -> Void) async {
        if isListening {
            finalTextHandler = onFinalText
            stopListening()
        } else {
            await beginListening(onFinalText: onFinalText)
        }
    }

    func beginListening(onFinalText: @escaping (String) -> Void) async {
        guard !isListening else { return }
        finalTextHandler = onFinalText
        await startListening()
    }

    func reset() {
        transcript = ""
        authorizationDenied = false
        finalTextHandler = nil
    }

    private func startListening() async {
        let speechStatus = await requestSpeechAuthorization()
        let micGranted = await requestMicrophoneAuthorization()

        guard speechStatus == .authorized, micGranted, recognizer != nil else {
            authorizationDenied = true
            return
        }

        authorizationDenied = false
        transcript = ""
        tearDownRecognition()

        do {
            try configureAudioSession()
        } catch {
            print("Stibi voice audio session setup failed: \(error.localizedDescription)")
            authorizationDenied = true
            return
        }

        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        request.requiresOnDeviceRecognition = false
        recognitionRequest = request

        let inputNode = audioEngine.inputNode
        let recordingFormat = bestRecordingFormat(for: inputNode)
        guard recordingFormat.sampleRate > 0, recordingFormat.channelCount > 0 else {
            print("Stibi voice invalid input format: \(recordingFormat)")
            authorizationDenied = true
            return
        }

        inputNode.removeTap(onBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { [weak self] buffer, _ in
            self?.recognitionRequest?.append(buffer)
        }

        audioEngine.prepare()
        do {
            try audioEngine.start()
            isListening = true
        } catch {
            inputNode.removeTap(onBus: 0)
            tearDownRecognition()
            authorizationDenied = true
            return
        }

        recognitionTask = recognizer?.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor in
                guard let self else { return }
                if let result {
                    self.transcript = result.bestTranscription.formattedString
                    if result.isFinal {
                        self.stopListening()
                    }
                }

                if error != nil {
                    self.stopListening()
                }
            }
        }
    }

    private func stopListening() {
        let finalText = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        isListening = false
        audioEngine.stop()
        audioEngine.inputNode.removeTap(onBus: 0)
        tearDownRecognition()
        try? audioSession.setActive(false, options: [.notifyOthersOnDeactivation])

        if !finalText.isEmpty {
            finalTextHandler?(finalText)
        }
        finalTextHandler = nil
    }

    private func configureAudioSession() throws {
        try audioSession.setCategory(.playAndRecord, mode: .measurement, options: [.duckOthers, .defaultToSpeaker, .allowBluetoothHFP])
        try audioSession.setPreferredSampleRate(44_100)
        try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
    }

    private func bestRecordingFormat(for inputNode: AVAudioInputNode) -> AVAudioFormat {
        let preferred = inputNode.inputFormat(forBus: 0)
        if preferred.sampleRate > 0, preferred.channelCount > 0 {
            return preferred
        }

        let fallback = inputNode.outputFormat(forBus: 0)
        if fallback.sampleRate > 0, fallback.channelCount > 0 {
            return fallback
        }

        return AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: 44_100,
            channels: 1,
            interleaved: false
        ) ?? fallback
    }

    private func tearDownRecognition() {
        recognitionRequest?.endAudio()
        recognitionTask?.cancel()
        recognitionTask = nil
        recognitionRequest = nil
    }

    private func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }

    private func requestMicrophoneAuthorization() async -> Bool {
        await withCheckedContinuation { continuation in
            AVAudioApplication.requestRecordPermission { granted in
                continuation.resume(returning: granted)
            }
        }
    }
}
