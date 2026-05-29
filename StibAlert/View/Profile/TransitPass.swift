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
        subscriptionLabel: "Abonnement STIB",
        cardNumber: "",
        expiryDate: nil,
        nfcFingerprint: nil,
        nfcTagType: nil,
        lastScannedAt: nil
    )

    var maskedCardNumber: String {
        let digits = cardNumber.filter(\.isNumber)
        guard !digits.isEmpty else { return "Ajoutez votre numero" }
        if digits.count <= 4 { return digits }

        let suffix = String(digits.suffix(4))
        return "•••• •••• •••• \(suffix)"
    }

    var formattedExpiryDate: String {
        guard let expiryDate else { return "Ajouter l'expiration" }
        let formatter = DateFormatter()
        formatter.locale = AppLocale.current
        formatter.dateFormat = "dd.MM.yyyy"
        return formatter.string(from: expiryDate)
    }

    var statusLabel: String {
        guard let expiryDate else { return "A completer" }
        let calendar = Calendar.current
        let now = calendar.startOfDay(for: Date())
        let expiry = calendar.startOfDay(for: expiryDate)

        if expiry < now { return "Expire" }
        if let days = calendar.dateComponents([.day], from: now, to: expiry).day, days <= 14 {
            return "Expire bientot"
        }
        return "Valide"
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
            return "Scannez ici"
        case .scanning:
            return "Lecture en cours"
        case .detected:
            return "Carte detectee"
        case .partial:
            return "Lecture incomplete"
        case .error:
            return "Lecture NFC indisponible"
        }
    }

    var message: String {
        switch self {
        case .idle:
            return "Approchez votre carte MoBIB de la partie haute de l'iPhone pour l'associer au profil."
        case .scanning:
            return "Gardez la carte immobile 1 a 2 secondes. Si rien ne se passe, deplacez-la legerement."
        case .detected(let payload):
            return "Tag \(payload.tagType) detecte \(Self.relativeText(from: payload.scannedAt))."
        case .partial:
            return "Le tag a ete lu, mais certaines informations restent incompletes. Completez manuellement si besoin."
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
