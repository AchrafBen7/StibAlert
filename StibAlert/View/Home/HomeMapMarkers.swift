import SwiftUI

/// Visual style for a stop's ⚠ badge — colour + SF symbol derived from the
/// colocated signalement so the badge matches the marker it replaces. `rank`
/// breaks ties when several signals share one stop (highest wins).
struct StopWarningStyle {
    let color: Color
    let icon: String
    let rank: Int
}

/// Single source of truth mapping a problem type → SF symbol, shared by the
/// map cluster marker and the on-stop badge so they never drift apart.
enum SignalVisuals {
    static func icon(forType type: String) -> String {
        switch type.lowercased() {
        case "retard": return "clock.fill"
        case "panne", "interruption": return "exclamationmark.octagon.fill"
        case "accident": return "exclamationmark.triangle.fill"
        case "travaux", "déviation": return "exclamationmark.triangle.fill"
        case "agression", "incivilité": return "shield.lefthalf.filled"
        case "propreté": return "trash.fill"
        case "perturbation": return "bolt.fill"
        case "arrêt non desservi": return "xmark.octagon.fill"
        case "information stib": return "info.circle.fill"
        default: return "exclamationmark.bubble.fill"
        }
    }

    /// Marker/badge colour for a community cluster — mirrors `ClusterMarker`.
    static func communityColor(for cluster: ClusterDTO) -> Color {
        if cluster.isOfficial { return DS.Color.info }
        switch cluster.confidence {
        case .high: return DS.Color.danger
        case .medium: return DS.Color.warning
        case .low: return Color(hex: "#9CA3AF")
        }
    }
}

struct UserLocationDotView: View {
    let heading: Double

    var body: some View {
        ZStack {
            DirectionConeShape()
                .fill(LinearGradient(
                    colors: [DS.Color.info.opacity(0.55), .clear],
                    startPoint: .top, endPoint: .bottom
                ))
                .frame(width: 28, height: 36)
                .offset(y: -16)
                .rotationEffect(.degrees(heading))

            Circle()
                .fill(DS.Color.background)
                .frame(width: 12, height: 12)
                .overlay(Circle().stroke(DS.Color.info, lineWidth: 1))
                .shadow(color: Color(red: 0.499, green: 0.527, blue: 0.962), radius: 4, x: 0, y: 4)
        }
    }
}

private struct DirectionConeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: rect.midX, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        p.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        p.closeSubpath()
        return p
    }
}

struct LiveSignalMarker: View {
    let problemType: String

    private var color: Color {
        switch problemType {
        case "Accident", "Agression": return DS.Color.danger
        case "Retard", "Panne": return DS.Color.warning
        case "Incivilité": return DS.Color.info
        case "Propreté": return DS.Color.success
        default: return DS.Color.primary
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color)
                .frame(width: 18, height: 18)
                .shadow(color: .black.opacity(0.35), radius: 2, x: 0, y: 1)
            Circle()
                .stroke(Color.white, lineWidth: 2)
                .frame(width: 18, height: 18)
        }
        .accessibilityElement()
        .accessibilityLabel("Signalement \(problemType)")
        .accessibilityHint("Ouvre le détail du signalement")
    }
}

struct OfficialSignalMarker: View {
    let problemType: String
    @State private var pulse = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .fill(DS.Color.danger.opacity(pulse ? 0.16 : 0.34))
                        .frame(width: pulse ? 48 : 38, height: pulse ? 46 : 36)
                        .scaleEffect(pulse ? 1.12 : 0.92)

                    RoundedRectangle(cornerRadius: 9, style: .continuous)
                        .fill(DS.Color.danger)
                        .frame(width: 34, height: 32)
                        .shadow(color: DS.Color.danger.opacity(0.35), radius: 8, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 2)

                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.system(size: 15, weight: .black))
                        .foregroundStyle(.white)
                }

                Text("STIB")
                    .font(.system(size: 6, weight: .black, design: .rounded))
                    .kerning(0.35)
                    .foregroundStyle(Color(hex: "#0055A4"))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
                    .background(Color.white)
                    .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    .offset(x: 7, y: -6)
            }

            TrianglePointer()
                .fill(DS.Color.danger)
                .frame(width: 12, height: 7)
                .offset(y: -1)
        }
        .onAppear {
            withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                pulse = true
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Alerte officielle STIB — \(problemType)")
        .accessibilityHint("Ouvre le détail de la perturbation officielle")
    }
}

private struct TrianglePointer: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}

struct HomeStopMarker: View {
    let stop: TransportStopSummaryDTO
    let isSelected: Bool
    /// Non-nil when an active signalement (community OR official STIB) sits on
    /// this stop. Instead of drawing a separate warning pin on top of the
    /// marker (which used to cover the stop name + line dots), we tuck a small
    /// badge — coloured + iconed by the issue's type/severity — into the
    /// corner of the name pill.
    var warningStyle: StopWarningStyle? = nil

    /// De-duplicated, normalised line list. Cap at 5 visible circles +
    /// "+N" suffix so a busy hub like Châtelet doesn't spawn a marker
    /// twenty circles wide.
    private var displayedLines: [String] {
        var seen = Set<String>()
        return stop.lines.filter { line in
            let key = line.trimmingCharacters(in: .whitespaces).uppercased()
            guard !key.isEmpty, !seen.contains(key) else { return false }
            seen.insert(key)
            return true
        }
    }
    private var visibleLines: [String] { Array(displayedLines.prefix(5)) }
    private var hiddenLinesCount: Int { max(displayedLines.count - 5, 0) }

    var body: some View {
        VStack(spacing: 3) {
            // Stop name label (IDF Mobilités style) — small pill above the
            // line dots so users can read which stop they're tapping.
            Text(stop.name)
                .font(.system(size: 9, weight: .bold))
                .lineLimit(1)
                .foregroundStyle(DS.Color.ink)
                .padding(.horizontal, 6)
                .frame(height: 18)
                .background(
                    Capsule()
                        .fill(DS.Color.paper.opacity(0.96))
                )
                .overlay(
                    Capsule()
                        .stroke(
                            isSelected ? DS.Color.ink : DS.Color.ink.opacity(0.18),
                            lineWidth: isSelected ? 1.5 : 1
                        )
                )
                .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
                .overlay(alignment: .topTrailing) {
                    if let warningStyle {
                        Image(systemName: warningStyle.icon)
                            .font(.system(size: 7.5, weight: .black))
                            .foregroundStyle(.white)
                            .frame(width: 15, height: 15)
                            .background(Circle().fill(warningStyle.color))
                            .overlay(Circle().stroke(DS.Color.paper, lineWidth: 1.5))
                            .offset(x: 5, y: -5)
                    }
                }

            // Row of small line circles in their official colours.
            HStack(spacing: 2) {
                ForEach(visibleLines, id: \.self) { line in
                    lineDot(line)
                }
                if hiddenLinesCount > 0 {
                    Text("+\(hiddenLinesCount)")
                        .font(.system(size: 8, weight: .bold, design: .rounded))
                        .foregroundStyle(DS.Color.ink)
                        .frame(minWidth: 16, minHeight: 16)
                        .padding(.horizontal, 2)
                        .background(DS.Color.paper)
                        .overlay(
                            Capsule()
                                .stroke(DS.Color.ink.opacity(0.2), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
            }
        }
        .scaleEffect(isSelected ? 1.08 : 1)
        .accessibilityElement()
        .accessibilityLabel("Arrêt \(stop.name)")
        .accessibilityHint("Ouvre les détails et prochains passages")
    }

    private func lineDot(_ line: String) -> some View {
        let fill = TransitLinePalette.fill(for: line)
        let fg = TransitLinePalette.foreground(for: line)
        return Text(line)
            .font(.system(size: 8, weight: .black, design: .rounded))
            .foregroundStyle(fg)
            .frame(width: 16, height: 16)
            .background(Circle().fill(fill))
            .overlay(Circle().stroke(DS.Color.paper, lineWidth: 1))
            .minimumScaleFactor(0.7)
            .lineLimit(1)
    }
}

struct SNCBStationMarker: View {
    let station: SNCBStation
    let isSelected: Bool
    var warningStyle: StopWarningStyle? = nil

    var body: some View {
        VStack(spacing: 3) {
            HStack(spacing: 4) {
                Text(station.displayName)
                    .font(.system(size: 9, weight: .bold))
                    .lineLimit(1)
                    .foregroundStyle(DS.Color.ink)

                Image("operator-sncb")
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 16, height: 12)
            }
            .padding(.horizontal, 7)
            .frame(height: 19)
            .background(Capsule().fill(DS.Color.paper.opacity(0.97)))
            .overlay(
                Capsule()
                    .stroke(isSelected ? Color(hex: "#0055A4") : DS.Color.ink.opacity(0.18), lineWidth: isSelected ? 1.5 : 1)
            )
            .shadow(color: .black.opacity(0.12), radius: 3, x: 0, y: 1)
            .overlay(alignment: .topTrailing) {
                if let warningStyle {
                    Image(systemName: warningStyle.icon)
                        .font(.system(size: 7.5, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 15, height: 15)
                        .background(Circle().fill(warningStyle.color))
                        .overlay(Circle().stroke(DS.Color.paper, lineWidth: 1.5))
                        .offset(x: 6, y: -5)
                }
            }

            // Small pin dot — same footprint as a STIB line dot (was an
            // oversized blue block + pointer that dominated the map).
            ZStack {
                Circle()
                    .fill(Color(hex: "#0055A4"))
                    .frame(width: 18, height: 18)
                    .overlay(Circle().stroke(DS.Color.paper, lineWidth: 1.5))
                    .shadow(color: .black.opacity(0.18), radius: 2, x: 0, y: 1)
                Image(systemName: "train.side.front.car")
                    .font(.system(size: 8, weight: .black))
                    .foregroundStyle(.white)
            }
        }
        .scaleEffect(isSelected ? 1.1 : 1)
        .accessibilityElement()
        .accessibilityLabel("Gare SNCB \(station.displayName)")
        .accessibilityHint("Sélectionne la gare")
    }
}

struct VilloMapMarker: View {
    let station: VilloStation

    private var fill: Color {
        switch visualState {
        case .closed:
            return Color.white.opacity(0.32)
        case .empty:
            return Color(hex: "#FF7A7A")
        case .low:
            return Color(hex: "#FFB15A")
        case .full:
            return Color(hex: "#7DB6FF")
        case .healthy:
            return Color(hex: "#57E3B6")
        }
    }

    private var stroke: Color {
        switch visualState {
        case .closed:
            return Color.white.opacity(0.55)
        case .empty:
            return Color(hex: "#FFD1D1")
        case .low:
            return Color(hex: "#FFE1BA")
        case .full:
            return Color(hex: "#D5E7FF")
        case .healthy:
            return Color(hex: "#CCF8EA")
        }
    }

    private var bikeBadgeText: String {
        "\(station.availableBikes)"
    }

    private var docksBadgeText: String {
        "+\(station.availableBikeStands)"
    }

    private var visualState: VilloVisualState {
        if !station.isOperational { return .closed }
        if station.availableBikes == 0 { return .empty }
        if station.availableBikeStands == 0 { return .full }
        if station.availableBikes <= 3 { return .low }
        return .healthy
    }

    var body: some View {
        VStack(spacing: 3) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: 32, height: 32)
                    .overlay(
                        Circle().stroke(stroke, lineWidth: 2)
                    )

                Image(systemName: "bicycle")
                    .font(.system(size: 13, weight: .bold))
                    .foregroundStyle(.black)
                    .frame(width: 32, height: 32, alignment: .center)

                Text(bikeBadgeText)
                    .font(.custom("Montserrat-SemiBold", size: 9))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 5)
                    .frame(height: 17)
                    .background(Color.white)
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
                    )
                    .offset(x: 12, y: -10)
            }
            .frame(width: 42, height: 36)

            Text(docksBadgeText)
                .font(.custom("Montserrat-SemiBold", size: 9))
                .foregroundStyle(.white.opacity(0.92))
                .padding(.horizontal, 6)
                .frame(height: 16)
                .background(Color.black.opacity(0.45))
                .clipShape(Capsule())
        }
        .shadow(color: .black.opacity(0.25), radius: 6, x: 0, y: 4)
        .accessibilityElement()
        .accessibilityLabel("Station Villo! \(station.displayName)")
        .accessibilityHint("Ouvre l’état de la station vélo")
    }

    private enum VilloVisualState {
        case closed
        case empty
        case low
        case full
        case healthy
    }
}

struct EventMapMarker: View {
    let event: TransportEventImpactDTO

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                HStack(spacing: 0) {
                    Rectangle()
                        .fill(backgroundTint)
                        .frame(width: 5)

                    ZStack {
                        DS.Color.paper.opacity(0.98)

                        Image(systemName: "calendar.badge.exclamationmark")
                            .font(.system(size: 14, weight: .bold))
                            .foregroundStyle(DS.Color.ink)
                    }
                    .frame(width: 34, height: 38)
                }
                .frame(width: 39, height: 38)
                .clipShape(RoundedRectangle(cornerRadius: 11, style: .continuous))
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )

                if let firstLine = event.impactedLines.first, !firstLine.isEmpty {
                    Text(firstLine)
                        .font(.system(size: 9, weight: .bold, design: .monospaced))
                        .foregroundStyle(TransitLinePalette.foreground(for: firstLine))
                        .frame(minWidth: 18, minHeight: 16)
                        .padding(.horizontal, 3)
                        .background(TransitLinePalette.fill(for: firstLine))
                        .overlay(
                            RoundedRectangle(cornerRadius: 4, style: .continuous)
                                .stroke(DS.Color.ink, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                        .offset(x: 6, y: -6)
                }
            }

            Diamond()
                .fill(DS.Color.paper.opacity(0.98))
                .frame(width: 11, height: 11)
                .overlay(
                    Diamond()
                        .stroke(DS.Color.ink, lineWidth: 1.5)
                )
                .offset(y: -4)
        }
        .shadow(color: .black.opacity(0.18), radius: 8, x: 0, y: 5)
        .accessibilityLabel("Événement \(event.title)")
    }

    private var backgroundTint: Color {
        switch event.impactLevel?.lowercased() {
        case "high":
            return Color(hex: "#FF8E6A")
        case "moderate":
            return Color(hex: "#F3C15D")
        default:
            return Color(hex: "#B8E28A")
        }
    }
}

private struct Diamond: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.midY))
        path.closeSubpath()
        return path
    }
}
