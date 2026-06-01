import SwiftUI

public enum DS {}

public extension DS {
    enum Color {
        public static let background = hsl(38, 24, 93, dark: hsl(0, 0, 7))
        public static let paper = hsl(36, 28, 95, dark: hsl(0, 0, 10))
        public static let paper2 = hsl(36, 18, 88, dark: hsl(0, 0, 14))
        public static let card = paper
        public static let popover = paper
        public static let sheet = paper

        public static let foreground = hsl(0, 0, 6, dark: hsl(38, 24, 92))
        public static let ink = foreground
        public static let inkSoft = hsl(0, 0, 22, dark: hsl(36, 14, 78))
        public static let inkMute = hsl(30, 6, 42, dark: hsl(30, 6, 58))
        public static let mutedForeground = inkMute
        public static let border = hsl(30, 8, 78, dark: hsl(0, 0, 24))
        public static let input = border

        public static let primary = hsl(14, 82, 51, dark: hsl(14, 88, 56))
        public static let primaryForeground = hsl(0, 0, 100)
        public static let primaryGlow = hsl(14, 88, 60)
        public static let ring = primary

        public static let accent = hsl(220, 56, 23)
        public static let accentForeground = hsl(0, 0, 100)

        // Identité STIB·AI : encre (noir éditorial) plutôt que le bleu marine
        // `accent` qui jurait avec la palette orange/papier de l'app. Couleur
        // dédiée pour rester cohérent partout où l'assistant apparaît.
        public static let ai = foreground
        public static let aiForeground = hsl(0, 0, 100, dark: hsl(0, 0, 8))
        public static let secondary = hsl(36, 18, 88, dark: hsl(0, 0, 14))
        public static let secondaryForeground = hsl(0, 0, 6, dark: hsl(38, 24, 92))
        public static let muted = secondary
        public static let destructive = hsl(4, 72, 48)
        public static let destructiveForeground = hsl(0, 0, 100)

        public static let metro = hsl(14, 82, 51)
        public static let tram = hsl(44, 95, 50)
        public static let bus = hsl(220, 56, 23)
        public static let noctis = hsl(268, 50, 38)
        public static let villo = hsl(152, 60, 30)
        public static let event = hsl(280, 70, 42)
        public static let community = hsl(192, 70, 38)

        public static let statusOK = hsl(152, 60, 32)
        public static let statusMinor = hsl(38, 92, 45)
        public static let statusMajor = hsl(14, 84, 48)
        public static let statusCritical = hsl(350, 75, 38)

        // Semantic aliases — use these in non-status contexts (CTAs, badges, banners)
        // so the intent is obvious at the call site. They share the underlying HSL with
        // statusXxx so a future palette tweak stays in one place.
        public static let success = statusOK
        public static let warning = statusMinor
        public static let danger = statusMajor
        public static let info = hsl(220, 88, 55, dark: hsl(220, 88, 68))

        public static func hsl(_ h: Double, _ s: Double, _ l: Double, alpha: Double = 1.0, dark: SwiftUI.Color? = nil) -> SwiftUI.Color {
            let light = SwiftUI.Color(hsl: (h, s, l), alpha: alpha)
            guard let dark else { return light }
            #if canImport(UIKit)
            return SwiftUI.Color(UIColor { trait in
                trait.userInterfaceStyle == .dark ? UIColor(dark) : UIColor(light)
            })
            #else
            return light
            #endif
        }
    }
}

public extension SwiftUI.Color {
    init(hsl: (h: Double, s: Double, l: Double), alpha: Double = 1.0) {
        let h = hsl.h / 360.0
        let s = hsl.s / 100.0
        let l = hsl.l / 100.0

        func hue2rgb(_ p: Double, _ q: Double, _ tIn: Double) -> Double {
            var t = tIn
            if t < 0 { t += 1 }
            if t > 1 { t -= 1 }
            if t < 1.0 / 6.0 { return p + (q - p) * 6 * t }
            if t < 1.0 / 2.0 { return q }
            if t < 2.0 / 3.0 { return p + (q - p) * (2.0 / 3.0 - t) * 6 }
            return p
        }

        let r, g, b: Double
        if s == 0 {
            r = l; g = l; b = l
        } else {
            let q = l < 0.5 ? l * (1 + s) : l + s - l * s
            let p = 2 * l - q
            r = hue2rgb(p, q, h + 1.0 / 3.0)
            g = hue2rgb(p, q, h)
            b = hue2rgb(p, q, h - 1.0 / 3.0)
        }
        self = SwiftUI.Color(.sRGB, red: r, green: g, blue: b, opacity: alpha)
    }
}

public extension DS {
    enum Font {
        // DelaGothicOne for editorial hero — scales with Dynamic Type via relativeTo.
        // Sizes tuned down from 32/22 → 24/18: at the original sizes Dela
        // Gothic (a dense blocky display face) dominated content-rich
        // screens like Profil / Décision / la fiche d'arrêt. Keeping the
        // typography identity but giving the rest of the page room to breathe.
        public static let displayH1: SwiftUI.Font = .custom("DelaGothicOne-Regular", size: 24, relativeTo: .largeTitle)
        public static let displayH2: SwiftUI.Font = .custom("DelaGothicOne-Regular", size: 18, relativeTo: .title2)

        // System fonts using Apple's TextStyle scale — full Dynamic Type support.
        public static let displayH3: SwiftUI.Font = .system(.headline)
        public static let body: SwiftUI.Font = .system(.subheadline)
        public static let bodyBold: SwiftUI.Font = .system(.subheadline).weight(.semibold)
        public static let bodySmall: SwiftUI.Font = .system(.footnote)
        public static let caption: SwiftUI.Font = .system(.caption)
        public static let eyebrow: SwiftUI.Font = .system(.caption2).weight(.semibold)
        public static let sectionTitle: SwiftUI.Font = .system(.caption2).weight(.bold)
        public static let mono: SwiftUI.Font = .system(.caption, design: .monospaced)
        public static let monoSmall: SwiftUI.Font = .system(.caption2, design: .monospaced)
        public static let monoLarge: SwiftUI.Font = .system(.subheadline, design: .monospaced).weight(.semibold)
    }

    enum Radius {
        public static let sm: CGFloat = 4
        public static let md: CGFloat = 6
        public static let lg: CGFloat = 8
        public static let pill: CGFloat = 999
    }

    enum Spacing {
        public static let xxs: CGFloat = 2
        public static let xs: CGFloat = 4
        public static let sm: CGFloat = 8
        public static let md: CGFloat = 12
        public static let lg: CGFloat = 16
        public static let xl: CGFloat = 20
        public static let xxl: CGFloat = 24
        public static let xxxl: CGFloat = 32
    }

    enum Stroke {
        public static let hairline: CGFloat = 1
        public static let thick: CGFloat = 1.5
    }

    struct ShadowStyle {
        public let color: SwiftUI.Color
        public let radius: CGFloat
        public let x: CGFloat
        public let y: CGFloat
    }

    enum Shadow {
        public static let raised = ShadowStyle(color: SwiftUI.Color.black.opacity(0.06), radius: 0, x: 0, y: 1)
        public static let floating = ShadowStyle(color: DS.Color.hsl(30, 30, 15, alpha: 0.18), radius: 24, x: 0, y: 8)
        public static let overlay = ShadowStyle(color: DS.Color.hsl(30, 30, 15, alpha: 0.28), radius: 60, x: 0, y: 24)
    }

    enum Motion {
        public static let easeIOS = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.32)
        public static let fadeIn = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.28)
        public static let slideUp = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.42)
        public static let popIn = Animation.timingCurve(0.32, 0.72, 0, 1, duration: 0.32)
        public static let tapScale: CGFloat = 0.98
        public static let iconTapScale: CGFloat = 0.95
    }
}

public extension View {
    func eyebrow() -> some View {
        font(DS.Font.eyebrow)
            .tracking(1.4)
            .textCase(.uppercase)
            .foregroundColor(DS.Color.inkMute)
    }

    func sectionTitle() -> some View {
        font(DS.Font.sectionTitle)
            .tracking(2.0)
            .textCase(.uppercase)
            .foregroundColor(DS.Color.ink)
    }

    func displayH1() -> some View {
        font(DS.Font.displayH1)
            .tracking(-0.96)
            .foregroundColor(DS.Color.ink)
    }

    func displayH2() -> some View {
        font(DS.Font.displayH2)
            .tracking(-0.55)
            .foregroundColor(DS.Color.ink)
    }

    func tabular() -> some View {
        font(DS.Font.mono)
            .monospacedDigit()
    }

    func shadow(_ style: DS.ShadowStyle) -> some View {
        shadow(color: style.color, radius: style.radius, x: style.x, y: style.y)
    }
}

public extension DS {
    struct PrimaryButtonStyle: ButtonStyle {
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 14, weight: .bold))
                .foregroundColor(DS.Color.primaryForeground)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(DS.Color.primary)
                .cornerRadius(DS.Radius.md)
                .shadow(DS.Shadow.floating)
                .scaleEffect(configuration.isPressed ? DS.Motion.tapScale : 1)
                .animation(DS.Motion.easeIOS, value: configuration.isPressed)
        }
    }

    struct SecondaryButtonStyle: ButtonStyle {
        public init() {}
        public func makeBody(configuration: Configuration) -> some View {
            configuration.label
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(DS.Color.ink)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(DS.Color.secondary)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.md)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: DS.Stroke.hairline)
                )
                .cornerRadius(DS.Radius.md)
                .scaleEffect(configuration.isPressed ? DS.Motion.tapScale : 1)
                .animation(DS.Motion.easeIOS, value: configuration.isPressed)
        }
    }

    struct PaperCard<Content: View>: View {
        let content: () -> Content
        public init(@ViewBuilder content: @escaping () -> Content) {
            self.content = content
        }

        public var body: some View {
            content()
                .padding(DS.Spacing.lg)
                .background(DS.Color.paper)
                .overlay(
                    RoundedRectangle(cornerRadius: DS.Radius.lg)
                        .stroke(DS.Color.ink.opacity(0.15), lineWidth: DS.Stroke.hairline)
                )
                .cornerRadius(DS.Radius.lg)
                .shadow(DS.Shadow.raised)
        }
    }

    enum StatusLevel {
        case ok, minor, major, critical

        var color: SwiftUI.Color {
            switch self {
            case .ok: return DS.Color.statusOK
            case .minor: return DS.Color.statusMinor
            case .major: return DS.Color.statusMajor
            case .critical: return DS.Color.statusCritical
            }
        }
    }

    struct StatusPill: View {
        public let label: String
        public let level: StatusLevel
        public init(_ label: String, level: StatusLevel) {
            self.label = label
            self.level = level
        }

        public var body: some View {
            HStack(spacing: 6) {
                Circle()
                    .fill(level.color)
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .bold, design: .monospaced))
                    .tracking(1.0)
                    .textCase(.uppercase)
                    .foregroundColor(level.color)
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(level.color.opacity(0.10))
            .overlay(Capsule().stroke(level.color.opacity(0.40), lineWidth: DS.Stroke.thick))
            .clipShape(Capsule())
        }
    }

    struct Rule: View {
        public var thick: Bool = false
        public init(thick: Bool = false) {
            self.thick = thick
        }

        public var body: some View {
            Rectangle()
                .fill(DS.Color.ink.opacity(thick ? 0.20 : 0.10))
                .frame(height: thick ? 1 : 0.5)
        }
    }

    struct SheetHandle: View {
        public init() {}
        public var body: some View {
            Capsule()
                .fill(DS.Color.ink.opacity(0.5))
                .frame(width: 36, height: 4)
                .padding(.top, 8)
                .padding(.bottom, 4)
        }
    }
}
