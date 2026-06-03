import WidgetKit
import SwiftUI

private let backendBaseURL = "https://stib-alert-backend.onrender.com"
private let appGroupID = "group.com.ehb.StibAlert"
private let favoriteLinesKey = "favoriteLines"

// MARK: - Model

enum VerdictLevel: String, Decodable {
    case allClear = "ALL_CLEAR"
    case watch = "WATCH"
    case caution = "CAUTION"
    case avoid = "AVOID"

    var iconSystemName: String {
        switch self {
        case .allClear: return "checkmark.seal.fill"
        case .watch:    return "eye.fill"
        case .caution:  return "exclamationmark.triangle.fill"
        case .avoid:    return "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .allClear: return Color(red: 0.2, green: 0.72, blue: 0.48)
        case .watch:    return Color(red: 0.42, green: 0.45, blue: 0.50)
        case .caution:  return Color(red: 0.99, green: 0.58, blue: 0.14)
        case .avoid:    return Color(red: 0.89, green: 0.24, blue: 0.20)
        }
    }

    var label: String {
        switch self {
        case .allClear: return "Voie libre"
        case .watch:    return "À surveiller"
        case .caution:  return "Prudence"
        case .avoid:    return "Évite"
        }
    }
}

struct VerdictEntry: TimelineEntry {
    let date: Date
    let verdict: VerdictLevel
    let headline: String
    let line: String?
}

// MARK: - Provider

struct VerdictProvider: TimelineProvider {
    func placeholder(in context: Context) -> VerdictEntry {
        VerdictEntry(
            date: .now,
            verdict: .allClear,
            headline: "Tes lignes habituelles sont fluides ce matin.",
            line: "92"
        )
    }

    func getSnapshot(in context: Context, completion: @escaping (VerdictEntry) -> Void) {
        Task { completion(await fetchEntry()) }
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<VerdictEntry>) -> Void) {
        Task {
            let entry = await fetchEntry()
            let refresh = Calendar.current.date(byAdding: .minute, value: 10, to: .now)!
            completion(Timeline(entries: [entry], policy: .after(refresh)))
        }
    }

    private func fetchEntry() async -> VerdictEntry {
        let firstFav = loadFirstFavoriteLine()
        var components = URLComponents(string: "\(backendBaseURL)/api/decision")
        if let firstFav {
            components?.queryItems = [URLQueryItem(name: "ligne", value: firstFav)]
        }

        guard let url = components?.url else {
            return placeholderUnknown(line: firstFav)
        }

        struct DecisionResponse: Decodable {
            let verdict: VerdictLevel?
            let headline: String?
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let decoded = try JSONDecoder().decode(DecisionResponse.self, from: data)
            return VerdictEntry(
                date: .now,
                verdict: decoded.verdict ?? .allClear,
                headline: decoded.headline ?? "Réseau STIB nominal.",
                line: firstFav
            )
        } catch {
            return placeholderUnknown(line: firstFav)
        }
    }

    private func placeholderUnknown(line: String?) -> VerdictEntry {
        VerdictEntry(
            date: .now,
            verdict: .allClear,
            headline: "Ouvre StibAlert pour voir le verdict détaillé.",
            line: line
        )
    }

    private func loadFirstFavoriteLine() -> String? {
        let ud = UserDefaults(suiteName: appGroupID) ?? .standard
        return ud.stringArray(forKey: favoriteLinesKey)?.first
    }
}

// MARK: - View

struct MorningVerdictEntryView: View {
    let entry: VerdictEntry
    @Environment(\.widgetFamily) private var family

    var body: some View {
        switch family {
        case .systemSmall: smallView
        default:           mediumView
        }
    }

    private var smallView: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: entry.verdict.iconSystemName)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(entry.verdict.tint)
                Text(entry.verdict.label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.4)
                    .foregroundStyle(entry.verdict.tint)
            }

            Spacer(minLength: 0)

            Text(entry.headline)
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(3)
                .minimumScaleFactor(0.78)
                .multilineTextAlignment(.leading)
                .fixedSize(horizontal: false, vertical: true)

            if let line = entry.line {
                Text("Ligne \(line)")
                    .font(.system(size: 10, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(13)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(backgroundColor.gradient, for: .widget)
    }

    private var mediumView: some View {
        HStack(alignment: .top, spacing: 14) {
            ZStack {
                Circle()
                    .fill(entry.verdict.tint.opacity(0.15))
                    .frame(width: 56, height: 56)
                Image(systemName: entry.verdict.iconSystemName)
                    .font(.system(size: 26, weight: .semibold))
                    .foregroundStyle(entry.verdict.tint)
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(entry.verdict.label.uppercased())
                    .font(.system(size: 10, weight: .black, design: .monospaced))
                    .tracking(1.6)
                    .foregroundStyle(entry.verdict.tint)
                Text(entry.headline)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(3)
                    .fixedSize(horizontal: false, vertical: true)
                if let line = entry.line {
                    Text("Ligne \(line) · StibAlert")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .containerBackground(backgroundColor.gradient, for: .widget)
    }

    private var backgroundColor: Color {
        Color(UIColor.systemBackground)
    }
}

// MARK: - Widget declaration

struct MorningVerdictWidget: Widget {
    let kind = "MorningVerdictWidget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: VerdictProvider()) { entry in
            // Light-only partout (cf. StibAlertWidget) : WidgetKit n'hérite pas
            // du UIUserInterfaceStyle de l'app, on force donc le thème clair.
            MorningVerdictEntryView(entry: entry)
                .environment(\.colorScheme, .light)
        }
        .configurationDisplayName("Verdict matin")
        .description("Le verdict de tes lignes habituelles, mis à jour automatiquement.")
        .supportedFamilies([.systemSmall, .systemMedium])
    }
}
