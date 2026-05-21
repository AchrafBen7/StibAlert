import Foundation
import CoreLocation

/// Lightweight on-device cache for the data that should survive when
/// the backend is unreachable (no signal in the métro, airplane mode, …).
///
/// Backed by UserDefaults + JSON encoding for simplicity. Designed for
/// ~50 KB max: a few hundred clusters and ~50 queued reports.
///
/// Three concerns are persisted:
///  1. **Last known clusters** — so the map and DecisionView can render
///     a degraded version instead of going blank.
///  2. **Queued signalements** — when the user signals offline, we keep
///     the intent in a queue and POST it as soon as connectivity returns.
///  3. **Last known user routine summary** — so the DecisionView can hint
///     "ta routine était ligne 56 → Schuman" without a network round-trip.
enum OfflineCache {
    private enum Keys {
        static let clusters = "offlineCache.clusters.v1"
        static let clustersFetchedAt = "offlineCache.clusters.fetchedAt.v1"
        static let queuedReports = "offlineCache.queuedReports.v1"
        static let routineSummary = "offlineCache.routineSummary.v1"
        static let favoriteLines = "offlineCache.favoriteLines.v1"
    }

    private static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .iso8601
        return e
    }()

    private static let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .iso8601
        return d
    }()

    // MARK: - Clusters

    static func saveClusters(_ clusters: [ClusterDTO]) {
        guard let data = try? encoder.encode(clusters) else { return }
        UserDefaults.standard.set(data, forKey: Keys.clusters)
        UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: Keys.clustersFetchedAt)
    }

    static func loadClusters() -> (clusters: [ClusterDTO], fetchedAt: Date?) {
        guard let data = UserDefaults.standard.data(forKey: Keys.clusters),
              let clusters = try? decoder.decode([ClusterDTO].self, from: data) else {
            return ([], nil)
        }
        let fetchedAt: Date? = {
            let interval = UserDefaults.standard.double(forKey: Keys.clustersFetchedAt)
            return interval > 0 ? Date(timeIntervalSince1970: interval) : nil
        }()
        return (clusters, fetchedAt)
    }

    static var clustersAreStale: Bool {
        let interval = UserDefaults.standard.double(forKey: Keys.clustersFetchedAt)
        guard interval > 0 else { return true }
        let age = Date().timeIntervalSince1970 - interval
        return age > 30 * 60
    }

    // MARK: - Favorite lines + routine summary

    static func saveFavoriteLines(_ lines: [String]) {
        UserDefaults.standard.set(lines, forKey: Keys.favoriteLines)
    }

    static func loadFavoriteLines() -> [String] {
        UserDefaults.standard.stringArray(forKey: Keys.favoriteLines) ?? []
    }

    struct RoutineSummary: Codable {
        let enabled: Bool
        let homeLabel: String?
        let workLabel: String?
        let departureTime: String?
    }

    static func saveRoutineSummary(_ summary: RoutineSummary?) {
        guard let summary, let data = try? encoder.encode(summary) else {
            UserDefaults.standard.removeObject(forKey: Keys.routineSummary)
            return
        }
        UserDefaults.standard.set(data, forKey: Keys.routineSummary)
    }

    static func loadRoutineSummary() -> RoutineSummary? {
        guard let data = UserDefaults.standard.data(forKey: Keys.routineSummary),
              let summary = try? decoder.decode(RoutineSummary.self, from: data) else {
            return nil
        }
        return summary
    }

    // MARK: - Queued reports (offline signalement queue)

    struct QueuedReport: Codable, Identifiable {
        let id: UUID
        let createdAt: Date
        let nomArret: String
        let ligne: String
        let typeProbleme: String
        let description: String
        let latitude: Double?
        let longitude: Double?
        let transportOperator: String?

        init(
            id: UUID = UUID(),
            createdAt: Date = Date(),
            nomArret: String,
            ligne: String,
            typeProbleme: String,
            description: String,
            latitude: Double?,
            longitude: Double?,
            transportOperator: String? = nil
        ) {
            self.id = id
            self.createdAt = createdAt
            self.nomArret = nomArret
            self.ligne = ligne
            self.typeProbleme = typeProbleme
            self.description = description
            self.latitude = latitude
            self.longitude = longitude
            self.transportOperator = transportOperator
        }
    }

    static func enqueueReport(_ report: QueuedReport) {
        var existing = loadQueuedReports()
        // Cap the queue to avoid pathological growth (50 items max).
        if existing.count >= 50 {
            existing.removeFirst(existing.count - 49)
        }
        existing.append(report)
        if let data = try? encoder.encode(existing) {
            UserDefaults.standard.set(data, forKey: Keys.queuedReports)
        }
    }

    static func loadQueuedReports() -> [QueuedReport] {
        guard let data = UserDefaults.standard.data(forKey: Keys.queuedReports),
              let reports = try? decoder.decode([QueuedReport].self, from: data) else {
            return []
        }
        return reports
    }

    static func removeQueuedReport(id: UUID) {
        var existing = loadQueuedReports()
        existing.removeAll { $0.id == id }
        if let data = try? encoder.encode(existing) {
            UserDefaults.standard.set(data, forKey: Keys.queuedReports)
        }
    }

    static func clearQueue() {
        UserDefaults.standard.removeObject(forKey: Keys.queuedReports)
    }
}
