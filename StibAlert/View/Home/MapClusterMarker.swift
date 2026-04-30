import SwiftUI

struct MapClusterMarker: View {
    let count: Int
    let dominantType: String

    private var accent: Color {
        switch dominantType {
        case "Accident", "Agression": return DS.Color.statusMajor
        case "Retard", "Panne": return DS.Color.statusMinor
        case "Incivilité": return DS.Color.community
        case "Propreté": return DS.Color.villo
        default: return DS.Color.primary
        }
    }

    private var diameter: CGFloat {
        if count >= 100 { return 48 }
        if count >= 20 { return 44 }
        if count >= 5 { return 38 }
        return 34
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.14))
                .frame(width: diameter + 18, height: diameter + 18)

            Circle()
                .fill(DS.Color.paper)
                .frame(width: diameter, height: diameter)
                .overlay(
                    Circle()
                        .stroke(DS.Color.ink.opacity(0.18), lineWidth: 1.5)
                )

            Circle()
                .fill(accent)
                .frame(width: diameter - 8, height: diameter - 8)
                .shadow(color: accent.opacity(0.28), radius: 6, x: 0, y: 3)

            Text("\(count)")
                .font(.system(size: count >= 100 ? 12 : 13, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .accessibilityLabel("Groupe de \(count) signalements, majoritairement \(dominantType.lowercased())")
    }
}
