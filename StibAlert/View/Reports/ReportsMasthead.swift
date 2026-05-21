import SwiftUI

enum ReportContentScope: String, CaseIterable, Identifiable {
    case reports     // "En cours" — community reports + active live incidents
    case official    // "Officiel" — scheduled / upcoming STIB official disruptions
    case events      // "Events" — Brussels-wide events impacting transit

    var id: String { rawValue }

    var title: String {
        switch self {
        case .reports: return "En cours"
        case .official: return "Officiel"
        case .events: return "Events"
        }
    }

    var switchLabel: String {
        switch self {
        case .reports: return "En cours"
        case .official: return "Officiel"
        case .events: return "Events"
        }
    }

    var icon: String {
        switch self {
        case .reports: return "dot.radiowaves.left.and.right"
        case .official: return "checkmark.seal.fill"
        case .events: return "calendar"
        }
    }
}

struct ReportsMasthead: View {
    @Binding var selectedScope: ReportContentScope
    let onScopeChange: (ReportContentScope) -> Void

    var body: some View {
        // Compact centered title — matches the smaller header style the
        // user wants across the Horaires / Favoris / Infos trafic tabs.
        // Dropped the Dela Gothic display font + eyebrow that were too
        // dominant on a content-dense page.
        Text("Infos trafic")
            .font(.system(size: 22, weight: .bold))
            .foregroundStyle(DS.Color.ink)
            .frame(maxWidth: .infinity)
    }
}
