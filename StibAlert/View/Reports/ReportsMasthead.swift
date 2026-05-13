import SwiftUI

enum ReportContentScope: String, CaseIterable, Identifiable {
    case reports
    case events

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reports: return "Reports"
        case .events: return "Événements"
        }
    }

    var switchLabel: String {
        switch self {
        case .reports: return "Réseau & signalements"
        case .events: return "Événements"
        }
    }
}

struct ReportsMasthead: View {
    @Binding var selectedScope: ReportContentScope
    let onScopeChange: (ReportContentScope) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("Reports")
                    .font(.system(size: 32, weight: .bold))
                    .tracking(-1)
                    .foregroundStyle(DS.Color.ink)
                Spacer()
            }

            scopeSwitch
                .padding(.top, 12)
        }
    }

    private var scopeSwitch: some View {
        HStack(spacing: 8) {
            ForEach(ReportContentScope.allCases) { scope in
                Button {
                    onScopeChange(scope)
                } label: {
                    Text(scope.switchLabel)
                        .font(DS.Font.monoSmall.weight(.bold))
                        .tracking(1.2)
                        .foregroundStyle(selectedScope == scope ? DS.Color.paper : DS.Color.ink)
                        .padding(.horizontal, 12)
                        .frame(height: 34)
                        .background(selectedScope == scope ? DS.Color.ink : DS.Color.paper)
                        .overlay(
                            Capsule()
                                .stroke(DS.Color.ink.opacity(0.14), lineWidth: 1)
                        )
                        .clipShape(Capsule())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
