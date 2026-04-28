import Foundation
#if canImport(CoreNFC)
import CoreNFC
#endif

@MainActor
final class MobibNFCReader: NSObject, ObservableObject {
    @Published private(set) var isScanning = false
    @Published private(set) var lastScan: MobibScanPayload?
    @Published private(set) var errorMessage: String?
    @Published private(set) var scanState: MobibScanState = .idle
    @Published private(set) var debugEvents: [MobibDebugEvent] = []

#if canImport(CoreNFC)
    private var session: NFCTagReaderSession?
#endif

    func beginScan() {
#if canImport(CoreNFC)
        guard NFCTagReaderSession.readingAvailable else {
            errorMessage = "La lecture NFC n'est pas disponible sur cet iPhone."
            scanState = .error(errorMessage ?? "Lecture NFC indisponible.")
            appendDebug(level: "error", "NFC non disponible sur cet iPhone.")
            return
        }

        errorMessage = nil
        isScanning = true
        scanState = .scanning
        appendDebug(level: "info", "Session NFC demarree.")
        guard let readerSession = NFCTagReaderSession(pollingOption: .iso14443, delegate: self) else {
            isScanning = false
            errorMessage = "Impossible de demarrer la lecture NFC sur cet appareil."
            scanState = .error(errorMessage ?? "Impossible de demarrer la lecture NFC.")
            appendDebug(level: "error", "Creation de session NFC impossible.")
            return
        }
        readerSession.alertMessage = "Approchez votre carte MoBIB de la partie haute de l'iPhone."
        self.session = readerSession
        readerSession.begin()
#else
        errorMessage = "Core NFC n'est pas disponible dans cette configuration."
        scanState = .error(errorMessage ?? "Core NFC indisponible.")
        appendDebug(level: "error", "Core NFC n'est pas disponible dans cette configuration.")
#endif
    }

    func clearDebugLog() {
        debugEvents.removeAll()
    }

    private func appendDebug(level: String, _ message: String) {
        debugEvents.insert(
            MobibDebugEvent(date: Date(), level: level.uppercased(), message: message),
            at: 0
        )
        debugEvents = Array(debugEvents.prefix(12))
        print("[MobibNFC][\(level.uppercased())] \(message)")
    }
}

#if canImport(CoreNFC)
extension MobibNFCReader: NFCTagReaderSessionDelegate {
    nonisolated func tagReaderSessionDidBecomeActive(_ session: NFCTagReaderSession) {}

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didInvalidateWithError error: Error) {
        Task { @MainActor in
            self.isScanning = false
            self.session = nil

            guard let nfcError = error as? NFCReaderError else {
                self.errorMessage = error.localizedDescription
                self.scanState = .error(error.localizedDescription)
                self.appendDebug(level: "error", "Session invalidee: \(error.localizedDescription)")
                return
            }

            switch nfcError.code {
            case .readerSessionInvalidationErrorFirstNDEFTagRead, .readerSessionInvalidationErrorUserCanceled:
                self.scanState = self.lastScan.map { $0.isPartial ? .partial($0) : .detected($0) } ?? .idle
                self.appendDebug(level: "info", "Session NFC terminee par l'utilisateur ou tag detecte.")
                break
            default:
                self.errorMessage = nfcError.localizedDescription
                self.scanState = .error(nfcError.localizedDescription)
                self.appendDebug(level: "error", "Erreur NFC: \(nfcError.localizedDescription)")
            }
        }
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else { return }

        session.connect(to: firstTag) { error in
            if let error {
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }

            let payload = Self.buildPayload(from: firstTag)
            Task { @MainActor in
                self.lastScan = payload
                self.isScanning = false
                self.session = nil
                self.scanState = payload.isPartial ? .partial(payload) : .detected(payload)
                self.appendDebug(level: payload.isPartial ? "warning" : "success", payload.debugSummary)
            }
            session.alertMessage = payload.isPartial
                ? "Tag detecte. Completez les informations manquantes dans le profil."
                : "Carte detectee et associee a votre profil."
            session.invalidate()
        }
    }

    nonisolated private static func buildPayload(from tag: NFCTag) -> MobibScanPayload {
        switch tag {
        case .miFare(let mifareTag):
            let fingerprint = hexString(from: mifareTag.identifier)
            return .init(
                fingerprint: fingerprint,
                tagType: "MIFARE / ISO14443",
                scannedAt: Date(),
                debugSummary: "MIFARE detecte • id \(fingerprint.prefix(16))",
                isPartial: false
            )
        case .iso7816(let iso7816Tag):
            let chunks = [
                iso7816Tag.historicalBytes ?? Data(),
                iso7816Tag.applicationData ?? Data(),
                Data(iso7816Tag.identifier)
            ]
            let fingerprint = chunks
                .filter { !$0.isEmpty }
                .map(hexString(from:))
                .joined(separator: "-")
            let isPartial = fingerprint.isEmpty

            return .init(
                fingerprint: fingerprint.isEmpty ? "ISO7816" : fingerprint,
                tagType: "ISO7816 / Calypso",
                scannedAt: Date(),
                debugSummary: isPartial
                    ? "ISO7816 detecte • aucune empreinte exploitable retournee"
                    : "ISO7816 detecte • empreinte \(fingerprint.prefix(24))",
                isPartial: isPartial
            )
        case .feliCa(let feliCaTag):
            let fingerprint = hexString(from: feliCaTag.currentIDm)
            return .init(
                fingerprint: fingerprint,
                tagType: "FeliCa",
                scannedAt: Date(),
                debugSummary: "FeliCa detecte • id \(fingerprint.prefix(16))",
                isPartial: false
            )
        case .iso15693(let iso15693Tag):
            let fingerprint = hexString(from: Data(iso15693Tag.identifier))
            return .init(
                fingerprint: fingerprint,
                tagType: "ISO15693",
                scannedAt: Date(),
                debugSummary: "ISO15693 detecte • id \(fingerprint.prefix(16))",
                isPartial: false
            )
        @unknown default:
            return .init(
                fingerprint: "TAG-UNKNOWN",
                tagType: "Tag NFC",
                scannedAt: Date(),
                debugSummary: "Type de tag NFC non reconnu.",
                isPartial: true
            )
        }
    }

    nonisolated private static func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
#endif
