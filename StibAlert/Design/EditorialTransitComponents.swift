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

struct LineBadge: View {
    let line: String
    var size: LineBadgeSize = .sm
    var fill: Color = DS.Color.primary
    var foreground: Color = DS.Color.primaryForeground

    var body: some View {
        Text(line)
            .font(size.font)
            .fontWeight(.bold)
            .foregroundStyle(foreground)
            .padding(.horizontal, size.horizontalPadding)
            .frame(minWidth: size.height, minHeight: size.height)
            .background(fill)
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
