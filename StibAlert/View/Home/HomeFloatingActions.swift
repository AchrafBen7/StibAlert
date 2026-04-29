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
        .padding(8)
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 22, style: .continuous)
                .stroke(Color.white.opacity(0.14), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: 8)
        .padding(.horizontal, 20)
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
                    .font(.system(size: 15, weight: .semibold))
                Text(label)
                    .font(.custom("Montserrat-SemiBold", size: 13))
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(background)
            )
            .shadow(color: background.opacity(0.24), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
