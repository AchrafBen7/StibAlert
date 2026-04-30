import SwiftUI

struct PageHeader: View {
    let title: String
    let eyebrow: String
    var large: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(eyebrow)
                .eyebrow()
            Text(title)
                .font(large ? DS.Font.displayH1 : DS.Font.displayH2)
                .foregroundStyle(DS.Color.ink)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SectionTitle: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        Text(text)
            .sectionTitle()
    }
}

struct Chip<Icon: View>: View {
    let label: String
    let active: Bool
    @ViewBuilder let icon: Icon
    let action: () -> Void

    init(label: String, active: Bool, @ViewBuilder icon: () -> Icon, action: @escaping () -> Void) {
        self.label = label
        self.active = active
        self.icon = icon()
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                icon
                    .font(.system(size: 12, weight: .semibold))
                Text(label)
                    .font(DS.Font.bodyBold)
            }
            .foregroundStyle(active ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 36)
            .background(active ? DS.Color.ink : DS.Color.paper)
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .stroke(active ? DS.Color.ink : DS.Color.ink.opacity(0.18), lineWidth: 1)
            )
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous))
        }
        .buttonStyle(.plain)
    }
}

enum LineBadgeSize {
    case sm
    case lg

    var height: CGFloat {
        switch self {
        case .sm: return 24
        case .lg: return 34
        }
    }

    var horizontalPadding: CGFloat {
        switch self {
        case .sm: return 8
        case .lg: return 12
        }
    }

    var font: Font {
        switch self {
        case .sm: return DS.Font.monoSmall
        case .lg: return DS.Font.monoLarge
        }
    }
}

enum TransitLinePalette {
    static func fill(for line: String) -> Color {
        let normalized = line.uppercased()

        switch normalized {
        case "1": return Color(hex: "#B0368F")
        case "2": return Color(hex: "#F47A20")
        case "4": return Color(hex: "#E94983")
        case "5": return Color(hex: "#F7B20D")
        case "6": return Color(hex: "#0F6AAE")
        case "7": return Color(hex: "#F2E64C")
        case "8": return Color(hex: "#2D9FDE")
        case "9": return Color(hex: "#BA509D")
        case "10": return Color(hex: "#9A56A5")
        case "12": return Color(hex: "#5A9838")
        case "13": return Color(hex: "#9BC2E6")
        case "14": return Color(hex: "#E9A1C9")
        case "17": return Color(hex: "#EF4335")
        case "18": return Color(hex: "#90B7E0")
        case "19": return Color(hex: "#EF4335")
        case "20": return Color(hex: "#F4C700")
        case "21": return Color(hex: "#F1DE40")
        case "25": return Color(hex: "#B23357")
        case "28": return Color(hex: "#F34C36")
        case "29": return Color(hex: "#F48C0C")
        case "34": return Color(hex: "#F4C700")
        case "35": return Color(hex: "#4770A6")
        case "36": return Color(hex: "#9ABFE4")
        case "37": return Color(hex: "#4572A5")
        case "38": return Color(hex: "#A884BC")
        case "39": return Color(hex: "#EE4334")
        case "41": return Color(hex: "#9CC0E4")
        case "42": return Color(hex: "#5C9C40")
        case "43": return Color(hex: "#B47B20")
        case "44": return Color(hex: "#F5C500")
        case "45": return Color(hex: "#B08CC1")
        case "46": return Color(hex: "#F34939")
        case "47": return Color(hex: "#F54F3E")
        case "48": return Color(hex: "#F68A0B")
        case "49": return Color(hex: "#436D9F")
        case "50": return Color(hex: "#C0CA05")
        case "51": return Color(hex: "#F6C700")
        case "53": return Color(hex: "#5B993C")
        case "54": return Color(hex: "#F34938")
        case "55": return Color(hex: "#F6C500")
        case "56": return Color(hex: "#F78707")
        case "58": return Color(hex: "#619E44")
        case "59": return Color(hex: "#B0791C")
        case "60": return Color(hex: "#E89AC8")
        case "61": return Color(hex: "#F8D80D")
        case "62": return Color(hex: "#EAA0CA")
        case "63": return Color(hex: "#9ABFE4")
        case "64": return Color(hex: "#F24735")
        case "65": return Color(hex: "#F4C700")
        case "66": return Color(hex: "#4771A6")
        case "69": return Color(hex: "#F38908")
        case "71": return Color(hex: "#5A983A")
        case "72": return Color(hex: "#E8A1C9")
        case "73": return Color(hex: "#E9A0C9")
        case "74": return Color(hex: "#A782B9")
        case "75": return Color(hex: "#F6D503")
        case "76": return Color(hex: "#F5D200")
        case "77": return Color(hex: "#5D9A3F")
        case "78": return Color(hex: "#AB85BC")
        case "79": return Color(hex: "#4A74A7")
        case "80": return Color(hex: "#5B993C")
        case "81", "T81": return Color(hex: "#5A993B")
        case "82": return Color(hex: "#9EC2E6")
        case "83": return Color(hex: "#B7CA06")
        case "86": return Color(hex: "#456FA2")
        case "87": return Color(hex: "#5C993E")
        case "88": return Color(hex: "#B13256")
        case "89": return Color(hex: "#BCCB06")
        case "92": return Color(hex: "#F34939")
        case "93": return Color(hex: "#F48B0C")
        case "95": return Color(hex: "#4772A5")
        case "96": return Color(hex: "#B43257")
        default:
            if normalized.hasPrefix("T") {
                return DS.Color.tram
            }
            return inferredFill(for: normalized)
        }
    }

    static func foreground(for line: String) -> Color {
        let fillColor = fill(for: line)
        return fillColor.isDark ? .white : .black
    }

    private static func inferredFill(for line: String) -> Color {
        if let numeric = Int(line) {
            if (1...6).contains(numeric) { return DS.Color.metro }
            if numeric >= 90 { return DS.Color.bus }
            if numeric >= 7 { return DS.Color.tram }
        }
        return DS.Color.primary
    }
}

struct LineBadge: View {
    let line: String
    var size: LineBadgeSize = .sm
    var fill: Color? = nil
    var foreground: Color? = nil

    var body: some View {
        Text(line)
            .font(size.font)
            .fontWeight(.bold)
            .foregroundStyle(foreground ?? TransitLinePalette.foreground(for: line))
            .padding(.horizontal, size.horizontalPadding)
            .frame(minWidth: size.height, minHeight: size.height)
            .background(fill ?? TransitLinePalette.fill(for: line))
            .clipShape(RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.md, style: .continuous)
                    .stroke(DS.Color.ink.opacity(0.12), lineWidth: 1)
            )
    }
}

struct StatusDot: View {
    let level: DS.StatusLevel
    var size: CGFloat = 8

    var body: some View {
        Circle()
            .fill(level.color)
            .frame(width: size, height: size)
    }
}

struct PaperGrainBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .background(
                DS.Color.background
                    .overlay(
                        Canvas { ctx, size in
                            let dot = Path(ellipseIn: CGRect(x: 0, y: 0, width: 1, height: 1))
                            let color = GraphicsContext.Shading.color(DS.Color.ink.opacity(0.02))
                            var y: CGFloat = 0
                            while y < size.height {
                                var x: CGFloat = 0
                                while x < size.width {
                                    ctx.fill(dot.applying(CGAffineTransform(translationX: x, y: y)), with: color)
                                    x += 3
                                }
                                y += 3
                            }
                        }
                        .allowsHitTesting(false)
                    )
            )
    }
}

struct PressableScaleStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}

struct PressableRowStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .background(configuration.isPressed ? DS.Color.paper2 : Color.clear)
            .animation(.easeOut(duration: 0.1), value: configuration.isPressed)
    }
}
