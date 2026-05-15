import SwiftUI

/// TGTG-style numeric circle shown on the map when multiple pins are grouped
/// at low zoom. Tap zooms the camera into the group's bounding region so the
/// underlying pins can be inspected individually.
struct ClusterCountMarker: View {
    let count: Int
    let origin: MapPinOrigin

    var body: some View {
        Text("\(count)")
            .font(.system(size: count > 99 ? 13 : 15, weight: .black, design: .rounded))
            .foregroundStyle(.white)
            .frame(width: diameter, height: diameter)
            .background(
                Circle()
                    .fill(fillColor)
                    .overlay(
                        Circle().stroke(Color.white.opacity(0.92), lineWidth: 2)
                    )
            )
            .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
            .accessibilityLabel("\(count) alertes")
    }

    private var diameter: CGFloat {
        switch count {
        case 0...9: return 32
        case 10...99: return 38
        default: return 46
        }
    }

    private var fillColor: Color {
        switch origin {
        case .official:  return DS.Color.primary
        case .community: return DS.Color.accent
        }
    }
}
