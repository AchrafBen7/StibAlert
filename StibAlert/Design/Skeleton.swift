import SwiftUI

private struct ShimmerModifier: ViewModifier {
    @State private var phase: CGFloat = -1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(
                GeometryReader { geo in
                    LinearGradient(
                        colors: [
                            .clear,
                            DS.Color.paper.opacity(0.55),
                            .clear
                        ],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: geo.size.width * 1.6)
                    .offset(x: geo.size.width * phase)
                    .blendMode(.plusLighter)
                }
                .allowsHitTesting(false)
            )
            .mask(content)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(.linear(duration: 1.2).repeatForever(autoreverses: false)) {
                    phase = 1.4
                }
            }
    }
}

extension View {
    func shimmering() -> some View {
        modifier(ShimmerModifier())
    }
}

struct SkeletonBlock: View {
    var width: CGFloat? = nil
    var height: CGFloat = 12
    var cornerRadius: CGFloat = 6

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .fill(DS.Color.paper2)
            .frame(width: width, height: height)
    }
}

struct SkeletonCard: View {
    var height: CGFloat = 84

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            SkeletonBlock(width: 44, height: 44, cornerRadius: 10)

            VStack(alignment: .leading, spacing: 8) {
                SkeletonBlock(width: 160, height: 13)
                SkeletonBlock(height: 11)
                SkeletonBlock(width: 90, height: 11)
            }

            Spacer(minLength: 0)
        }
        .padding(14)
        .frame(maxWidth: .infinity, minHeight: height, alignment: .topLeading)
        .background(DS.Color.paper)
        .overlay(
            RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous)
                .stroke(DS.Color.ink.opacity(0.06), lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: DS.Radius.lg, style: .continuous))
        .shimmering()
    }
}

struct SkeletonRow: View {
    var body: some View {
        HStack(spacing: 12) {
            SkeletonBlock(width: 36, height: 36, cornerRadius: 8)
            VStack(alignment: .leading, spacing: 6) {
                SkeletonBlock(width: 140, height: 12)
                SkeletonBlock(width: 80, height: 10)
            }
            Spacer(minLength: 0)
            SkeletonBlock(width: 40, height: 12)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 14)
        .shimmering()
    }
}

struct SkeletonList: View {
    var count: Int = 4
    var rowSpacing: CGFloat = 12
    var style: Style = .card

    enum Style {
        case card, row
    }

    var body: some View {
        VStack(spacing: rowSpacing) {
            ForEach(0..<count, id: \.self) { _ in
                switch style {
                case .card: SkeletonCard()
                case .row: SkeletonRow()
                }
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Chargement en cours")
    }
}
