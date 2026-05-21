import SwiftUI

/// Map cluster pin for grouped reports. Shaped as a chip (icon + count)
/// instead of a plain numbered circle so users don't confuse it with a
/// generic "N stops grouped" indicator — it always reads as "N reports".
/// Tap zooms the camera into the group's bounding region.
struct ClusterCountMarker: View {
    let count: Int
    let origin: MapPinOrigin

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: iconName)
                .font(.system(size: 11, weight: .black))
            Text("\(count)")
                .font(.system(size: 13, weight: .black, design: .rounded))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 8)
        .frame(height: 26)
        .background(
            Capsule()
                .fill(fillColor)
                .overlay(
                    Capsule().stroke(Color.white.opacity(0.92), lineWidth: 1.5)
                )
        )
        .shadow(color: Color.black.opacity(0.22), radius: 4, y: 2)
        .accessibilityLabel(accessibilityText)
    }

    private var iconName: String {
        switch origin {
        case .official:  return "exclamationmark.triangle.fill"
        case .community: return "bubble.left.and.bubble.right.fill"
        }
    }

    private var fillColor: Color {
        switch origin {
        case .official:  return DS.Color.primary
        case .community: return DS.Color.accent
        }
    }

    private var accessibilityText: String {
        switch origin {
        case .official:  return "\(count) alertes officielles"
        case .community: return "\(count) signalements communauté"
        }
    }
}
