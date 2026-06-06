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

        // BUG #4 — Si une session précédente est encore vivante (cas où user
        // cancel le system sheet et re-tap rapidement avant que le delegate
        // ait nettoyé `self.session`), on l'invalide explicitement avant
        // d'en créer une nouvelle. Évite l'effet "rien ne se passe au re-tap"
        // observé sur iOS < 16 quand la 1ère session bloque encore le NFC.
        if let existing = self.session {
            existing.invalidate()
            self.session = nil
            appendDebug(level: "warning", "Session NFC précédente forcée à se terminer avant re-scan.")
        }

        errorMessage = nil
        isScanning = true
        scanState = .scanning
        appendDebug(level: "info", "Session NFC démarrée (polling ISO14443 + ISO15693).")
        // MoBIB is Calypso over ISO 14443 Type B. FeliCa (.iso18092) would
        // need com.apple.developer.nfc.readersession.felica.systemcodes
        // declared in entitlements, which we don't have — iOS refuses the
        // session entirely if we ask for FeliCa without it. ISO 15693 is
        // free to combine and helps for some MoBIB revisions.
        let pollingOptions: NFCTagReaderSession.PollingOption = [.iso14443, .iso15693]
        guard let readerSession = NFCTagReaderSession(pollingOption: pollingOptions, delegate: self) else {
            isScanning = false
            errorMessage = "Impossible de démarrer la lecture NFC sur cet appareil."
            scanState = .error(errorMessage ?? "Impossible de démarrer la lecture NFC.")
            appendDebug(level: "error", "Création de session NFC impossible.")
            return
        }
        readerSession.alertMessage = "Tiens ta MoBIB contre l'arrière du haut de l'iPhone (zone caméra), sans bouger 1-2 secondes."
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
                let friendly = Self.friendlyMessage(for: error)
                self.errorMessage = friendly
                self.scanState = .error(friendly)
                self.appendDebug(level: "error", "Session invalidée: \(error.localizedDescription)")
                return
            }

            switch nfcError.code {
            case .readerSessionInvalidationErrorFirstNDEFTagRead,
                 .readerSessionInvalidationErrorUserCanceled:
                // User dismissed the system sheet or a tag was detected — keep
                // the scan state aligned with whatever last result we have.
                self.scanState = self.lastScan.map { $0.isPartial ? .partial($0) : .detected($0) } ?? .idle
                self.appendDebug(level: "info", "Session NFC terminée par l'utilisateur ou tag detecté.")
            case .readerSessionInvalidationErrorSessionTimeout:
                let msg = "Aucune carte détectée. Approche la MoBIB de la partie haute de l'iPhone et garde-la immobile."
                self.errorMessage = msg
                self.scanState = .error(msg)
                self.appendDebug(level: "warning", "Timeout NFC — aucune carte présentée.")
            case .readerErrorUnsupportedFeature:
                let msg = "Ton iPhone ne prend pas en charge la lecture NFC compatible MoBIB."
                self.errorMessage = msg
                self.scanState = .error(msg)
                self.appendDebug(level: "error", "NFC non supporté sur cet appareil.")
            default:
                let friendly = Self.friendlyMessage(for: nfcError)
                self.errorMessage = friendly
                self.scanState = .error(friendly)
                self.appendDebug(level: "error", "Erreur NFC: \(nfcError.localizedDescription)")
            }
        }
    }

    /// Translates the cryptic system NFC errors into something a Brussels
    /// commuter can actually act on. iOS sometimes returns
    /// "Impossible de lire la carte car elle n'est pas valide" for what is
    /// really a timeout or an antenna placement issue — that copy is far too
    /// alarming for a UX entry point.
    static func friendlyMessage(for error: Error) -> String {
        let raw = error.localizedDescription.lowercased()
        if raw.contains("timeout") || raw.contains("session") {
            return "Aucune carte détectée. Approche la MoBIB de la partie haute de l'iPhone."
        }
        if raw.contains("invalide") || raw.contains("invalid") || raw.contains("valide") {
            return "Impossible de lire cette carte. Glisse-la doucement autour du haut de l'iPhone, ou complète manuellement ci-dessous."
        }
        if raw.contains("annul") || raw.contains("cancel") {
            return "Lecture annulée."
        }
        return "La lecture n'a pas pu se faire. Réessaie ou complète manuellement."
    }

    nonisolated func tagReaderSession(_ session: NFCTagReaderSession, didDetect tags: [NFCTag]) {
        guard let firstTag = tags.first else { return }

        Task {
            do {
                try await session.connect(to: firstTag)
            } catch {
                await MainActor.run {
                    self.appendDebug(level: "error", "Connexion au tag échouée: \(error.localizedDescription)")
                }
                session.invalidate(errorMessage: error.localizedDescription)
                return
            }

            // MoBIB = Calypso (ISO 7816). On LIT réellement la carte (SELECT de
            // l'application transport + READ RECORD) pour en sortir un max
            // d'infos : dernières validations + fichiers bruts. Les autres types
            // de tag retombent sur l'empreinte UID seule.
            let payload: MobibScanPayload
            var extraDebug: [String] = []
            if case let .iso7816(iso) = firstTag {
                let result = await Self.readCalypso(iso)
                extraDebug = result.debug
                payload = Self.buildCalypsoPayload(tag: iso, result: result)
            } else {
                payload = Self.buildPayload(from: firstTag)
            }

            await MainActor.run {
                for line in extraDebug { self.appendDebug(level: "info", line) }
                if payload.aid != nil {
                    var insight = "Décodé: \(payload.networkLabel ?? "MoBIB") • \(payload.contractCount) contrats"
                    if let birth = payload.holderBirthDate {
                        let df = DateFormatter()
                        df.dateFormat = "dd/MM/yyyy"
                        insight += " • titulaire né le \(df.string(from: birth))"
                    }
                    self.appendDebug(level: "success", insight)
                }
                if !payload.lastValidations.isEmpty {
                    self.appendDebug(level: "success", "Validations: " + payload.lastValidations.joined(separator: " | "))
                }
                self.lastScan = payload
                self.isScanning = false
                self.session = nil
                self.scanState = payload.isPartial ? .partial(payload) : .detected(payload)
                self.appendDebug(level: payload.isPartial ? "warning" : "success", payload.debugSummary)
            }
            session.alertMessage = payload.isPartial
                ? "Carte lue partiellement — détails dans le profil."
                : "Carte MoBIB lue."
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

    /// Lit réellement une carte Calypso/MoBIB : SELECT de l'application
    /// transport puis READ RECORD sur les SFI usuels (environnement,
    /// événements, contrats, compteurs). Renvoie les fichiers BRUTS + des lignes
    /// de debug. Aucun décodage destructif : on ramène les octets bruts pour
    /// pouvoir caler le parsing exact sur une vraie MoBIB ensuite.
    nonisolated private static func readCalypso(
        _ tag: NFCISO7816Tag
    ) async -> (files: [(sfi: UInt8, record: Int, data: Data)], aid: String?, debug: [String]) {
        var files: [(sfi: UInt8, record: Int, data: Data)] = []
        var debug: [String] = []

        // 1) SELECT de l'application : on essaie les AID déclarés dans Info.plist.
        let aids: [(name: String, bytes: [UInt8])] = [
            ("1TIC.ICA", [0x31, 0x54, 0x49, 0x43, 0x2E, 0x49, 0x43, 0x41]),
            ("Calypso BPrime", [0xA0, 0x00, 0x00, 0x04, 0x04, 0x01, 0x25, 0x00, 0x91, 0x01]),
            ("Calypso", [0x33, 0x4D, 0x54, 0x52, 0x00, 0x10])
        ]
        var selectedAID: String?
        for aid in aids {
            let apdu = NFCISO7816APDU(
                instructionClass: 0x00, instructionCode: 0xA4,
                p1Parameter: 0x04, p2Parameter: 0x00,
                data: Data(aid.bytes), expectedResponseLength: 256
            )
            if let (resp, sw1, sw2) = try? await tag.sendCommand(apdu: apdu) {
                debug.append(String(format: "SELECT %@ → SW %02X%02X", aid.name, sw1, sw2))
                if sw1 == 0x90 && sw2 == 0x00 {
                    selectedAID = aid.name
                    if !resp.isEmpty { debug.append("  FCI: " + String(hexString(from: resp).prefix(48))) }
                    break
                }
            } else {
                debug.append("SELECT \(aid.name) → erreur I/O")
            }
        }
        guard let selectedAID else {
            debug.append("Aucune application Calypso sélectionnée (carte non MoBIB ou lecture refusée).")
            return (files: [], aid: nil, debug: debug)
        }

        // 2) READ RECORD sur un large éventail de SFI Calypso/Intercode. On
        // IGNORE les enregistrements tout-à-zéro (slots vides non utilisés de la
        // carte, ex: sfi 1A/1D) et on logge le HEX COMPLET des fichiers AVEC
        // données — c'est ce dump qui permet de caler le décodage exact MoBIB.
        let sfis: [UInt8] = [0x07, 0x06, 0x05, 0x08, 0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x19, 0x1A, 0x1B, 0x1C, 0x1D, 0x1E, 0x1F]
        var emptyCount = 0
        for sfi in sfis {
            for record in 1...5 {
                let p2 = UInt8((Int(sfi) << 3) | 0x04)
                let apdu = NFCISO7816APDU(
                    instructionClass: 0x00, instructionCode: 0xB2,
                    p1Parameter: UInt8(record), p2Parameter: p2,
                    data: Data(), expectedResponseLength: 256
                )
                guard let (resp, sw1, sw2) = try? await tag.sendCommand(apdu: apdu) else { break }
                guard sw1 == 0x90 && sw2 == 0x00 && !resp.isEmpty else { break } // 6A8x = plus de record
                if resp.allSatisfy({ $0 == 0 }) {
                    emptyCount += 1
                    continue // slot vide (non utilisé) → ignoré
                }
                files.append((sfi: sfi, record: record, data: resp))
                debug.append(String(format: "DATA sfi=%02X rec=%d (%dB): %@", sfi, record, resp.count, hexString(from: resp)))
            }
        }
        debug.append("Calypso \(selectedAID): \(files.count) fichiers AVEC DONNÉES, \(emptyCount) vides ignorés.")
        return (files: files, aid: selectedAID, debug: debug)
    }

    /// Construit le payload à partir des fichiers Calypso lus : dump brut de
    /// tous les fichiers + décodage des dernières validations (SFI 0x08).
    nonisolated private static func buildCalypsoPayload(
        tag: NFCISO7816Tag,
        result: (files: [(sfi: UInt8, record: Int, data: Data)], aid: String?, debug: [String])
    ) -> MobibScanPayload {
        let uid = hexString(from: Data(tag.identifier))
        guard let aid = result.aid, !result.files.isEmpty else {
            return MobibScanPayload(
                fingerprint: uid.isEmpty ? "ISO7816" : uid,
                tagType: "ISO7816 / Calypso",
                scannedAt: Date(),
                debugSummary: "Calypso: SELECT/lecture impossible — UID seul.",
                isPartial: true,
                cardSerial: uid.isEmpty ? nil : uid
            )
        }

        let dump = result.files
            .map { String(format: "SFI %02X rec %d: %@", $0.sfi, $0.record, hexString(from: $0.data)) }
            .joined(separator: "\n")

        var validations: [String] = []
        for file in result.files where file.sfi == 0x08 {
            if let line = CalypsoIntercode.decodeEvent(file.data).displayLine {
                validations.append(line)
            }
        }

        let serial = result.files.first { $0.sfi == 0x07 && $0.record == 1 }
            .map { String(hexString(from: $0.data).prefix(16)) }

        // Décodage calé sur une vraie MoBIB STIB :
        //  • contrats = enregistrements du fichier Contrats (SFI 09)
        //  • date de naissance du titulaire = date BCD (AAAAMMJJ) présente
        //    dans l'environnement (SFI 07) — ancre fiable, auto-validante.
        let contractCount = result.files.filter { $0.sfi == 0x09 }.count
        let network = Self.networkLabel(forAID: aid)
        let birth = result.files.first { $0.sfi == 0x07 }
            .flatMap { CalypsoIntercode.findBirthDateBCD(in: $0.data) }

        return MobibScanPayload(
            fingerprint: uid.isEmpty ? "MOBIB" : uid,
            tagType: "MoBIB / Calypso (\(aid))",
            scannedAt: Date(),
            debugSummary: "MoBIB \(network) • \(result.files.count) fichiers • \(contractCount) contrats • \(validations.count) validations",
            isPartial: false,
            aid: aid,
            cardSerial: serial,
            lastValidations: validations,
            rawDump: dump,
            networkLabel: network,
            contractCount: contractCount,
            fileCount: result.files.count,
            holderBirthDate: birth
        )
    }

    /// Libellé réseau à partir de l'AID sélectionné. 1TIC.ICA = application
    /// billettique MoBIB (Belgique) ; sur Bruxelles l'émetteur est la STIB-MIVB.
    nonisolated private static func networkLabel(forAID aid: String) -> String {
        if aid.localizedCaseInsensitiveContains("1TIC") { return "STIB-MIVB" }
        return "MoBIB / Calypso"
    }

    nonisolated private static func hexString(from data: Data) -> String {
        data.map { String(format: "%02X", $0) }.joined()
    }
}
#endif

/// Décodeur des champs Calypso/Intercode (date/heure) — sans dépendance CoreNFC,
/// donc compilable même hors NFC. Le parsing fin (type/ligne/arrêt) varie selon
/// la révision MoBIB et se cale sur un vrai dump.
enum CalypsoIntercode {
    /// Intercode compte les jours depuis le 1ᵉʳ janvier 1997 (Europe/Brussels).
    static let epoch1997: Date = {
        var c = DateComponents()
        c.year = 1997; c.month = 1; c.day = 1
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        return cal.date(from: c) ?? Date(timeIntervalSince1970: 852_076_800)
    }()

    static func date(daysSince1997 days: Int) -> Date? {
        guard days > 0, days < 40_000 else { return nil }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        return cal.date(byAdding: .day, value: days, to: epoch1997)
    }

    /// Cherche, dans l'environnement MoBIB (SFI 07), une date BCD (AAAAMMJJ) —
    /// c'est la date de naissance du titulaire dans le format STIB réel. On fait
    /// glisser une fenêtre de 32 bits (la date n'est PAS alignée sur l'octet sur
    /// MoBIB) et on retient la 1ʳᵉ valeur dont les 8 quartets sont des chiffres
    /// décimaux ET qui forme une date plausible. Auto-validante : un motif
    /// aléatoire a très peu de chances de produire une vraie AAAAMMJJ.
    static func findBirthDateBCD(in data: Data) -> Date? {
        let bytes = [UInt8](data)
        let totalBits = bytes.count * 8
        guard totalBits >= 32 else { return nil }
        func bit(_ i: Int) -> Int { (Int(bytes[i / 8]) >> (7 - i % 8)) & 1 }
        func read32(_ start: Int) -> Int {
            var v = 0
            for k in 0..<32 { v = (v << 1) | bit(start + k) }
            return v
        }
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        for off in 0...(totalBits - 32) {
            let v = read32(off)
            let nibs = (0..<8).map { (v >> (4 * (7 - $0))) & 0xF }
            if nibs.contains(where: { $0 > 9 }) { continue }
            let year = nibs[0] * 1000 + nibs[1] * 100 + nibs[2] * 10 + nibs[3]
            let month = nibs[4] * 10 + nibs[5]
            let day = nibs[6] * 10 + nibs[7]
            guard (1925...2015).contains(year), (1...12).contains(month), (1...31).contains(day) else { continue }
            var c = DateComponents()
            c.year = year; c.month = month; c.day = day
            if let d = cal.date(from: c) { return d }
        }
        return nil
    }

    struct Event {
        let date: Date?
        let minutesSinceMidnight: Int?
        var displayLine: String? {
            guard let date else { return nil }
            let df = DateFormatter()
            df.locale = Locale(identifier: "nl_BE")
            df.timeZone = TimeZone(identifier: "Europe/Brussels")
            df.dateFormat = "dd/MM/yyyy"
            var s = df.string(from: date)
            if let m = minutesSinceMidnight, m >= 0, m < 1440 {
                s += String(format: " %02d:%02d", m / 60, m % 60)
            }
            return s
        }
    }

    /// Indeling gangbaar bij Intercode-events: EventDateStamp (14 bits, dagen
    /// sinds 1997) + EventTimeStamp (11 bits, minuten sinds middernacht) aan het
    /// begin van het record.
    static func decodeEvent(_ data: Data) -> Event {
        var reader = BitReader(data)
        let days = reader.read(14)
        let minutes = reader.read(11)
        return Event(
            date: date(daysSince1997: days),
            minutesSinceMidnight: (minutes >= 0 && minutes < 1440) ? minutes : nil
        )
    }

    /// MSB-first bit-reader; read() geeft -1 bij onvoldoende data.
    struct BitReader {
        private let bytes: [UInt8]
        private var pos = 0
        init(_ data: Data) { bytes = [UInt8](data) }
        mutating func read(_ count: Int) -> Int {
            guard count > 0, count <= 32, pos + count <= bytes.count * 8 else { pos += count; return -1 }
            var value = 0
            for _ in 0..<count {
                let bit = (Int(bytes[pos / 8]) >> (7 - pos % 8)) & 1
                value = (value << 1) | bit
                pos += 1
            }
            return value
        }
    }
}
