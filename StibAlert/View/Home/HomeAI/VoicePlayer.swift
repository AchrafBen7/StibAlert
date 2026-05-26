import AVFoundation
import Foundation

/// Text-to-speech wrapper around `AVSpeechSynthesizer` (fr-FR by default).
/// Strips markdown/emoji before speaking so the voice never reads "deux
/// étoiles ligne 81 deux étoiles".
@MainActor
final class VoicePlayer: NSObject, ObservableObject {
    @Published private(set) var isSpeaking: Bool = false

    private let synth = AVSpeechSynthesizer()

    override init() {
        super.init()
        synth.delegate = self
    }

    func speak(_ text: String, language: String = "fr-FR") {
        let cleaned = Self.cleanForSpeech(text)
        guard !cleaned.isEmpty else { return }
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }

        // Make sure the audio session is playback-friendly (mixes politely
        // with other apps; respects the user's silent switch via .duckOthers).
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .voicePrompt, options: [.duckOthers, .mixWithOthers])
        try? session.setActive(true, options: .notifyOthersOnDeactivation)

        let utterance = AVSpeechUtterance(string: cleaned)
        utterance.voice = Self.preferredVoice(language: language)
        utterance.rate = 0.5
        utterance.pitchMultiplier = 1.0
        utterance.preUtteranceDelay = 0.05
        synth.speak(utterance)
    }

    func stop() {
        if synth.isSpeaking { synth.stopSpeaking(at: .immediate) }
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Picks the best installed French voice — enhanced/premium if available,
    /// otherwise the system default. Avoids reaching for a hardcoded id that
    /// might not be present on the device.
    private static func preferredVoice(language: String) -> AVSpeechSynthesisVoice? {
        let candidates = AVSpeechSynthesisVoice.speechVoices().filter { $0.language == language }
        if let premium = candidates.first(where: { $0.quality == .premium }) { return premium }
        if let enhanced = candidates.first(where: { $0.quality == .enhanced }) { return enhanced }
        return AVSpeechSynthesisVoice(language: language) ?? candidates.first
    }

    /// Strip markdown syntax + emoji + STIB-AI tag markers so the synthesizer
    /// doesn't pronounce them.
    static func cleanForSpeech(_ raw: String) -> String {
        var text = raw

        // Remove [[L:NUM]] / [[L:NUM|label]] line-code markers.
        text = text.replacingOccurrences(of: #"\[\[L:[^\]]+\]\]"#, with: "", options: .regularExpression)
        // Remove markdown links [label](url) → keep label only.
        text = text.replacingOccurrences(of: #"\[([^\]]+)\]\([^\)]+\)"#, with: "$1", options: .regularExpression)
        // Strip emphasis markers (*, _, `).
        text = text.replacingOccurrences(of: #"[\*_`]"#, with: "", options: .regularExpression)
        // Strip headings / bullets at the start of lines.
        text = text.replacingOccurrences(of: #"(?m)^\s*(#+|-|\*|•)\s*"#, with: "", options: .regularExpression)
        // Collapse extra whitespace.
        text = text.replacingOccurrences(of: #"\s+"#, with: " ", options: .regularExpression)
        // Drop most emoji & symbols (keep punctuation + accented latin).
        text = String(text.unicodeScalars.filter { scalar in
            if scalar.properties.isEmojiPresentation || scalar.properties.isEmoji && scalar.value > 0x2700 {
                return false
            }
            return true
        })
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

extension VoicePlayer: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = true }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in self.isSpeaking = false }
    }
}
