import SwiftUI
import UIKit

struct HomeMapFilterBar: View {
    @Binding var selected: ReportProblemType?
    @Binding var showVillo: Bool
    @Binding var showEvents: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                chip(
                    title: "Tout",
                    icon: "dot.radiowaves.left.and.right",
                    accent: DS.Color.primary,
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

                chip(
                    title: "Villo!",
                    icon: "bicycle",
                    accent: DS.Color.villo,
                    isActive: showVillo
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        showVillo.toggle()
                    }
                }

                chip(
                    title: "Événements",
                    icon: "calendar.badge.exclamationmark",
                    accent: DS.Color.event,
                    isActive: showEvents
                ) {
                    UIImpactFeedbackGenerator(style: .light).impactOccurred()
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.82)) {
                        showEvents.toggle()
                    }
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 2)
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
            HStack(spacing: 5) {
                Image(systemName: icon)
                    .font(.system(size: 10, weight: .semibold))
                Text(title)
                    .font(DS.Font.caption)
                    .tracking(0.8)
            }
            .foregroundStyle(isActive ? DS.Color.paper : DS.Color.ink)
            .padding(.horizontal, 12)
            .frame(height: 34)
            .background(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .fill(isActive ? accent : DS.Color.paper.opacity(0.94))
            )
            .overlay(
                RoundedRectangle(cornerRadius: DS.Radius.pill, style: .continuous)
                    .stroke(isActive ? accent.opacity(0.85) : DS.Color.ink.opacity(0.18), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .shadow(DS.Shadow.raised)
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
