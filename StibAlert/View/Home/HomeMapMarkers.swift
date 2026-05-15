import SwiftUI

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

    private var primaryLine: String? {
        stop.lines.first
    }

    private var fill: Color {
        if isSelected { return DS.Color.ink }
        guard let primaryLine else { return DS.Color.paper }
        return TransitLinePalette.fill(for: primaryLine)
    }

    private var foreground: Color {
        if isSelected { return DS.Color.paper }
        guard let primaryLine else { return DS.Color.ink }
        return TransitLinePalette.foreground(for: primaryLine)
    }

    private var extraCount: Int {
        max(stop.lines.count - 1, 0)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            ZStack {
                Circle()
                    .fill(fill)
                    .frame(width: isSelected ? 34 : 32, height: isSelected ? 34 : 32)
                    .overlay(
                        Circle()
                            .stroke(DS.Color.paper, lineWidth: 3)
                    )
                    .overlay(
                        Circle()
                            .stroke(DS.Color.ink.opacity(isSelected ? 0.9 : 0.22), lineWidth: isSelected ? 1.5 : 1)
                    )

                Text(primaryLine ?? "•")
                    .font(.system(size: primaryLine?.count ?? 1 > 2 ? 12 : 14, weight: .heavy, design: .rounded))
                    .foregroundStyle(foreground)
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
            }
            .shadow(color: .black.opacity(0.16), radius: 5, x: 0, y: 3)

            if extraCount > 0 {
                Text("+\(extraCount)")
                    .font(.system(size: 10, weight: .bold, design: .rounded))
                    .foregroundStyle(DS.Color.ink)
                    .padding(.horizontal, 6)
                    .frame(height: 18)
                    .background(DS.Color.paper)
                    .overlay(
                        Capsule()
                            .stroke(DS.Color.ink.opacity(0.16), lineWidth: 1)
                    )
                    .clipShape(Capsule())
                    .offset(x: 8, y: -6)
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Arrêt \(stop.name)")
        .accessibilityHint("Ouvre les détails et prochains passages")
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
