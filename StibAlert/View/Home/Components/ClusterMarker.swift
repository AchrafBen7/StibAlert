import SwiftUI

struct ClusterMarker: View {
    let cluster: ClusterDTO
    var isSelected: Bool = false
    @State private var pulse = false

    private var color: Color {
        if cluster.isOfficial {
            return Color(hex: "#3E7BFE")
        }
        switch cluster.confidence {
        case .high: return Color(hex: "#E94E1B")
        case .medium: return Color(hex: "#F59E0B")
        case .low: return Color(hex: "#9CA3AF")
        }
    }

    private var iconName: String {
        switch cluster.typeProbleme.lowercased() {
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
                            .fill(color.opacity(pulse ? 0.10 : 0.28))
                            .frame(width: pulse ? 56 : 42, height: pulse ? 56 : 42)
                            .scaleEffect(pulse ? 1.15 : 0.95)
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
        .onAppear {
            if freshness {
                withAnimation(.easeInOut(duration: 0.72).repeatForever(autoreverses: true)) {
                    pulse = true
                }
            }
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
