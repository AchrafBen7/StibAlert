import SwiftUI

struct MapClusterMarker: View {
    let count: Int
    let dominantType: String

    private var color: Color {
        switch dominantType {
        case "Accident", "Agression": return AppTheme.Palette.alert
        case "Retard", "Panne": return AppTheme.Palette.warning
        case "Incivilité": return AppTheme.Palette.info
        case "Propreté": return AppTheme.Palette.success
        default: return AppTheme.Palette.brand
        }
    }

    private var diameter: CGFloat {
        if count >= 100 { return 44 }
        if count >= 20 { return 40 }
        if count >= 5 { return 34 }
        return 30
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(color.opacity(0.25))
                .frame(width: diameter + 14, height: diameter + 14)

            Circle()
                .fill(color)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .stroke(Color.white, lineWidth: 2.5)
                )
                .shadow(color: color.opacity(0.35), radius: 6, x: 0, y: 2)

            Text("\(count)")
                .font(AppTheme.Fonts.captionStrong)
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Groupe de \(count) signalements, majoritairement \(dominantType.lowercased())")
    }
}
