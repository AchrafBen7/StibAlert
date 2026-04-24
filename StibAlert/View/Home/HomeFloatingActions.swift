import SwiftUI
import UIKit

struct HomeFloatingActions: View {
    let onReport: () -> Void
    let onRoute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FloatingActionButton(
                icon: "arrow.triangle.turn.up.right.diamond.fill",
                label: "Itinéraire",
                background: Color(hex: "#2563EB"),
                foreground: .white,
                action: onRoute
            )

            FloatingActionButton(
                icon: "exclamationmark.bubble.fill",
                label: "Signaler",
                background: Color(hex: "#E23B3B"),
                foreground: .white,
                action: onReport
            )
        }
        .padding(.horizontal, 18)
    }
}

private struct FloatingActionButton: View {
    let icon: String
    let label: String
    let background: Color
    let foreground: Color
    let action: () -> Void

    var body: some View {
        Button(action: {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            action()
        }) {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                Text(label)
                    .font(.custom("Montserrat-SemiBold", size: 14))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 18)
            .frame(height: 52)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 26, style: .continuous)
                    .fill(background)
            )
            .shadow(color: background.opacity(0.35), radius: 10, x: 0, y: 6)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
