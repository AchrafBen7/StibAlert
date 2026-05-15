import SwiftUI

/// TGTG-style numeric circle shown on the map when multiple community clusters
/// are grouped at low zoom. Tap zooms the camera into the bounding region so
/// the underlying pins can be inspected individually.
struct ClusterCountMarker: View {
    let count: Int

    var body: some View {
        Text("\(count)")
            .font(.system(size: count > 99 ? 13 : 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(DS.Color.primary)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.9), lineWidth: 2)
                    )
            )
            .shadow(color: Color.black.opacity(0.25), radius: 4, y: 2)
            .accessibilityLabel("\(count) alertes communautaires")
    }

    private var diameter: CGFloat {
        switch count {
        case 0...9: return 32
        case 10...99: return 38
        default: return 44
        }
    }
}
