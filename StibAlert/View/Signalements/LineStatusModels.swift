import SwiftUI

/// Modèles de statut de ligne, extraits de l'ancien écran `SignalementsView`
/// (supprimé : l'onglet Lignes utilise `SchedulesView`). Seuls les types encore
/// consommés par `LigneDetailPage` sont conservés — `LineOverviewStop`,
/// `LineConnectionBadge` et `LineStatusMockData` n'étaient référencés nulle part.

enum LineFilter: CaseIterable, Identifiable {
    case all
    case tram
    case bus
    case metro

    var id: Self { self }

    var label: String {
        switch self {
        case .all: return AppLocalizer.string("filter.all", defaultValue: "Toutes")
        case .tram: return AppLocalizer.string("mode.tram", defaultValue: "Tram")
        case .bus: return AppLocalizer.string("mode.bus", defaultValue: "Bus")
        case .metro: return AppLocalizer.string("mode.metro", defaultValue: "Métro")
        }
    }

    /// Affiché dans le placeholder « Chercher dans … » → traduit.
    var searchLabel: String {
        switch self {
        case .all: return AppLocalizer.string("filter.search.network", defaultValue: "le réseau")
        case .tram: return AppLocalizer.string("mode.tram", defaultValue: "Tram")
        case .bus: return AppLocalizer.string("mode.bus", defaultValue: "Bus")
        case .metro: return AppLocalizer.string("mode.metro", defaultValue: "Métro")
        }
    }

    var iconName: String {
        switch self {
        case .all: return "square.grid.2x2"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .metro: return "tram.fill.tunnel"
        }
    }

    var modeAccent: Color {
        switch self {
        case .all: return DS.Color.ink
        case .metro: return DS.Color.metro
        case .tram: return DS.Color.tram
        case .bus: return DS.Color.bus
        }
    }

    static func from(line: String) -> LineFilter {
        if ["1", "2", "5", "6"].contains(line) { return .metro }
        if let numeric = Int(line), numeric >= 90 { return .bus }
        return .tram
    }

    static func from(typeTransport: String?) -> LineFilter {
        switch typeTransport?.lowercased() {
        case "métro", "metro": return .metro
        case "tram": return .tram
        case "bus": return .bus
        default: return .all
        }
    }
}

enum LineHealthStatus {
    case fluid
    case disrupted
    case critical

    var label: String {
        switch self {
        case .fluid: return AppLocalizer.string("status.fluid", defaultValue: "Fluide")
        case .disrupted: return AppLocalizer.string("status.disrupted", defaultValue: "Perturbé")
        case .critical: return AppLocalizer.string("status.critical", defaultValue: "Critique")
        }
    }
}

struct LineStatusItem: Identifiable {
    let id = UUID()
    let line: String
    let lineColor: Color
    let lineTextColor: Color
    let origin: String
    let destination: String
    let direction: String
    let status: LineHealthStatus
    let reportsCount: Int
    let filter: LineFilter
    let confidenceText: String?
}

