import SwiftUI

// MARK: - Accessibility Utilities

/// Helper to format duration for screen readers
func formatDurationForA11y(_ minutes: Int) -> String {
    if minutes <= 0 {
        return "Imminent"
    } else if minutes < 60 {
        return "Dans \(minutes) minute\(minutes == 1 ? "" : "s")"
    } else {
        let hours = minutes / 60
        let mins = minutes % 60
        // Texte lu par VoiceOver : le pluriel vient de la traduction, jamais d'un
        // « s » concaténé (le néerlandais ne forme pas ses pluriels ainsi).
        let hourStr = AppLocalizer.format("plural.hours", defaultValue: "%lld heures", hours)
        if mins == 0 {
            return AppLocalizer.format("a11y.in_time", defaultValue: "Dans %@", hourStr)
        }
        let minStr = AppLocalizer.format("plural.minutes", defaultValue: "%lld minutes", mins)
        return AppLocalizer.format("a11y.in_time_and", defaultValue: "Dans %@ et %@", hourStr, minStr)
    }
}

/// Helper to format transfers/correspondances for screen readers
func formatTransfersForA11y(_ count: Int) -> String {
    if count == 0 {
        return AppLocalizer.string("a11y.direct_no_transfer", defaultValue: "Direct, pas de correspondances")
    }
    return AppLocalizer.format("plural.transfers", defaultValue: "%lld correspondances", count)
}

// MARK: - Stop Card Accessibility Helpers

/// Accessibility label for HomeStopPreviewCard body
struct StopCardAccessibilityLabel: View {
    let stopName: String
    let lines: [String]
    let isLoading: Bool
    let hasError: Bool
    let nextDeparture: String?

    private var lineInfo: String {
        lines.isEmpty
            ? "Aucune ligne disponible"
            : AppLocalizer.format("a11y.lines_list", defaultValue: "Lignes : %@", lines.joined(separator: ", "))
    }

    private var departureInfo: String {
        if isLoading {
            return AppLocalizer.string("a11y.loading", defaultValue: "Chargement en cours")
        } else if hasError {
            return AppLocalizer.string("a11y.departures_error", defaultValue: "Erreur de chargement des passages")
        } else if let nextDeparture {
            return nextDeparture
        } else {
            return AppLocalizer.string("stopdetail.no_departures", defaultValue: "Aucun passage prévu pour le moment")
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(stopName).hidden()
            Text(lineInfo).hidden()
            Text(departureInfo).hidden()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Arrêt: \(stopName)")
        .accessibilityValue("\(lineInfo). \(departureInfo).")
    }
}

// MARK: - Departure Accessibility
/// Format a departure for screen readers with proper grammar
func formatDepartureForA11y(line: String, destination: String?, minutesUntil: Int) -> String {
    let dest = destination ?? "direction"
    let time = formatDurationForA11y(minutesUntil)
    return "Ligne \(line) vers \(dest), \(time)"
}

// MARK: - Route Accessibility
/// Format route summary for screen readers
func formatRouteForA11y(
    durationMinutes: Int,
    transitSummary: String,
    walkingSummary: String,
    reliabilityText: String
) -> String {
    let duration = formatDurationForA11y(durationMinutes)
    return AppLocalizer.format("a11y.route_summary",
                               defaultValue: "%@, %@. %@. Durée : %@",
                               transitSummary, walkingSummary, reliabilityText, duration)
}

// MARK: - Error Message View
struct AccessibleErrorMessage: View {
    let error: String
    let onRetry: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "exclamationmark.circle")
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(DS.Color.statusMajor)

            VStack(alignment: .leading, spacing: 4) {
                Text("Erreur de chargement")
                    .font(DS.Font.bodyBold)
                    .foregroundStyle(DS.Color.ink)

                Text(error)
                    .font(DS.Font.body)
                    .foregroundStyle(DS.Color.inkMute)
                    .lineLimit(2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            Button(action: onRetry) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(DS.Color.primary)
                    .frame(width: 44, height: 44)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Réessayer")
            .accessibilityHint("Double-tap pour réessayer le chargement")
        }
        .padding(14)
        .background(DS.Color.statusMajor.opacity(0.08))
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(DS.Color.statusMajor.opacity(0.3), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Erreur: \(error)")
    }
}
