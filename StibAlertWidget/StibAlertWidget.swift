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
        case .ok:       return "Normal"
        case .warning:  return "Perturbé"
        case .critical: return "Arrêté"
        case .unknown:  return "—"
        }
    }
}

// MARK: - Design tokens

private enum WD {
    // Backgrounds
    static let bg          = Color(red: 0.07, green: 0.08, blue: 0.11)
    static let card        = Color(red: 0.12, green: 0.14, blue: 0.18)
    static let cardStroke  = Color.white.opacity(0.08)

    // Text
    static let ink         = Color.white
    static let inkSoft     = Color.white.opacity(0.60)
    static let inkMute     = Color.white.opacity(0.30)

    // Brand
    static let orange      = Color(red: 0.94, green: 0.38, blue: 0.09)

    // Line colors (official STIB palette)
    static func lineColor(_ line: String) -> Color {
        switch line.uppercased() {
        case "1", "5": return Color(red: 0.66, green: 0.18, blue: 0.62)
        case "2", "6": return Color(red: 0.00, green: 0.44, blue: 0.72)
        case "3", "4": return Color(red: 0.76, green: 0.11, blue: 0.55)
        case "7":      return Color(red: 0.96, green: 0.90, blue: 0.13)
        case "8":      return Color(red: 0.56, green: 0.28, blue: 0.62)
        case "9":      return Color(red: 0.72, green: 0.52, blue: 0.18)
        case "10":     return Color(red: 0.61, green: 0.32, blue: 0.67)
        case "25", "55": return Color(red: 0.00, green: 0.45, blue: 0.72)
        case "36", "53": return Color(red: 0.31, green: 0.61, blue: 0.25)
        case "37":     return Color(red: 0.95, green: 0.88, blue: 0.16)
        case "47", "56": return Color(red: 1.00, green: 0.47, blue: 0.00)
        case "71":     return Color(red: 0.33, green: 0.55, blue: 0.25)
        case "83":     return Color(red: 0.70, green: 0.84, blue: 0.00)
        default:       return orange
        }
    }

    static func textColor(for line: String) -> Color {
        ["7", "37", "83"].contains(line.uppercased()) ? Color(red: 0.07, green: 0.08, blue: 0.11) : .white
    }

    static func modeIcon(for line: String) -> String {
        let n = line.uppercased()
        if n.hasPrefix("T") { return "tram.fill" }
        guard let num = Int(n.filter(\.isNumber)) else { return "tram.fill" }
        if (1...6).contains(num) { return "m.circle.fill" }
        return num >= 90 || (12...89).contains(num) ? "bus.fill" : "tram.fill"
    }

    /// Converts raw minutes into a human-readable string.
    /// ≥ 60 minutes → actual arrival time "HH:mm" instead of absurd counts.
    static func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "À quai" }
        guard minutes < 60 else {
            let arrival = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
            let f = DateFormatter()
            f.dateFormat = "HH:mm"
            return f.string(from: arrival)
        }
        return "\(minutes) min"
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
                case "none", "low":      return .ok
                case "medium":           return .warning
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

// MARK: - Entry View

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

// MARK: - Small widget

private struct SmallWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if let line = entry.lines.first {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Image(systemName: WD.modeIcon(for: line.lineNumber))
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(WD.inkMute)
                    Text("StibAlert")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(WD.inkMute)
                    Spacer()
                    StatusPip(status: line.status)
                }

                Spacer()

                // Line badge + time
                HStack(alignment: .bottom, spacing: 10) {
                    WLineBadge(line: line.lineNumber, size: 44)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WD.formatMinutes(line.nextPassageMinutes ?? -1))
                            .font(.system(size: 26, weight: .black, design: .rounded))
                            .foregroundStyle(timeColor(for: line.nextPassageMinutes))
                            .minimumScaleFactor(0.70)
                            .lineLimit(1)
                        if let dest = line.destination, !dest.isEmpty {
                            Text(dest.uppercased())
                                .font(.system(size: 8, weight: .bold, design: .monospaced))
                                .tracking(0.6)
                                .foregroundStyle(WD.inkSoft)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer().frame(height: 8)

                // Status label
                HStack(spacing: 5) {
                    Circle()
                        .fill(line.status.color)
                        .frame(width: 5, height: 5)
                    Text(line.status.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                        .foregroundStyle(line.status.color)
                }
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WD.bg, for: .widget)
        } else {
            EmptyWidgetView()
        }
    }

    private func timeColor(for minutes: Int?) -> Color {
        guard let m = minutes else { return WD.inkMute }
        if m == 0 { return WD.orange }
        if m <= 3 { return Color(red: 0.96, green: 0.65, blue: 0.14) }
        return WD.ink
    }
}

// MARK: - Medium widget

private struct MediumWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if entry.lines.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                // Header
                HStack {
                    Text("StibAlert")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.4)
                        .foregroundStyle(WD.orange)
                    Spacer()
                    Text(entry.date, style: .time)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(WD.inkMute)
                }

                HStack(spacing: 8) {
                    ForEach(entry.lines.prefix(2)) { line in
                        MediumLineCard(line: line)
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(WD.bg, for: .widget)
        }
    }
}

private struct MediumLineCard: View {
    let line: StibLineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Top row: badge + time
            HStack(alignment: .top) {
                WLineBadge(line: line.lineNumber, size: 36)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if let minutes = line.nextPassageMinutes {
                        Text(WD.formatMinutes(minutes))
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(timeColor(for: minutes))
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                        Text(minutes >= 60 ? "arrivée" : "prochain")
                            .font(.system(size: 7, weight: .bold, design: .monospaced))
                            .tracking(0.5)
                            .foregroundStyle(WD.inkMute)
                    } else {
                        Text("—")
                            .font(.system(size: 22, weight: .black, design: .rounded))
                            .foregroundStyle(WD.inkMute)
                    }
                }
            }

            Spacer(minLength: 6)

            // Destination
            if let dest = line.destination, !dest.isEmpty {
                Text(dest)
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(WD.inkSoft)
                    .lineLimit(1)
            } else {
                Text("Aucune dest.")
                    .font(.system(size: 9, weight: .semibold, design: .rounded))
                    .foregroundStyle(WD.inkMute)
                    .lineLimit(1)
            }

            Spacer(minLength: 6)

            // Status
            HStack(spacing: 4) {
                Circle()
                    .fill(line.status.color)
                    .frame(width: 5, height: 5)
                Text(line.status.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(line.status.color)
                Spacer()
                Image(systemName: WD.modeIcon(for: line.lineNumber))
                    .font(.system(size: 8, weight: .bold))
                    .foregroundStyle(WD.inkMute)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 90, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(WD.card)
                .overlay(
                    RoundedRectangle(cornerRadius: 14, style: .continuous)
                        .stroke(WD.cardStroke, lineWidth: 1)
                )
        )
    }

    private func timeColor(for minutes: Int) -> Color {
        if minutes == 0 { return WD.orange }
        if minutes <= 3 { return Color(red: 0.96, green: 0.65, blue: 0.14) }
        return WD.ink
    }
}

// MARK: - Shared components

private struct WLineBadge: View {
    let line: String
    let size: CGFloat

    var body: some View {
        Text(line)
            .font(.system(size: size * 0.38, weight: .black, design: .rounded))
            .foregroundStyle(WD.textColor(for: line))
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(WD.lineColor(line))
            )
    }
}

private struct StatusPip: View {
    let status: LineWidgetStatus

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(status.color)
                .frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(status.color)
        }
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(WD.orange)
            Text("Ajoute une ligne\nen favoris")
                .font(.system(size: 11, weight: .bold, design: .rounded))
                .foregroundStyle(WD.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WD.bg, for: .widget)
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
