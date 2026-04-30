import SwiftUI
import DotLottie

struct StibiMascotView: View {
    let visualState: String

    var body: some View {
        DotLottieAnimation(
            fileName: "stibi-mascot",
            config: AnimationConfig(
                autoplay: true,
                loop: true,
                speed: Float(speed(for: visualState))
            )
        )
        .view()
        .scaleEffect(scale(for: visualState))
        .frame(width: size(for: visualState), height: size(for: visualState))
        .allowsHitTesting(false)
    }

    private func speed(for visualState: String) -> Double {
        switch visualState {
        case "alert": return 1.15
        case "guiding": return 1.0
        case "speaking": return 1.2
        case "watching": return 0.95
        default: return 0.85
        }
    }

    private func size(for visualState: String) -> CGFloat {
        switch visualState {
        case "speaking": return 62
        case "alert": return 66
        default: return 58
        }
    }

    private func scale(for visualState: String) -> CGFloat {
        switch visualState {
        case "speaking": return 1.24
        case "alert": return 1.28
        default: return 1.18
        }
    }
}
