import SwiftUI
import UIKit

struct HomeMapFilterBar: View {
    @Binding var selected: ReportProblemType?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    title: "Tout",
                    icon: "dot.radiowaves.left.and.right",
                    accent: AppTheme.Palette.brand,
                    isActive: selected == nil
                ) {
                    tap(nil)
                }

                ForEach(ReportProblemType.allCases) { type in
                    chip(
                        title: type.title,
                        icon: icon(for: type),
                        accent: type.accentColor,
                        isActive: selected == type
                    ) {
                        tap(type)
                    }
                }
            }
            .padding(.horizontal, 18)
        }
    }

    private func tap(_ type: ReportProblemType?) {
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
            selected = type
        }
    }

    private func chip(
        title: String,
        icon: String,
        accent: Color,
        isActive: Bool,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.system(size: 11, weight: .semibold))
                Text(title)
                    .font(AppTheme.Fonts.captionStrong)
            }
            .foregroundStyle(isActive ? AppTheme.Palette.textOnBrand : AppTheme.Palette.textPrimary)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                Capsule(style: .continuous)
                    .fill(isActive ? accent : AppTheme.Palette.screenElevated.opacity(0.9))
            )
            .overlay(
                Capsule(style: .continuous)
                    .stroke(isActive ? accent : AppTheme.Palette.border, lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
    }

    private func icon(for type: ReportProblemType) -> String {
        switch type {
        case .accident: return "car.fill"
        case .delay: return "clock.fill"
        case .breakdown: return "wrench.adjustable.fill"
        case .incivility: return "person.fill.questionmark"
        case .cleanliness: return "trash.fill"
        case .aggression: return "exclamationmark.shield.fill"
        }
    }
}
