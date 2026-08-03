import Foundation

/// Horaires théoriques conservés SUR L'APPAREIL, pour qu'un arrêt reste
/// lisible quand le serveur ne répond pas.
///
/// Le repli « horaires théoriques » existait déjà, mais il était calculé côté
/// serveur : quand celui-ci renvoyait 502 ou dépassait le délai, l'app ne
/// recevait rien du tout — pas même le repli censé rattraper la panne. Le filet
/// de sécurité tombait en même temps que ce qu'il devait rattraper.
///
/// Une journée entière d'horaires pour un arrêt pèse ~2 Ko (mesuré : 265
/// passages sur les trois types de jour). On peut donc garder sans scrupule
/// ceux des arrêts que l'utilisateur a réellement ouverts.
enum StibScheduleCache {
    /// Au-delà, on considère le snapshot GTFS trop vieux pour être affiché
    /// sans mentir : les horaires STIB changent aux changements de service.
    private static let maxAgeDays = 45

    private struct Entry: Codable {
        let savedAt: Date
        let schedule: StibStopSchedule
    }

    // MARK: - Emplacement

    private static var directory: URL? {
        guard let caches = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = caches.appendingPathComponent("stib-schedules", isDirectory: true)
        if !FileManager.default.fileExists(atPath: folder.path) {
            try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        }
        return folder
    }

    /// Les identifiants d'arrêt viennent du serveur : on ne les met jamais tels
    /// quels dans un chemin de fichier.
    private static func fileURL(for stopId: String) -> URL? {
        let safe = stopId.unicodeScalars
            .map { CharacterSet.alphanumerics.contains($0) ? Character($0) : "_" }
            .reduce(into: "") { $0.append($1) }
        guard !safe.isEmpty else { return nil }
        return directory?.appendingPathComponent("\(safe).json")
    }

    // MARK: - Écriture / lecture

    static func save(_ schedule: StibStopSchedule) {
        guard !schedule.lines.isEmpty, let url = fileURL(for: schedule.stopId) else { return }
        let entry = Entry(savedAt: Date(), schedule: schedule)
        guard let data = try? JSONEncoder().encode(entry) else { return }
        try? data.write(to: url, options: .atomic)
    }

    static func load(stopId: String) -> StibStopSchedule? {
        guard let url = fileURL(for: stopId),
              let data = try? Data(contentsOf: url),
              let entry = try? JSONDecoder().decode(Entry.self, from: data)
        else { return nil }

        let age = Calendar.current.dateComponents([.day], from: entry.savedAt, to: Date()).day ?? 0
        guard age <= maxAgeDays else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        return entry.schedule
    }

    // MARK: - Prochains passages depuis le cache

    /// Reconstruit des passages exploitables à partir des horaires conservés.
    ///
    /// - Parameters:
    ///   - stopIds: le quai touché ET ses voisins de même nom. De Lijn comme la
    ///     STIB découpent un arrêt en plusieurs quais ; n'en lire qu'un donnerait
    ///     une seule direction.
    ///   - now: injecté pour être testable.
    static func departures(
        forStopIds stopIds: [String],
        now: Date = Date(),
        limit: Int = 12
    ) -> [TransportDepartureDTO] {
        let dayType = StibScheduleService.currentDayType(at: now)
        let nowMinutes = minutesSinceMidnight(now)

        var rows: [(minutes: Int, departure: TransportDepartureDTO)] = []
        for stopId in stopIds {
            guard let schedule = load(stopId: stopId) else { continue }
            for line in schedule.lines {
                for clock in line.departures(for: dayType) {
                    guard let scheduled = minutesFromClock(clock) else { continue }
                    guard let wait = waitMinutes(from: nowMinutes, to: scheduled) else { continue }
                    rows.append((
                        wait,
                        TransportDepartureDTO(
                            line: line.line,
                            destination: line.destination,
                            minutes: wait,
                            source: "scheduled",
                            delayMinutes: nil,
                            scheduledDepartureAt: now.addingTimeInterval(TimeInterval(wait) * 60),
                            realtimeDepartureAt: nil
                        )
                    ))
                }
            }
        }

        // Un passage par (ligne, direction) : la liste doit rester lisible, pas
        // dérouler tout l'horaire de la journée.
        var seen = Set<String>()
        var result: [TransportDepartureDTO] = []
        for row in rows.sorted(by: { $0.minutes < $1.minutes }) {
            let key = "\(row.departure.line)|\(row.departure.destination ?? "")"
            guard seen.insert(key).inserted else { continue }
            result.append(row.departure)
            if result.count >= limit { break }
        }
        return result
    }

    // MARK: - Calcul horaire

    private static func minutesSinceMidnight(_ date: Date) -> Int {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "Europe/Brussels") ?? .current
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    /// « 06:15 » → 375. Le GTFS dépasse 24 h pour les services de nuit
    /// (« 25:10 » = 01:10 le lendemain), d'où l'heure non bornée à 23.
    private static func minutesFromClock(_ clock: String) -> Int? {
        let parts = clock.split(separator: ":")
        guard parts.count == 2,
              let hours = Int(parts[0]),
              let minutes = Int(parts[1]),
              (0..<60).contains(minutes)
        else { return nil }
        return hours * 60 + minutes
    }

    /// Attente en minutes, en tenant compte du passage à minuit. On rejette les
    /// passages à plus de 12 h : au-delà, ce n'est plus « le prochain », et une
    /// attente absurde décrédibilise tout l'écran.
    private static func waitMinutes(from nowMinutes: Int, to scheduledMinutes: Int) -> Int? {
        let direct = scheduledMinutes - nowMinutes
        let candidates = [direct, direct + 1440, direct - 1440]
        guard let wait = candidates.filter({ $0 >= 0 }).min(), wait <= 12 * 60 else { return nil }
        return wait
    }
}
