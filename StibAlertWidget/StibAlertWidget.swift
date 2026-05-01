import WidgetKit
import SwiftUI

// MARK: - Shared config

private let appGroupID = "group.com.ehb.StibAlert"
private let backendBaseURL = "https://stib-alert-backend.onrender.com"

// MARK: - Timeline model

struct StibLineEntry: TimelineEntry {
    let date: Date
    let lines: [StibLineSnapshot]
}

struct StibLineSnapshot: Identifiable {
    let id: String
    let lineNumber: String
    let status: LineWidgetStatus
    let nextPassageMinutes: Int?
    let destination: String?
}

enum LineWidgetStatus: String {
    case ok, warning, critical, unknown

    var icon: String {
        switch self {
        case .ok:       return "checkmark.circle.fill"
        case .warning:  return "exclamationmark.triangle.fill"
        case .critical: return "xmark.circle.fill"
        case .unknown:  return "minus.circle.fill"
        }
    }

    var color: Color {
        switch self {
        case .ok:       return Color(red: 0.13, green: 0.75, blue: 0.40)
        case .warning:  return Color(red: 0.96, green: 0.65, blue: 0.14)
        case .critical: return Color(red: 0.96, green: 0.27, blue: 0.27)
        case .unknown:  return Color.gray
        }
    }

    var label: String {
        switch self {
        case .ok:       return "OK"
        case .warning:  return "Perturbé"
        case .critical: return "Interrompu"
        case .unknown:  return "—"
        }
    }
}

// MARK: - Provider

struct StibWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StibLineEntry {
        .init(date: .now, lines: [
            .init(id: "92", lineNumber: "92", status: .ok,      nextPassageMinutes: 4, destination: "Simonis"),
            .init(id: "5",  lineNumber: "5",  status: .warning, nextPassageMinutes: 9, destination: "Herrmann-Debroux")
        ])
    }

    func getSnapshot(in context: Context, completion: @escaping (StibLineEntry) -> Void) {
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StibLineEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let next  = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(next)))
        }
    }

    // MARK: Private

    private func fetchEntry() async -> StibLineEntry {
        let favorites = loadFavoriteLines()
        guard !favorites.isEmpty else { return .init(date: .now, lines: []) }

        var snapshots: [StibLineSnapshot] = []
        for line in favorites.prefix(2) {
            if let snap = await fetchLineStatus(line) {
                snapshots.append(snap)
            } else {
                snapshots.append(.init(id: line, lineNumber: line, status: .unknown, nextPassageMinutes: nil, destination: nil))
            }
        }
        return .init(date: .now, lines: snapshots)
    }

    private func loadFavoriteLines() -> [String] {
        (UserDefaults(suiteName: appGroupID) ?? .standard).stringArray(forKey: "favoriteLines") ?? []
    }

    private func fetchLineStatus(_ line: String) async -> StibLineSnapshot? {
        guard let encoded = line.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
              let url = URL(string: "\(backendBaseURL)/api/transport/line/\(encoded)") else { return nil }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded   = try JSONDecoder().decode(WidgetLineResponse.self, from: data)
            let status: LineWidgetStatus = {
                switch decoded.severity?.lowercased() {
                case "none", "low": return .ok
                case "medium":      return .warning
                case "high", "critical": return .critical
                default: return .ok
                }
            }()
            return .init(id: line, lineNumber: line, status: status,
                         nextPassageMinutes: decoded.nextDepartures?.first?.minutes,
                         destination: decoded.nextDepartures?.first?.destination)
        } catch { return nil }
    }
}

private struct WidgetLineResponse: Decodable {
    let severity: String?
    let nextDepartures: [WidgetDeparture]?
}
private struct WidgetDeparture: Decodable {
    let line: String
    let destination: String?
    let minutes: Int
}

// MARK: - Views

struct StibAlertWidgetEntryView: View {
    let entry: StibLineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemMedium: MediumWidgetView(entry: entry)
        default:            SmallWidgetView(entry: entry)
        }
    }
}

private struct SmallWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if let line = entry.lines.first {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    Text(line.lineNumber)
                        .font(.system(size: 22, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                    Text("STIB")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(.white.opacity(0.5))
                }
                Spacer()
                HStack(spacing: 5) {
                    Image(systemName: line.status.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(line.status.color)
                    Text(line.status.label)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.white)
                }
                if let mins = line.nextPassageMinutes {
                    Text(mins == 0 ? "À l'arrêt" : "Prochain : \(mins) min")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.7))
                        .lineLimit(1)
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(Color(red: 0.06, green: 0.09, blue: 0.15), for: .widget)
        } else {
            EmptyWidgetView()
        }
    }
}

private struct MediumWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if entry.lines.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    Text("StibAlert")
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(.white.opacity(0.5))
                    Spacer()
                    Text(entry.date, style: .time)
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.35))
                }

                ForEach(entry.lines.prefix(2)) { line in
                    HStack(spacing: 10) {
                        Text(line.lineNumber)
                            .font(.system(size: 18, weight: .black, design: .rounded))
                            .foregroundStyle(.white)
                            .frame(width: 36)
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 4) {
                                Image(systemName: line.status.icon)
                                    .font(.system(size: 11))
                                    .foregroundStyle(line.status.color)
                                Text(line.status.label)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundStyle(.white)
                            }
                            if let dest = line.destination {
                                Text(dest)
                                    .font(.system(size: 10))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .lineLimit(1)
                            }
                        }
                        Spacer()
                        if let mins = line.nextPassageMinutes {
                            VStack(alignment: .trailing, spacing: 0) {
                                Text("\(mins)")
                                    .font(.system(size: 20, weight: .black, design: .rounded))
                                    .foregroundStyle(.white)
                                Text("min")
                                    .font(.system(size: 9))
                                    .foregroundStyle(.white.opacity(0.5))
                            }
                        }
                    }
                    .padding(.vertical, 6)
                    .padding(.horizontal, 10)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(Color(red: 0.06, green: 0.09, blue: 0.15), for: .widget)
        }
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.4))
            Text("Ajoutez des\nlignes en favoris")
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(Color(red: 0.06, green: 0.09, blue: 0.15), for: .widget)
    }
}

// MARK: - Widget declaration

struct StibAlertWidget: Widget {
    let kind = "StibAlertWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: StibWidgetProvider()) { entry in
            StibAlertWidgetEntryView(entry: entry)
        }
        .configurationDisplayName("StibAlert")
        .description("Vos lignes favorites et leurs prochains passages.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
