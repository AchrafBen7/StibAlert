import Foundation

struct TransitPass: Codable, Equatable {
    var holderName: String
    var subscriptionLabel: String
    var cardNumber: String
    var expiryDate: Date?
    var nfcFingerprint: String?
    var nfcTagType: String?
    var lastScannedAt: Date?

    static let empty = TransitPass(
        holderName: "",
        subscriptionLabel: "",
        cardNumber: "",
        expiryDate: nil,
        nfcFingerprint: nil,
        nfcTagType: nil,
        lastScannedAt: nil
    )

    var maskedCardNumber: String {
        let digits = cardNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return AppLocalizer.string("transit_pass.card.add_number", defaultValue: "Ajoutez votre numéro") }
        if digits.count <= 4 { return digits }

        let suffix = String(digits.suffix(4))
        return "•••• •••• •••• \(suffix)"
    }

    var formattedExpiryDate: String {
        guard let expiryDate else { return AppLocalizer.string("transit_pass.card.add_expiry", defaultValue: "Ajouter l'expiration") }
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: expiryDate)
    }

    var statusLabel: String {
        guard let expiryDate else {
            // Carte scannée (empreinte présente) mais sans date d'expiration
            // lisible sur la puce → "Liée" plutôt que "À compléter" : le scan a
            // bien rattaché la carte physique au profil.
            if let fingerprint = nfcFingerprint, !fingerprint.isEmpty {
                return AppLocalizer.string("transit_pass.status.linked_short", defaultValue: "Liée")
            }
            return AppLocalizer.string("transit_pass.status.todo", defaultValue: "A completer")
        }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let expiry = calendar.startOfDay(for: expiryDate)

        if expiry < now { return AppLocalizer.string("transit_pass.status.expired", defaultValue: "Expiré") }
        if let days = calendar.dateComponents([.day], from: now, to: expiry).day, days <= 14 {
            return AppLocalizer.string("transit_pass.status.expiring", defaultValue: "Expire bientôt")
        }
        return AppLocalizer.string("transit_pass.status.valid", defaultValue: "Valide")
    }
}

enum TransitPassStorage {
    private static let key = "stib.transit-pass"

    static func load() -> TransitPass {
        guard
            let data = UserDefaults.standard.data(forKey: key),
            var pass = try? JSONDecoder().decode(TransitPass.self, from: data)
        else {
            return .empty
        }
        // BUG #5 — Restaure le fingerprint depuis Keychain (stocké séparément
        // pour ne PAS apparaître dans le JSON UserDefaults qui peut être
        // lu via capture d'écran / backup iCloud non chiffré).
        pass.nfcFingerprint = KeychainHelper.readMobibFingerprint()
        return pass
    }

    static func save(_ pass: TransitPass) {
        // Persist le fingerprint en Keychain et le retire du JSON avant
        // sérialisation. Si le user a wipé le pass (nfcFingerprint nil),
        // on delete aussi en Keychain pour pas garder un secret orphelin.
        if let fingerprint = pass.nfcFingerprint, !fingerprint.isEmpty {
            KeychainHelper.saveMobibFingerprint(fingerprint)
        } else {
            KeychainHelper.deleteMobibFingerprint()
        }
        var stripped = pass
        stripped.nfcFingerprint = nil
        guard let data = try? JSONEncoder().encode(stripped) else { return }
        UserDefaults.standard.set(data, forKey: key)
    }
}

struct MobibScanPayload: Equatable {
    let fingerprint: String
    let tagType: String
    let scannedAt: Date
    let debugSummary: String
    let isPartial: Bool
    // Données Calypso/MoBIB lues réellement sur la carte (optionnelles : les
    // tags non-Calypso ne les remplissent pas).
    var aid: String? = nil
    var cardSerial: String? = nil
    var lastValidations: [String] = []
    var rawDump: String? = nil
    // Décodage Calypso/MoBIB calé sur le format réel STIB (best-effort).
    var networkLabel: String? = nil   // ex: "STIB-MIVB"
    var contractCount: Int = 0        // nb de contrats lus (SFI 09)
    var fileCount: Int = 0            // nb total de fichiers avec données
    var holderBirthDate: Date? = nil  // date de naissance (BCD, env SFI 07)
    var calypsoVersion: Int? = nil    // version appli Calypso (6 bits env)
    var country: String? = nil        // pays émetteur (ex: "Belgique")
    var validityEnd: Date? = nil      // fin de validité de la carte (env, b42)
    var cardNumber: String? = nil     // n° de carte imprimé (serial BCD, env)
}

enum MobibScanState: Equatable {
    case idle
    case scanning
    case detected(MobibScanPayload)
    case partial(MobibScanPayload)
    case error(String)

    var title: String {
        switch self {
        case .idle:
            return AppLocalizer.string("transit_pass.scan.idle.title", defaultValue: "Scannez ici")
        case .scanning:
            return AppLocalizer.string("transit_pass.scan.scanning.title", defaultValue: "Lecture en cours")
        case .detected:
            return AppLocalizer.string("transit_pass.scan.detected.title", defaultValue: "Carte détectée")
        case .partial:
            return AppLocalizer.string("transit_pass.scan.partial.title", defaultValue: "Lecture incomplète")
        case .error:
            return AppLocalizer.string("transit_pass.scan.error.title", defaultValue: "Lecture NFC indisponible")
        }
    }

    var message: String {
        switch self {
        case .idle:
            return AppLocalizer.string("transit_pass.scan.idle.msg", defaultValue: "Approchez votre carte MoBIB de la partie haute de l'iPhone pour l'associer au profil.")
        case .scanning:
            return AppLocalizer.string("transit_pass.scan.scanning.msg", defaultValue: "Gardez la carte immobile 1 à 2 secondes. Si rien ne se passe, déplacez-la légèrement.")
        case .detected(let payload):
            return AppLocalizer.format("transit_pass.scan.detected.msg", defaultValue: "Tag %@ détecté %@.", payload.tagType, Self.relativeText(from: payload.scannedAt))
        case .partial:
            return AppLocalizer.string("transit_pass.scan.partial.msg", defaultValue: "Le tag a été lu, mais certaines informations restent incomplètes. Complétez manuellement si besoin.")
        case .error(let message):
            return message
        }
    }

    var icon: String {
        switch self {
        case .idle:
            return "wave.3.right.circle"
        case .scanning:
            return "dot.radiowaves.left.and.right"
        case .detected:
            return "checkmark.seal.fill"
        case .partial:
            return "exclamationmark.circle.fill"
        case .error:
            return "exclamationmark.triangle.fill"
        }
    }

    var accentHex: String {
        switch self {
        case .idle:
            return "#7CB2FF"
        case .scanning:
            return "#73F0D2"
        case .detected:
            return "#73F0D2"
        case .partial:
            return "#FFB347"
        case .error:
            return "#FF7A7A"
        }
    }

    private static func relativeText(from date: Date) -> String {
        let formatter = RelativeDateTimeFormatter()
        formatter.locale = AppLocale.current
        formatter.unitsStyle = .short
        return formatter.localizedString(for: date, relativeTo: Date())
    }
}

struct MobibDebugEvent: Identifiable, Equatable {
    let id = UUID()
    let date: Date
    let level: String
    let message: String
}
