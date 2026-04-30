import SwiftUI

struct HomeStatusBanner: View {
    let favoriteAffected: Int
    let totalActive: Int
    let lastUpdated: Date?
    let officialNotice: String?
    let onTap: () -> Void

    private enum Level {
        case empty
        case fine
        case warning
        case critical

        var color: Color {
            switch self {
            case .empty: return AppTheme.Palette.info
            case .fine: return AppTheme.Palette.success
            case .warning: return AppTheme.Palette.warning
            case .critical: return AppTheme.Palette.alert
            }
        }

        var icon: String {
            switch self {
            case .empty: return "dot.radiowaves.left.and.right"
            case .fine: return "checkmark.circle.fill"
            case .warning: return "exclamationmark.triangle.fill"
            case .critical: return "exclamationmark.octagon.fill"
            }
        }
    }

    private var level: Level {
        if favoriteAffected >= 3 { return .critical }
        if favoriteAffected > 0 { return .warning }
        if totalActive == 0 { return .empty }
        return .fine
    }

    private var headline: String {
        switch level {
        case .critical, .warning:
            let word = favoriteAffected > 1 ? "perturbations" : "perturbation"
            return "\(favoriteAffected) \(word) sur vos lignes"
        case .fine:
            return "Vos lignes sont OK"
        case .empty:
            return "Aucun signalement actif"
        }
    }

    private var subline: String {
        var parts: [String] = []
        if totalActive > 0 {
            let word = totalActive > 1 ? "signalements" : "signalement"
            parts.append("\(totalActive) \(word) à Bruxelles")
        }
        if let lastUpdated {
            parts.append("MAJ \(relativeTime(from: lastUpdated))")
        }
        return parts.joined(separator: " · ")
    }

    private var showsOfficialNotice: Bool {
        guard let officialNotice else { return false }
        return !officialNotice.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 10) {
                    Image(systemName: level.icon)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(DS.Color.paper)
                        .frame(width: 26, height: 26)
                        .background(level.color)
                        .clipShape(Circle())

                    VStack(alignment: .leading, spacing: 2) {
                        Text(headline)
                            .font(DS.Font.bodyBold)
                            .foregroundStyle(DS.Color.ink)
                            .lineLimit(1)

                        if !subline.isEmpty {
                            Text(subline)
                                .font(DS.Font.monoSmall)
                                .tracking(0.8)
                                .foregroundStyle(DS.Color.inkMute)
                                .lineLimit(1)
                        }
                    }

                    Spacer(minLength: 0)

                    Image(systemName: "chevron.right")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(DS.Color.inkMute)
                }

                if showsOfficialNotice, let officialNotice {
                    HStack(spacing: 8) {
                        Image(systemName: "antenna.radiowaves.left.and.right.slash")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(DS.Color.statusMinor)
                        Text(officialNotice)
                            .font(DS.Font.caption)
                            .foregroundStyle(DS.Color.inkSoft)
                            .multilineTextAlignment(.leading)
                            .lineLimit(2)
                    }
                    .padding(.horizontal, 9)
                    .padding(.vertical, 7)
                    .background(DS.Color.statusMinor.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                            .stroke(DS.Color.statusMinor.opacity(0.24), lineWidth: 1)
                    )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(DS.Color.paper.opacity(0.96))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                    .stroke(level.color.opacity(0.45), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
            .shadow(DS.Shadow.floating)
        }
        .buttonStyle(.plain)
        .accessibilityLabel([headline, subline, officialNotice].compactMap { $0 }.joined(separator: ". "))
    }

    private func relativeTime(from date: Date) -> String {
        let seconds = Int(Date().timeIntervalSince(date))
        if seconds < 30 { return "à l'instant" }
        if seconds < 60 { return "il y a \(seconds) s" }
        let minutes = seconds / 60
        if minutes < 60 { return "il y a \(minutes) min" }
        let hours = minutes / 60
        return "il y a \(hours) h"
    }
}
