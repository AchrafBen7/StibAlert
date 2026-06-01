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

    // Forme = SOURCE. Officiel STIB → losange angulaire (autorité), communauté
    // → goutte ronde. Couplé au code couleur (rouge vs bleu), deux signaux
    // indépendants distinguent les marqueurs sans ambiguïté.
    private var isOfficial: Bool { cluster.isOfficial }
    private var side: CGFloat { isSelected ? 42 : 36 }

    var body: some View {
        VStack(spacing: 0) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    if freshness {
                        haloShape
                            .fill(color.opacity(0.18))
                            .frame(width: side + 10, height: side + 10)
                    }

                    markerShape
                        .fill(color)
                        .frame(width: side, height: side)
                        .shadow(color: color.opacity(0.4), radius: 6, x: 0, y: 3)
                        .shadow(color: .black.opacity(0.28), radius: 3, x: 0, y: 2)
                        .overlay(
                            markerShape.stroke(Color.white, lineWidth: 2)
                                .frame(width: side, height: side)
                        )

                    Image(systemName: iconName)
                        .font(.system(size: 15, weight: .black))
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

            // Pointe bas uniquement pour la goutte communauté ; le losange
            // officiel est un badge auto-porté, sans pointe.
            if !isOfficial {
                TrianglePointerShape()
                    .fill(color)
                    .frame(width: 12, height: 7)
                    .offset(y: -1)
            }
        }
        .accessibilityElement()
        .accessibilityLabel(accessibilityLabel)
        .accessibilityHint(isOfficial
            ? "Ouvre le détail de la perturbation officielle"
            : "Ouvre les détails de l'alerte communautaire")
    }

    /// Forme du marqueur : losange (officiel STIB) vs cercle (communauté).
    /// AnyShape (iOS 16+) pour pouvoir renvoyer deux formes concrètes.
    private var markerShape: AnyShape {
        isOfficial ? AnyShape(DiamondShape()) : AnyShape(Circle())
    }

    private var haloShape: AnyShape {
        isOfficial ? AnyShape(DiamondShape()) : AnyShape(Circle())
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

/// Losange (carré pivoté 45°) — forme « officielle STIB ». Sa silhouette
/// angulaire contraste avec la goutte ronde de la communauté.
private struct DiamondShape: Shape {
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
