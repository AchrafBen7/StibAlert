import Foundation

struct UtilisateurDTO: Codable, Identifiable, Equatable {
    let id: String
    let nom: String
    let email: String
    let photoProfil: String?
    let langue: String?
    let notifications: Bool?
    let role: String?
    let favoris: [String]?
    let favorisDetails: [FavoriDetailDTO]?
    let routine: CommuteRoutineDTO?
    let votes: [String]?
    let oneSignalPlayerId: String?
    let favoriteLines: [String]?
    let weeklyDigestEnabled: Bool?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, email, photoProfil, langue, notifications, role, favoris, favorisDetails, routine, votes, oneSignalPlayerId, favoriteLines, weeklyDigestEnabled
    }
}

struct CommuteRoutineDTO: Codable, Equatable {
    let enabled: Bool
    let homeLabel: String
    let workLabel: String
    let departureTime: String
    let homeStopId: String?
    let workStopId: String?

    init(
        enabled: Bool,
        homeLabel: String,
        workLabel: String,
        departureTime: String,
        homeStopId: String?,
        workStopId: String?
    ) {
        self.enabled = enabled
        self.homeLabel = homeLabel
        self.workLabel = workLabel
        self.departureTime = departureTime
        self.homeStopId = homeStopId
        self.workStopId = workStopId
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        enabled = try container.decodeIfPresent(Bool.self, forKey: .enabled) ?? false
        homeLabel = try container.decodeIfPresent(String.self, forKey: .homeLabel) ?? "Domicile"
        workLabel = try container.decodeIfPresent(String.self, forKey: .workLabel) ?? "Travail"
        departureTime = try container.decodeIfPresent(String.self, forKey: .departureTime) ?? "08:15"
        homeStopId = try container.decodeIfPresent(String.self, forKey: .homeStopId)
        workStopId = try container.decodeIfPresent(String.self, forKey: .workStopId)
    }

    private enum CodingKeys: String, CodingKey {
        case enabled, homeLabel, workLabel, departureTime, homeStopId, workStopId
    }
}

struct FavoriDetailDTO: Codable, Identifiable, Equatable {
    let id: String
    let nom: String
    let latitude: Double?
    let longitude: Double?
    let lignesDesservies: [String]?
    let status: String?
    let crowding: String?
    let signalementCount: Int?
    let primaryLine: String?
    let lastProblemType: String?
    let lastConfidence: String?
    let nextPassageMinutes: Int?
    let lastUpdatedAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case nom, latitude, longitude, lignesDesservies
        case status, crowding, signalementCount, primaryLine
        case lastProblemType, lastConfidence, nextPassageMinutes, lastUpdatedAt
    }
}

struct InscriptionRequest: Encodable {
    let nom: String
    let email: String
    let motDePasse: String
}

struct InscriptionResponse: Decodable {
    let message: String
    let activationToken: String
}

struct ActivationRequest: Encodable {
    let activationToken: String
    let activationCode: String
}

struct AuthResponse: Decodable {
    let message: String
    let utilisateur: UtilisateurDTO
    let token: String
    let refreshToken: String?
}

struct RefreshTokenRequest: Encodable {
    let refreshToken: String
}

struct RefreshTokenResponse: Decodable {
    let token: String
    let refreshToken: String
}

struct ConnexionRequest: Encodable {
    let email: String
    let motDePasse: String
}

struct MessageResponse: Decodable {
    let message: String
}

struct SignalementDTO: Codable, Identifiable, Equatable {
    let id: String
    let utilisateurId: String?
    let arretId: ArretRef?
    let ligne: String
    let typeProbleme: String
    let description: String
    let photo: String?
    let latitude: Double?
    let longitude: Double?
    let confiance: String?
    let source: String?
    let votesPositifs: Int?
    let votesNegatifs: Int?
    let dateSignalement: Date?
    let status: String?
    let community: SignalementCommunityDTO?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case utilisateurId, arretId, ligne, typeProbleme, description
        case photo, latitude, longitude, confiance, source
        case votesPositifs, votesNegatifs, dateSignalement, status, community
    }
}

struct SignalementCommunityDTO: Codable, Equatable {
    let status: String?
    let confidence: Double?
    let freshnessMinutes: Int?
    let confirmations: Int?
    let stillBlocked: Int?
    let resolved: Int?
}

extension SignalementDTO {
    var displayTypeProbleme: String {
        let raw = typeProbleme.trimmingCharacters(in: .whitespacesAndNewlines)
        guard sourceLabel == "Source STIB", raw.localizedCaseInsensitiveCompare("Autre") == .orderedSame else {
            return raw
        }

        let normalized = description
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
            .lowercased()

        if normalized.contains("interrompu") || normalized.contains("interruption") || normalized.contains("supprime") {
            return "Interruption"
        }
        if normalized.contains("non desservi") || normalized.contains("ne dessert pas") {
            return "Arrêt non desservi"
        }
        if normalized.contains("travaux") {
            return "Travaux"
        }
        if normalized.contains("devi") || normalized.contains("deviation") {
            return "Déviation"
        }
        if normalized.contains("retard") || normalized.contains("attente") {
            return "Retard"
        }
        return "Information STIB"
    }

    var effectiveFreshnessMinutes: Int? {
        if let freshness = community?.freshnessMinutes {
            return freshness
        }

        guard let dateSignalement else { return nil }
        return max(Int(Date().timeIntervalSince(dateSignalement) / 60), 0)
    }

    var freshnessLabel: String {
        guard let minutes = effectiveFreshnessMinutes else { return "Signalé à l'instant" }
        if minutes < 1 { return "Signalé à l'instant" }
        if minutes < 60 { return "Signalé il y a \(minutes) min" }
        return "Signalé il y a \(minutes / 60) h"
    }

    var confirmationsSummaryLabel: String? {
        guard let freshness = effectiveFreshnessMinutes else { return nil }
        let confirmations = community?.confirmations ?? 0
        guard confirmations > 0 else { return nil }
        return "Confirmé \(confirmations)× en \(freshnessWindowLabel(minutes: freshness))"
    }

    var confidenceLabel: String? {
        guard let confiance else { return nil }
        switch confiance.lowercased() {
        case "haute", "high":
            return "Confiance haute"
        case "moyenne", "medium":
            return "Confiance moyenne"
        case "basse", "low":
            return "Confiance basse"
        default:
            return nil
        }
    }

    var confidenceExplanation: String? {
        guard let confiance else { return nil }
        switch confiance.lowercased() {
        case "haute", "high":
            return "Basée sur une position GPS très proche de l'arrêt signalé."
        case "moyenne", "medium":
            return "Basée sur une position GPS cohérente, mais moins précise autour de l'arrêt."
        case "basse", "low":
            return "Basée sur une position GPS absente ou trop éloignée de l'arrêt signalé."
        default:
            return "Basée sur la proximité GPS observée au moment du signalement."
        }
    }

    var isStale: Bool {
        (effectiveFreshnessMinutes ?? 0) >= 120
    }

    var stalePromptLabel: String? {
        isStale ? "Plus récent ?" : nil
    }

    var sourceLabel: String {
        switch source?.lowercased() {
        case let raw? where raw.contains("official") || raw.contains("stib"):
            return "Source STIB"
        case let raw? where raw.contains("mixed"):
            return "STIB + communauté"
        default:
            return "Communauté"
        }
    }

    private func freshnessWindowLabel(minutes: Int) -> String {
        if minutes < 1 { return "moins d'1 min" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(minutes / 60) h"
    }
}

extension TransportIncidentDTO {
    var sourceLabel: String {
        let normalized = source?.lowercased() ?? ""
        if normalized.contains("official") || normalized.contains("stib") {
            return community == nil ? "Source STIB" : "STIB + communauté"
        }
        return community == nil ? "Terrain" : "Communauté"
    }

    var confidenceLabel: String? {
        guard let legacyConfidence else { return nil }
        switch legacyConfidence.lowercased() {
        case "haute", "high":
            return "Confiance haute"
        case "moyenne", "medium":
            return "Confiance moyenne"
        case "basse", "low":
            return "Confiance basse"
        default:
            return nil
        }
    }

    var confidenceExplanation: String {
        switch legacyConfidence?.lowercased() {
        case "haute", "high":
            return "Basée sur une position GPS très proche de l'arrêt signalé."
        case "moyenne", "medium":
            return "Basée sur une position GPS cohérente, mais moins précise autour de l'arrêt."
        case "basse", "low":
            return "Basée sur une position GPS absente ou trop éloignée de l'arrêt signalé."
        default:
            return "Basée sur les indices réseau et la proximité GPS disponibles."
        }
    }
}

enum ArretRef: Codable, Equatable {
    case id(String)
    case populated(ArretDTO)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let s = try? container.decode(String.self) {
            self = .id(s); return
        }
        let a = try container.decode(ArretDTO.self)
        self = .populated(a)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .id(let s): try container.encode(s)
        case .populated(let a): try container.encode(a)
        }
    }

    var id: String {
        switch self {
        case .id(let s): return s
        case .populated(let a): return a.id
        }
    }
}

struct ArretDTO: Codable, Equatable {
    let id: String
    let stopId: String?
    let nom: String
    let latitude: Double?
    let longitude: Double?
    let lignesDesservies: [String]?
    let nextPassageMinutes: Int?
    let nextPassages: [Int]?
    let nextPassageSource: String?
    let delayMinutes: Int?
    let scheduledDepartureAt: Date?
    let realtimeDepartureAt: Date?

    enum CodingKeys: String, CodingKey {
        case id = "_id"
        case stopId = "stop_id"
        case nom, latitude, longitude, lignesDesservies
        case nextPassageMinutes, nextPassages, nextPassageSource
        case delayMinutes, scheduledDepartureAt, realtimeDepartureAt
    }
}

struct TransportLabelDTO: Codable, Equatable {
    let fr: String?
    let nl: String?
    let en: String?
}

struct TransportIncidentStopDTO: Codable, Equatable {
    let id: String?
    let stopId: String?
    let name: String?
    let latitude: Double?
    let longitude: Double?
}

struct TransportIncidentDTO: Codable, Identifiable, Equatable {
    let id: String
    let type: String?
    let description: String?
    let severity: String?
    let confidence: Double?
    let legacyConfidence: String?
    let source: String?
    let line: String?
    let stop: TransportIncidentStopDTO?
    let date: Date?
    let community: SignalementCommunityDTO?
}

struct TransportDepartureDTO: Codable, Identifiable, Equatable {
    var id: String { "\(line)-\(destination ?? "unknown")-\(minutes)" }
    let line: String
    let destination: String?
    let minutes: Int
    let source: String?
    let delayMinutes: Int?
    let scheduledDepartureAt: Date?
    let realtimeDepartureAt: Date?
}

struct TransportAlternativeDTO: Codable, Identifiable, Equatable {
    var id: String { type }
    let type: String
    let label: String
    let score: Double
    let totalDurationMinutes: Int
    let walkingMinutes: Int
    let transfers: Int
    let lines: [String]
    let severity: String
    let confidence: Double
    let explanation: String
    let explanationDetails: TransportAlternativeExplanationDTO?
    let reasons: [String]?
    let steps: [TransportRouteStepDTO]?
    let scheduledDepartureAt: Date?
    let scheduledArrivalAt: Date?
    let realtimeDepartureAt: Date?
    let realtimeArrivalAt: Date?
    let activeVehicle: TransportVehicleDTO?
    let officialAlerts: [TransportOfficialAlertDTO]?
}

struct TransportAlternativeExplanationDTO: Codable, Equatable {
    let riskLevel: String
    let summary: String
    let highlights: [String]
    let categories: [TransportAlternativeExplanationCategoryDTO]
}

struct TransportAlternativeExplanationCategoryDTO: Codable, Equatable, Identifiable {
    var id: String { key }
    let key: String
    let title: String
    let impact: String
    let detail: String
}

struct TransportRouteStepDTO: Codable, Identifiable, Equatable {
    var id: String { "\(order)-\(mode)-\(line ?? "none")-\(instruction)" }
    let order: Int
    let mode: String
    let instruction: String
    let durationMinutes: Int
    let line: String?
    let destination: String?
    let stopName: String?
    let arrivalStopName: String?
    let stopsCount: Int?
    let startLatitude: Double?
    let startLongitude: Double?
    let targetLatitude: Double?
    let targetLongitude: Double?
    let scheduledDepartureAt: Date?
    let scheduledArrivalAt: Date?
    let realtimeDepartureMinutes: Int?
    let realtimeDepartureAt: Date?
    let realtimeArrivalAt: Date?
    let vehicle: TransportVehicleDTO?
    let alerts: [TransportOfficialAlertDTO]?
    let path: [TransportStepCoordinateDTO]?
}

struct TransportOfficialAlertDTO: Codable, Identifiable, Equatable {
    var id: String { alertId ?? "\(title ?? "alert")-\(priority ?? 0)" }
    private enum CodingKeys: String, CodingKey {
        case alertId = "id"
        case title
        case description
        case priority
        case lines
        case stops
    }
    let alertId: String?
    let title: String?
    let description: String?
    let priority: Int?
    let lines: [String]?
    let stops: [String]?

    init(id: String?, title: String?, description: String?, priority: Int?, lines: [String]?, stops: [String]?) {
        self.alertId = id
        self.title = title
        self.description = description
        self.priority = priority
        self.lines = lines
        self.stops = stops
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        alertId = try container.decodeIfPresent(String.self, forKey: .alertId)
        title = try container.decodeIfPresent(String.self, forKey: .title)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        priority = try container.decodeIfPresent(Int.self, forKey: .priority)
        lines = try container.decodeIfPresent([String].self, forKey: .lines)
        stops = try container.decodeIfPresent([String].self, forKey: .stops)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(alertId, forKey: .alertId)
        try container.encodeIfPresent(title, forKey: .title)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(priority, forKey: .priority)
        try container.encodeIfPresent(lines, forKey: .lines)
        try container.encodeIfPresent(stops, forKey: .stops)
    }
}

struct TransportStepCoordinateDTO: Codable, Equatable, Hashable {
    let lat: Double
    let lng: Double
}

struct TransportStopSummaryDTO: Codable, Identifiable, Equatable {
    let id: String
    let stopId: String?
    let name: String
    let latitude: Double?
    let longitude: Double?
    let lines: [String]
}

struct TransportLineStopDTO: Codable, Identifiable, Equatable {
    let id: String
    let stopId: String?
    let name: String
}

struct TransportLineSummaryDTO: Codable, Equatable {
    let id: String
    let lineId: String
    let name: String
    let type: String
    let color: String
    let direction: String
    let stops: [TransportLineStopDTO]
}

struct TransportVehicleDTO: Codable, Identifiable, Equatable {
    var id: String { vehicleId ?? "\(line ?? "unknown")-\(latitude ?? 0)-\(longitude ?? 0)" }
    let vehicleId: String?
    let line: String?
    let direction: String?
    let latitude: Double?
    let longitude: Double?
    let updatedAt: Date?
}

struct TransportOverviewDTO: Codable, Equatable {
    struct Context: Codable, Equatable {
        let lat: String?
        let lng: String?
    }

    let context: Context?
    let severity: String
    let confidence: Double
    let realtimeStatus: String
    let officialDataStatus: String?
    let officialDataMessage: String?
    let perturbationSummary: TransportPerturbationSummaryDTO?
    let label: TransportLabelDTO?
    let color: String?
    let activeIncidents: [TransportIncidentDTO]
    let stops: [TransportStopSummaryDTO]
    let nextDepartures: [TransportDepartureDTO]
    let recommendedAlternatives: [TransportAlternativeDTO]
}

struct TransportEventsResponseDTO: Codable, Equatable {
    struct Meta: Codable, Equatable {
        let line: String?
        let query: String?
        let activeOnly: Bool
        let total: Int
    }

    let events: [TransportEventImpactDTO]
    let meta: Meta?
}

struct TransportEventImpactDTO: Codable, Equatable, Identifiable {
    let id: String
    let source: String?
    let title: String
    let category: String?
    let venue: String?
    let zoneLabel: String?
    let address: String?
    let latitude: Double?
    let longitude: Double?
    let startsAt: Date?
    let endsAt: Date?
    let phase: String?
    let phaseLabel: String?
    let expectedAttendance: Int?
    let impactLevel: String?
    let notesFr: String?
    let impactedLines: [String]
    let impactedStops: [String]
    let impactedStopDetails: [TransportEventImpactedStopDTO]?
    let confidence: Double?
    let soldOut: Bool?
    let url: String?
}

struct TransportEventImpactedStopDTO: Codable, Equatable, Identifiable {
    let id: String?
    let stopId: String?
    let name: String
}

struct TransportPerturbationSummaryDTO: Codable, Equatable {
    let title: String
    let shortText: String
    let longText: String
    let bullets: [String]
    let affectedLines: [String]
    let affectedStops: [String]
    let incidentTypes: [String]?
    let sourceLabel: String?
    let sourceBreakdown: TransportPerturbationSourceBreakdownDTO?
    let crowdingRisk: TransportCrowdingRiskDTO?
    let source: String?
}

struct TransportPerturbationSourceBreakdownDTO: Codable, Equatable {
    let official: Int?
    let community: Int?
    let mixed: Int?
}

struct TransportCrowdingRiskDTO: Codable, Equatable {
    let level: String
    let title: String
    let shortText: String
    let longText: String
    let eventNames: [String]
    let zoneLabel: String?
    let impactedLines: [String]
    let impactedStops: [String]
    let confidence: Double?
    let source: String?
}

struct TransportStopDTO: Codable, Equatable {
    let stop: TransportStopSummaryDTO
    let severity: String
    let confidence: Double
    let realtimeStatus: String
    let officialDataStatus: String?
    let officialDataMessage: String?
    let perturbationSummary: TransportPerturbationSummaryDTO?
    let label: TransportLabelDTO?
    let color: String?
    let activeIncidents: [TransportIncidentDTO]
    let nextDepartures: [TransportDepartureDTO]
    let recommendedAlternatives: [TransportAlternativeDTO]
}

struct TransportLineDTO: Codable, Equatable {
    let line: TransportLineSummaryDTO
    let severity: String
    let confidence: Double
    let realtimeStatus: String
    let officialDataStatus: String?
    let officialDataMessage: String?
    let perturbationSummary: TransportPerturbationSummaryDTO?
    let label: TransportLabelDTO?
    let color: String?
    let activeIncidents: [TransportIncidentDTO]
    let nextDepartures: [TransportDepartureDTO]
    let vehicles: [TransportVehicleDTO]?
    let recommendedAlternatives: [TransportAlternativeDTO]
}

struct TransportRecommendationFallbackDTO: Codable, Equatable {
    let reason: String
    let message: String
}

struct TransportRecommendationRequest: Encodable {
    let depart: String
    let destination: String
    let lignesBloquees: [String]
}

struct TransportRecommendationDTO: Codable, Equatable {
    struct Request: Codable, Equatable {
        let depart: String
        let destination: String
        let lignesBloquees: [String]
    }

    let request: Request
    let severity: String
    let confidence: Double
    let realtimeStatus: String
    let officialDataStatus: String?
    let officialDataMessage: String?
    let perturbationSummary: TransportPerturbationSummaryDTO?
    let label: TransportLabelDTO?
    let color: String?
    let activeIncidents: [TransportIncidentDTO]
    let nextDepartures: [TransportDepartureDTO]
    let recommendedAlternatives: [TransportAlternativeDTO]
    let fallback: TransportRecommendationFallbackDTO?
}
