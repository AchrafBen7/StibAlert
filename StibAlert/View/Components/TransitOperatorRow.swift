import SwiftUI

enum TransitOperator: String, CaseIterable, Identifiable {
    case stib
    case delijn
    case sncb
    case tec

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .stib:   return "STIB·MIVB"
        case .delijn: return "De Lijn"
        case .sncb:   return "SNCB"
        case .tec:    return "TEC"
        }
    }

    /// Asset Catalog name for the operator's actual brand logo.
    var assetName: String {
        switch self {
        case .stib:   return "operator-stib"
        case .delijn: return "operator-delijn"
        case .sncb:   return "operator-sncb"
        case .tec:    return "operator-tec"
        }
    }

    var accessibilityLabel: String {
        switch self {
        case .stib:   return "STIB-MIVB"
        case .delijn: return "De Lijn"
        case .sncb:   return "SNCB-NMBS"
        case .tec:    return "TEC"
        }
    }

    var mapLabel: String {
        switch self {
        case .stib: return "STIB"
        case .delijn: return "De Lijn"
        case .sncb: return "SNCB"
        case .tec: return "TEC"
        }
    }
}

/// Reusable row of Belgian transit operator logos. STIB and SNCB are wired
/// today; De Lijn / TEC stay visible but disabled until their local datasets
/// land.
struct TransitOperatorRow: View {
    var activeOperator: TransitOperator = .stib
    var enabledOperators: Set<TransitOperator> = [.stib, .sncb]
    var onSelect: ((TransitOperator) -> Void)? = nil

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TransitOperator.allCases) { op in
                tile(op)
            }
        }
    }

    private func tile(_ op: TransitOperator) -> some View {
        let isActive = op == activeOperator
        let isEnabled = enabledOperators.contains(op)

        return Button {
            guard isEnabled else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            onSelect?(op)
        } label: {
            VStack(spacing: 4) {
                Image(op.assetName)
                    .renderingMode(.original)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 28, height: 28)
                    .frame(width: 44, height: 44)
                    .background(
                        Circle()
                            .fill(isActive ? DS.Color.ink.opacity(0.06) : DS.Color.paper.opacity(0.95))
                    )
                    .overlay(
                        Circle()
                            .stroke(DS.Color.ink.opacity(isActive ? 0.30 : 0.08), lineWidth: isActive ? 1.5 : 1)
                    )
                    .saturation(isEnabled ? 1 : 0)
                    .opacity(isEnabled ? 1 : 0.42)
                Text(op.shortName)
                    .font(.system(size: 9, weight: .bold))
                    .tracking(0.5)
                    .foregroundStyle(isActive ? DS.Color.ink : DS.Color.inkMute)
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .disabled(!isEnabled)
        .accessibilityLabel(op.accessibilityLabel + (isEnabled ? "" : " (bientôt)"))
    }
}
