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

    var actionLabel: String {
        switch self {
        case .ok:       return "réseau normal"
        case .warning:  return "prévoir marge"
        case .critical: return "éviter ligne"
        case .unknown:  return "horaire à vérifier"
        }
    }
}

private enum WidgetDesign {
    static let paper = Color(red: 0.97, green: 0.94, blue: 0.90)
    static let paperElevated = Color(red: 1.00, green: 0.98, blue: 0.94)
    static let ink = Color(red: 0.06, green: 0.06, blue: 0.05)
    static let inkSoft = Color(red: 0.43, green: 0.40, blue: 0.36)
    static let inkMute = Color(red: 0.62, green: 0.58, blue: 0.52)
    static let orange = Color(red: 0.94, green: 0.25, blue: 0.09)
    static let lineBorder = Color.black.opacity(0.14)
    static let mono = Font.system(.caption2, design: .monospaced).weight(.bold)

    static func lineColor(_ line: String) -> Color {
        switch line.uppercased() {
        case "1", "5": return Color(red: 0.66, green: 0.18, blue: 0.62)
        case "2", "6": return Color(red: 0.00, green: 0.44, blue: 0.72)
        case "3", "4": return Color(red: 0.76, green: 0.11, blue: 0.55)
        case "7": return Color(red: 0.96, green: 0.90, blue: 0.13)
        case "8": return Color(red: 0.56, green: 0.28, blue: 0.62)
        case "9": return Color(red: 0.72, green: 0.52, blue: 0.18)
        case "10": return Color(red: 0.61, green: 0.32, blue: 0.67)
        case "25", "55": return Color(red: 0.00, green: 0.45, blue: 0.72)
        case "36", "53": return Color(red: 0.31, green: 0.61, blue: 0.25)
        case "37": return Color(red: 0.95, green: 0.88, blue: 0.16)
        case "47", "56": return Color(red: 1.00, green: 0.47, blue: 0.00)
        case "71": return Color(red: 0.33, green: 0.55, blue: 0.25)
        case "83": return Color(red: 0.70, green: 0.84, blue: 0.00)
        default: return orange
        }
    }

    static func readableText(for line: String) -> Color {
        // Yellow/bright lime STIB lines read better with dark text.
        if ["7", "37", "83"].contains(line.uppercased()) {
            return ink
        }
        return .white
    }

    static func modeIcon(for line: String) -> String {
        let normalized = line.uppercased()
        if normalized.hasPrefix("T") { return "tram.fill" }
        guard let number = Int(normalized.filter(\.isNumber)) else { return "tram.fill" }
        if (1...6).contains(number) { return "m.circle.fill" }
        if number >= 90 || (12...89).contains(number) { return "bus.fill" }
        return "tram.fill"
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
            ZStack(alignment: .bottomLeading) {
                WidgetBackgroundPattern()

                VStack(alignment: .leading, spacing: 9) {
                    HStack {
                        Text("STIBALERT")
                            .font(WidgetDesign.mono)
                            .tracking(1.4)
                            .foregroundStyle(WidgetDesign.inkMute)
                        Spacer()
                        StatusDot(status: line.status)
                    }

                    Spacer(minLength: 0)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack(alignment: .center, spacing: 10) {
                            WidgetLineBadge(line: line.lineNumber, size: 48)

                            VStack(alignment: .leading, spacing: 3) {
                                Text(nextPassageTitle(for: line))
                                    .font(.system(size: 30, weight: .black, design: .rounded))
                                    .foregroundStyle(WidgetDesign.ink)
                                    .minimumScaleFactor(0.75)
                                    .lineLimit(1)
                                Text(destinationTitle(for: line))
                                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                                    .tracking(0.9)
                                    .foregroundStyle(WidgetDesign.inkSoft)
                                    .lineLimit(1)
                            }
                        }

                        HStack(spacing: 6) {
                            Image(systemName: WidgetDesign.modeIcon(for: line.lineNumber))
                                .font(.system(size: 10, weight: .bold))
                            Text(line.status.actionLabel)
                                .font(.system(size: 10, weight: .bold, design: .monospaced))
                                .tracking(0.6)
                        }
                        .foregroundStyle(WidgetDesign.inkSoft)
                    }
                }
                .padding(13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WidgetDesign.paper, for: .widget)
        } else {
            EmptyWidgetView()
        }
    }

    private func nextPassageTitle(for line: StibLineSnapshot) -> String {
        guard let minutes = line.nextPassageMinutes else { return "—" }
        return minutes == 0 ? "À quai" : "\(minutes) min"
    }

    private func destinationTitle(for line: StibLineSnapshot) -> String {
        guard let destination = line.destination, !destination.isEmpty else { return "VERS DESTINATION" }
        return "VERS \(destination.uppercased())"
    }
}

private struct MediumWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if entry.lines.isEmpty {
            EmptyWidgetView()
        } else {
            ZStack {
                WidgetBackgroundPattern()

                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("STIBALERT")
                                .font(WidgetDesign.mono)
                                .tracking(1.5)
                                .foregroundStyle(WidgetDesign.inkMute)
                            Text("Tes lignes · passages")
                                .font(.system(size: 17, weight: .black, design: .rounded))
                                .foregroundStyle(WidgetDesign.ink)
                                .lineLimit(1)
                        }

                        Spacer()

                        Text(entry.date, style: .time)
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .foregroundStyle(WidgetDesign.inkMute)
                    }

                    HStack(spacing: 9) {
                        ForEach(entry.lines.prefix(2)) { line in
                            MediumLineCard(line: line)
                        }
                    }
                }
                .padding(13)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(WidgetDesign.paper, for: .widget)
        }
    }
}

private struct MediumLineCard: View {
    let line: StibLineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 8) {
                WidgetLineBadge(line: line.lineNumber, size: 38)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    Text(nextPassageTitle)
                        .font(.system(size: 28, weight: .black, design: .rounded))
                        .foregroundStyle(WidgetDesign.ink)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                    if line.nextPassageMinutes != nil {
                        Text("prochain")
                            .font(.system(size: 8, weight: .bold, design: .monospaced))
                            .tracking(0.7)
                            .foregroundStyle(WidgetDesign.inkMute)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(destinationTitle)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.8)
                    .foregroundStyle(WidgetDesign.inkSoft)
                    .lineLimit(1)
            }

            Spacer(minLength: 0)

            HStack(spacing: 6) {
                Image(systemName: WidgetDesign.modeIcon(for: line.lineNumber))
                    .font(.system(size: 10, weight: .bold))
                Text(line.status.actionLabel)
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .tracking(0.5)
                Spacer(minLength: 0)
                StatusDot(status: line.status, compact: true)
            }
            .foregroundStyle(WidgetDesign.inkSoft)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 94, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .fill(WidgetDesign.paperElevated)
                .shadow(color: .black.opacity(0.07), radius: 10, x: 0, y: 5)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .stroke(WidgetDesign.lineBorder, lineWidth: 1)
        )
    }

    private var nextPassageTitle: String {
        guard let minutes = line.nextPassageMinutes else { return "—" }
        return minutes == 0 ? "À quai" : "\(minutes)"
    }

    private var destinationTitle: String {
        guard let destination = line.destination, !destination.isEmpty else { return "VERS DESTINATION" }
        return "VERS \(destination.uppercased())"
    }
}

private struct WidgetLineBadge: View {
    let line: String
    let size: CGFloat

    private var color: Color { WidgetDesign.lineColor(line) }

    var body: some View {
        Text(line)
            .font(.system(size: size * 0.38, weight: .black, design: .rounded))
            .foregroundStyle(WidgetDesign.readableText(for: line))
            .minimumScaleFactor(0.6)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .fill(color)
            )
            .overlay(
                RoundedRectangle(cornerRadius: size * 0.18, style: .continuous)
                    .stroke(WidgetDesign.ink.opacity(0.22), lineWidth: 1.5)
            )
            .shadow(color: color.opacity(0.25), radius: 8, x: 0, y: 4)
    }
}

private struct StatusDot: View {
    let status: LineWidgetStatus
    var compact = false

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: status.icon)
                .font(.system(size: compact ? 8 : 10, weight: .black))
            Text(status.label.uppercased())
                .font(.system(size: compact ? 8 : 9, weight: .black, design: .monospaced))
                .tracking(0.7)
        }
        .foregroundStyle(status.color)
        .padding(.horizontal, compact ? 6 : 8)
        .frame(height: compact ? 20 : 24)
        .background(status.color.opacity(0.12))
        .overlay(Capsule().stroke(status.color.opacity(0.28), lineWidth: 1))
        .clipShape(Capsule())
    }
}

private struct WidgetNextPassagePill: View {
    let minutes: Int?

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 5) {
            Image(systemName: "clock.fill")
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(WidgetDesign.orange)

            if let minutes {
                Text(minutes == 0 ? "À quai" : "\(minutes) min")
                    .font(.system(size: 13, weight: .black, design: .rounded))
                    .foregroundStyle(WidgetDesign.ink)
                Text("prochain")
                    .font(.system(size: 9, weight: .bold, design: .monospaced))
                    .foregroundStyle(WidgetDesign.inkMute)
            } else {
                Text("Horaire indispo")
                    .font(.system(size: 11, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetDesign.inkSoft)
            }
        }
        .padding(.horizontal, 9)
        .frame(height: 28)
        .background(.white.opacity(0.72))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(WidgetDesign.lineBorder, lineWidth: 1))
    }
}

private struct WidgetBackgroundPattern: View {
    var body: some View {
        ZStack {
            WidgetDesign.paper
            LinearGradient(
                colors: [
                    WidgetDesign.orange.opacity(0.18),
                    .clear,
                    Color(red: 0.97, green: 0.74, blue: 0.10).opacity(0.16)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            Circle()
                .fill(WidgetDesign.orange.opacity(0.14))
                .frame(width: 118, height: 118)
                .offset(x: 92, y: -58)
            Circle()
                .stroke(WidgetDesign.ink.opacity(0.08), lineWidth: 18)
                .frame(width: 128, height: 128)
                .offset(x: -92, y: 72)
        }
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        ZStack {
            WidgetBackgroundPattern()
            VStack(spacing: 8) {
                Image(systemName: "tram.fill")
                    .font(.system(size: 24, weight: .bold))
                    .foregroundStyle(WidgetDesign.orange)
                Text("Ajoute une ligne\nen favoris")
                    .font(.system(size: 12, weight: .bold, design: .rounded))
                    .foregroundStyle(WidgetDesign.ink)
                    .multilineTextAlignment(.center)
                Text("StibAlert")
                    .font(WidgetDesign.mono)
                    .tracking(1.3)
                    .foregroundStyle(WidgetDesign.inkMute)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WidgetDesign.paper, for: .widget)
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
