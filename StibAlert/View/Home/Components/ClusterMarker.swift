import SwiftUI

struct ClusterMarker: View {
    let cluster: ClusterDTO
    var isSelected: Bool = false

    private var color: Color {
        SignalVisuals.communityColor(for: cluster)
    }

    private var iconName: String {
        SignalVisuals.icon(forType: cluster.typeProbleme)
    }

    private var freshness: Bool {
        guard let lastReportedAt = cluster.lastReportedAt else { return false }
        return Date().timeIntervalSince(lastReportedAt) < 30 * 60
    }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if freshness {
                        Circle()
                            .fill(color.opacity(0.18))
                            .frame(width: 46, height: 46)
                    }

                    Circle()
                        .fill(color)
                        .frame(width: isSelected ? 42 : 36, height: isSelected ? 42 : 36)
                        .shadow(color: color.opacity(0.4), radius: 6, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 2)

                    Image(systemName: iconName)
                        .font(.system(size: 16, weight: .black))
                        .foregroundStyle(.white)
                }

                if cluster.reportCount > 1 {
                    Text("\(cluster.reportCount)")
                        .font(.system(size: 9, weight: .black, design: .rounded))
                        .foregroundStyle(.white)
                        .padding(.horizontal, 5)
                        .padding(.vertical, 3)
                        .background(Color.black)
                        .clipShape(Capsule())
                        .offset(x: 10, y: -8)
                }
            }

            TrianglePointerShape()
                .fill(color)
                .frame(width: 12, height: 7)
                .offset(y: -1)
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint("Ouvre les détails de l'alerte communautaire")
    }

    private var accessibilityLabel: String {
        let confidenceLabel = cluster.confidence.displayLabel
        let officialPrefix = cluster.isOfficial ? "Alerte STIB officielle" : "Alerte communauté"
        return "\(officialPrefix) — \(cluster.typeProbleme) ligne \(cluster.ligne), \(cluster.reportCount) rapports, confiance \(confidenceLabel.lowercased())"
    }
}

private struct TrianglePointerShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
