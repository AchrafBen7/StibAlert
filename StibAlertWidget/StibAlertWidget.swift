import WidgetKit
import SwiftUI

// MARK: - Shared config

private let appGroupID = "group.com.ehb.StibAlert"
private let backendBaseURL = "https://stib-alert-backend.onrender.com"
private let nearbyLinesKey = "widget_nearby_lines"
private let favoriteLinesKey = "favoriteLines"

// MARK: - Timeline model

struct StibLineEntry: TimelineEntry {
    let date: Date
    let lines: [StibLineSnapshot]
    let totalLineCount: Int   // across all pages, for indicator dots
    let pageIndex: Int
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

    var dsColor: Color {
        switch self {
        case .ok:       return WD.statusOK
        case .warning:  return WD.statusMinor
        case .critical: return WD.statusCritical
        case .unknown:  return WD.inkMute
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

// MARK: - Design tokens (mirrors DS.Color exactly)

private extension Color {
    static func ds(_ h: Double, _ s: Double, _ l: Double, dark: Color? = nil) -> Color {
        let light = hsl(h, s, l)
        guard let dark else { return light }
        return Color(UIColor { $0.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light) })
    }

    private static func hsl(_ h: Double, _ s: Double, _ l: Double) -> Color {
        let hN = h / 360, sN = s / 100, lN = l / 100
        func hue2rgb(_ p: Double, _ q: Double, _ t: Double) -> Double {
            var t = t
            if t < 0 { t += 1 }; if t > 1 { t -= 1 }
            if t < 1/6 { return p + (q-p)*6*t }
            if t < 0.5 { return q }
            if t < 2/3 { return p + (q-p)*(2/3-t)*6 }
            return p
        }
        let r, g, b: Double
        if sN == 0 { r = lN; g = lN; b = lN }
        else {
            let q = lN < 0.5 ? lN*(1+sN) : lN+sN-lN*sN
            let p = 2*lN - q
            r = hue2rgb(p, q, hN + 1/3)
            g = hue2rgb(p, q, hN)
            b = hue2rgb(p, q, hN - 1/3)
        }
        return Color(.sRGB, red: r, green: g, blue: b)
    }
}

private enum WD {
    static let background = Color.ds(38, 24, 93, dark: .ds(0, 0, 7))
    static let paper      = Color.ds(36, 28, 95, dark: .ds(0, 0, 10))
    static let paper2     = Color.ds(36, 18, 88, dark: .ds(0, 0, 14))
    static let ink        = Color.ds(0, 0, 6,   dark: .ds(38, 24, 92))
    static let inkSoft    = Color.ds(0, 0, 22,  dark: .ds(36, 14, 78))
    static let inkMute    = Color.ds(30, 6, 42,  dark: .ds(30, 6, 58))
    static let border     = Color.ds(30, 8, 78,  dark: .ds(0, 0, 24))
    static let primary    = Color.ds(14, 82, 51, dark: .ds(14, 88, 56))

    static let statusOK       = Color.ds(152, 60, 32)
    static let statusMinor    = Color.ds(38,  92, 45)
    static let statusCritical = Color.ds(350, 75, 38)

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
        default:       return primary
        }
    }

    static func lineTextColor(for line: String) -> Color {
        ["7", "37", "83"].contains(line.uppercased()) ? ink : .white
    }

    static func modeIcon(for line: String) -> String {
        let n = line.uppercased()
        if n.hasPrefix("T") { return "tram.fill" }
        guard let num = Int(n.filter(\.isNumber)) else { return "tram.fill" }
        if (1...6).contains(num) { return "m.circle.fill" }
        return num >= 90 || (12...89).contains(num) ? "bus.fill" : "tram.fill"
    }

    /// < 60 min → "X min" ; ≥ 60 min → actual HH:mm arrival time.
    static func formatMinutes(_ minutes: Int) -> String {
        guard minutes > 0 else { return "À quai" }
        guard minutes < 60 else {
            let arrival = Calendar.current.date(byAdding: .minute, value: minutes, to: Date()) ?? Date()
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            return f.string(from: arrival)
        }
        return "\(minutes) min"
    }
}

// MARK: - Provider

struct StibWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> StibLineEntry {
        StibLineEntry(date: .now, lines: [
            .init(id: "92", lineNumber: "92", status: .ok,      nextPassageMinutes: 4,  destination: "Simonis"),
            .init(id: "5",  lineNumber: "5",  status: .warning, nextPassageMinutes: 11, destination: "Herrmann-Debroux")
        ], totalLineCount: 2, pageIndex: 0)
    }

    func getSnapshot(in context: Context, completion: @escaping (StibLineEntry) -> Void) {
        Task { completion(await buildEntries(family: context.family).first ?? placeholder(in: context)) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<StibLineEntry>) -> Void) {
        Task {
            let entries = await buildEntries(family: context.family)
            // Reload after 5 min (all pages will have cycled by then)
            let refresh = Calendar.current.date(byAdding: .minute, value: 5, to: .now)!
            completion(Timeline(entries: entries, policy: .after(refresh)))
        }
    }

    // MARK: Private

    /// Build one entry per carousel page, staggered 30 s apart.
    private func buildEntries(family: WidgetFamily) async -> [StibLineEntry] {
        let lineNumbers = loadLineNumbers()
        guard !lineNumbers.isEmpty else {
            return [StibLineEntry(date: .now, lines: [], totalLineCount: 0, pageIndex: 0)]
        }

        // Fetch all snapshots in parallel, preserving order
        var ordered = [StibLineSnapshot?](repeating: nil, count: lineNumbers.count)
        await withTaskGroup(of: (Int, StibLineSnapshot?).self) { group in
            for (i, line) in lineNumbers.enumerated() {
                group.addTask { (i, await fetchLineStatus(line)) }
            }
            for await (i, snap) in group {
                ordered[i] = snap ?? StibLineSnapshot(
                    id: lineNumbers[i], lineNumber: lineNumbers[i],
                    status: .unknown, nextPassageMinutes: nil, destination: nil)
            }
        }
        let allSnaps = ordered.compactMap { $0 }

        // Page size depends on widget family
        let pageSize = family == .systemLarge ? 4 : 2
        let pages = stride(from: 0, to: allSnaps.count, by: pageSize).map { i in
            Array(allSnaps[i..<min(i + pageSize, allSnaps.count)])
        }

        return pages.enumerated().map { idx, page in
            let date = idx == 0 ? Date() : Calendar.current.date(byAdding: .second, value: idx * 30, to: .now)!
            return StibLineEntry(date: date, lines: page, totalLineCount: allSnaps.count, pageIndex: idx)
        }
    }

    /// Nearby lines written by the app take priority; falls back to favorites.
    private func loadLineNumbers() -> [String] {
        let ud = UserDefaults(suiteName: appGroupID) ?? .standard
        if let nearby = ud.stringArray(forKey: nearbyLinesKey), !nearby.isEmpty {
            return Array(nearby.prefix(8))
        }
        return Array((ud.stringArray(forKey: favoriteLinesKey) ?? []).prefix(8))
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
            return StibLineSnapshot(id: line, lineNumber: line, status: status,
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

// MARK: - Entry view

struct StibAlertWidgetEntryView: View {
    let entry: StibLineEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall:  SmallWidgetView(entry: entry)
        case .systemLarge:  LargeWidgetView(entry: entry)
        default:            MediumWidgetView(entry: entry)
        }
    }
}

// MARK: - Small

private struct SmallWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if let line = entry.lines.first {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Text("StibAlert")
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .tracking(1.2)
                        .foregroundStyle(WD.inkMute)
                    Spacer()
                    WStatusPip(status: line.status)
                }

                Spacer()

                HStack(alignment: .bottom, spacing: 10) {
                    WLineBadge(line: line.lineNumber, size: 42)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(WD.formatMinutes(line.nextPassageMinutes ?? -1))
                            .font(.system(size: 24, weight: .black, design: .rounded))
                            .foregroundStyle(nextColor(line.nextPassageMinutes))
                            .minimumScaleFactor(0.7)
                            .lineLimit(1)
                        if let dest = line.destination, !dest.isEmpty {
                            Text(dest)
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundStyle(WD.inkMute)
                                .lineLimit(1)
                        }
                    }
                }

                Spacer().frame(height: 10)

                HStack(spacing: 4) {
                    Image(systemName: WD.modeIcon(for: line.lineNumber))
                        .font(.system(size: 8, weight: .bold))
                    Text(line.status.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(line.status.dsColor)
            }
            .padding(13)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .containerBackground(WD.background, for: .widget)
        } else {
            EmptyWidgetView()
        }
    }

    private func nextColor(_ minutes: Int?) -> Color {
        guard let m = minutes, m >= 0 else { return WD.inkMute }
        if m == 0 { return WD.primary }
        if m <= 3 { return WD.statusMinor }
        return WD.ink
    }
}

// MARK: - Medium (2 cards + carousel dots)

private struct MediumWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if entry.lines.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("StibAlert")
                        .font(.system(size: 10, weight: .black, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(WD.primary)
                    Spacer()
                    // Carousel page dots
                    if entry.totalLineCount > 2 {
                        PageDots(total: Int(ceil(Double(entry.totalLineCount) / 2)), current: entry.pageIndex)
                    }
                    Text(entry.date, style: .time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WD.inkMute)
                        .padding(.leading, 6)
                }

                HStack(spacing: 8) {
                    ForEach(entry.lines.prefix(2)) { line in
                        MediumLineCard(line: line)
                    }
                    // Pad to 2 cards if only 1 line on last page
                    if entry.lines.count < 2 {
                        Spacer()
                    }
                }
            }
            .padding(12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(WD.background, for: .widget)
        }
    }
}

// MARK: - Large (4 rows)

private struct LargeWidgetView: View {
    let entry: StibLineEntry

    var body: some View {
        if entry.lines.isEmpty {
            EmptyWidgetView()
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack {
                    Text("StibAlert")
                        .font(.system(size: 11, weight: .black, design: .monospaced))
                        .tracking(1.6)
                        .foregroundStyle(WD.primary)
                    Spacer()
                    if entry.totalLineCount > 4 {
                        PageDots(total: Int(ceil(Double(entry.totalLineCount) / 4)), current: entry.pageIndex)
                    }
                    Text(entry.date, style: .time)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(WD.inkMute)
                        .padding(.leading, 6)
                }
                .padding(.bottom, 10)

                VStack(spacing: 0) {
                    ForEach(Array(entry.lines.prefix(4).enumerated()), id: \.element.id) { idx, line in
                        LargeLineRow(line: line)
                        if idx < entry.lines.prefix(4).count - 1 {
                            Rectangle()
                                .fill(WD.border)
                                .frame(height: 0.5)
                        }
                    }
                }
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(WD.paper2)
                        .overlay(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .stroke(WD.border, lineWidth: 1)
                        )
                )

                Spacer()
            }
            .padding(14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .containerBackground(WD.background, for: .widget)
        }
    }
}

private struct LargeLineRow: View {
    let line: StibLineSnapshot

    var body: some View {
        HStack(spacing: 10) {
            WLineBadge(line: line.lineNumber, size: 32)

            VStack(alignment: .leading, spacing: 1) {
                if let dest = line.destination, !dest.isEmpty {
                    Text(dest)
                        .font(.system(size: 12, weight: .semibold, design: .rounded))
                        .foregroundStyle(WD.ink)
                        .lineLimit(1)
                } else {
                    Text("Direction inconnue")
                        .font(.system(size: 12))
                        .foregroundStyle(WD.inkMute)
                }
                HStack(spacing: 4) {
                    Image(systemName: WD.modeIcon(for: line.lineNumber))
                        .font(.system(size: 8, weight: .bold))
                    Text(line.status.label)
                        .font(.system(size: 9, weight: .semibold, design: .monospaced))
                }
                .foregroundStyle(line.status.dsColor)
            }

            Spacer()

            if let min = line.nextPassageMinutes {
                Text(WD.formatMinutes(min))
                    .font(.system(size: min >= 60 ? 14 : 17, weight: .black, design: .rounded))
                    .foregroundStyle(nextColor(min))
                    .minimumScaleFactor(0.7)
                    .lineLimit(1)
            } else {
                Text("—")
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(WD.inkMute)
            }
        }
        .padding(.horizontal, 12)
        .frame(minHeight: 52)
    }

    private func nextColor(_ minutes: Int) -> Color {
        if minutes == 0 { return WD.primary }
        if minutes <= 3 { return WD.statusMinor }
        return WD.ink
    }
}

// MARK: - Medium card

private struct MediumLineCard: View {
    let line: StibLineSnapshot

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                WLineBadge(line: line.lineNumber, size: 36)
                Spacer()
                VStack(alignment: .trailing, spacing: 1) {
                    if let min = line.nextPassageMinutes {
                        Text(WD.formatMinutes(min))
                            .font(.system(size: 21, weight: .black, design: .rounded))
                            .foregroundStyle(nextColor(min))
                            .minimumScaleFactor(0.65)
                            .lineLimit(1)
                        Text(min >= 60 ? "arrivée" : "prochain")
                            .font(.system(size: 7, weight: .semibold, design: .monospaced))
                            .tracking(0.4)
                            .foregroundStyle(WD.inkMute)
                    } else {
                        Text("—")
                            .font(.system(size: 21, weight: .black, design: .rounded))
                            .foregroundStyle(WD.inkMute)
                    }
                }
            }

            Spacer(minLength: 6)

            if let dest = line.destination, !dest.isEmpty {
                Text(dest)
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(WD.inkSoft)
                    .lineLimit(1)
            } else {
                Text("–")
                    .font(.system(size: 9))
                    .foregroundStyle(WD.inkMute)
            }

            Spacer(minLength: 6)

            HStack(spacing: 4) {
                Image(systemName: WD.modeIcon(for: line.lineNumber))
                    .font(.system(size: 8, weight: .bold))
                Text(line.status.label)
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                Spacer()
                Circle()
                    .fill(line.status.dsColor)
                    .frame(width: 6, height: 6)
            }
            .foregroundStyle(line.status.dsColor)
        }
        .padding(10)
        .frame(maxWidth: .infinity, minHeight: 88, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(WD.paper2)
                .overlay(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(WD.border, lineWidth: 1)
                )
        )
    }

    private func nextColor(_ minutes: Int) -> Color {
        if minutes == 0 { return WD.primary }
        if minutes <= 3 { return WD.statusMinor }
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
            .foregroundStyle(WD.lineTextColor(for: line))
            .minimumScaleFactor(0.55)
            .lineLimit(1)
            .frame(width: size, height: size)
            .background(
                RoundedRectangle(cornerRadius: size * 0.22, style: .continuous)
                    .fill(WD.lineColor(line))
            )
    }
}

private struct WStatusPip: View {
    let status: LineWidgetStatus

    var body: some View {
        HStack(spacing: 3) {
            Circle().fill(status.dsColor).frame(width: 5, height: 5)
            Text(status.label)
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(status.dsColor)
        }
    }
}

private struct PageDots: View {
    let total: Int
    let current: Int

    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<total, id: \.self) { i in
                Circle()
                    .fill(i == current ? WD.primary : WD.inkMute.opacity(0.5))
                    .frame(width: i == current ? 5 : 4, height: i == current ? 5 : 4)
            }
        }
    }
}

private struct EmptyWidgetView: View {
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: "tram.fill")
                .font(.system(size: 22, weight: .bold))
                .foregroundStyle(WD.primary)
            Text("Ouvre StibAlert\npour voir les lignes proches")
                .font(.system(size: 11, weight: .semibold, design: .rounded))
                .foregroundStyle(WD.ink)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .containerBackground(WD.background, for: .widget)
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
        .description("Lignes proches de toi, mises à jour automatiquement.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}
