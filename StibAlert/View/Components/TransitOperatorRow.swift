import SwiftUI

/// The four major Belgian transit operators. STIB-MIVB is the only one
/// wired into the backend today; the rest are placeholders shown desaturated
/// to communicate the multi-operator roadmap.
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
}

/// Reusable row of the 4 Belgian transit operator logos. Used as the
/// masthead of both the Infos trafic and the Horaires tabs to communicate
/// the multi-operator scope (only STIB is wired today; the rest are
/// desaturated placeholders).
struct TransitOperatorRow: View {
    /// Which operator is currently active / wired. Today this is hard-coded
    /// to `.stib` but stays parameterised so we can flip the others on as
    /// their backend integrations land.
    var activeOperator: TransitOperator = .stib

    var body: some View {
        HStack(spacing: 10) {
            ForEach(TransitOperator.allCases) { op in
                tile(op)
            }
        }
    }

    private func tile(_ op: TransitOperator) -> some View {
        let isActive = op == activeOperator
        return VStack(spacing: 4) {
            Image(op.assetName)
                .renderingMode(.original)
                .resizable()
                .scaledToFit()
                .frame(width: 28, height: 28)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(DS.Color.paper.opacity(0.95))
                )
                .overlay(
                    Circle()
                        .stroke(DS.Color.ink.opacity(isActive ? 0.18 : 0.08), lineWidth: 1)
                )
                // Grey-out non-active operators so users immediately read
                // them as "not wired yet" without losing the brand cue.
                .saturation(isActive ? 1 : 0)
                .opacity(isActive ? 1 : 0.45)
            Text(op.shortName)
                .font(.system(size: 9, weight: .bold))
                .tracking(0.5)
                .foregroundStyle(isActive ? DS.Color.ink : DS.Color.inkMute)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
        .accessibilityLabel(op.accessibilityLabel + (isActive ? "" : " (bientôt)"))
    }
}
