import SwiftUI
import UIKit

struct HomeFloatingActions: View {
    let onReport: () -> Void
    let onRoute: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            FloatingActionButton(
                icon: "arrow.triangle.turn.up.right.diamond",
                label: "Itinéraire",
                background: DS.Color.accent,
                foreground: DS.Color.primaryForeground,
                action: onRoute
            )

            FloatingActionButton(
                icon: "exclamationmark.bubble",
                label: "Signaler",
                background: DS.Color.primary,
                foreground: DS.Color.primaryForeground,
                action: onReport
            )
        }
        .padding(8)
        .background(DS.Color.paper.opacity(0.96))
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
        )
        .shadow(DS.Shadow.floating)
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
                    .font(DS.Font.bodyBold)
            }
            .foregroundStyle(foreground)
            .padding(.horizontal, 14)
            .frame(height: 46)
            .frame(maxWidth: .infinity)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(background)
            )
            .shadow(color: background.opacity(0.24), radius: 8, x: 0, y: 4)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}
