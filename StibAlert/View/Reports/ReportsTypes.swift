import SwiftUI

enum ReportSegment: String, CaseIterable, Identifiable {
    case all, official, community, events
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return AppLocalizer.string("scope.all", defaultValue: "Tout")
        case .official: return AppLocalizer.string("source.official", defaultValue: "Officiel")
        case .community: return AppLocalizer.string("source.community", defaultValue: "Communauté")
        case .events: return AppLocalizer.string("scope.events", defaultValue: "Événements")
        }
    }
    var iconSystemName: String? {
        switch self {
        case .all: return nil
        case .official: return "shield.fill"
        case .community: return "person.2.fill"
        case .events: return "ticket.fill"
        }
    }
}

enum EditorialFeedItemType {
    case official, community, mixed, event
}

enum ReportTransportMode: String, CaseIterable, Identifiable {
    case all, metro, tram, bus, sncb

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return AppLocalizer.string("mode.all", defaultValue: "Tous modes")
        case .metro: return AppLocalizer.string("mode.metro", defaultValue: "Métro")
        case .tram: return AppLocalizer.string("mode.tram", defaultValue: "Tram")
        case .bus: return AppLocalizer.string("mode.bus", defaultValue: "Bus")
        case .sncb: return "SNCB"   // i18n:ignore — nom d'opérateur
        }
    }

    var iconSystemName: String? {
        switch self {
        case .all: return nil
        case .metro: return "m.circle.fill"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        case .sncb: return "train.side.front.car"
        }
    }
}

enum ReportSortMode: String, CaseIterable, Identifiable {
    case recent, urgent, personal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return AppLocalizer.string("sort.recent", defaultValue: "Plus récents")
        case .urgent: return AppLocalizer.string("sort.urgent", defaultValue: "Plus urgents")
        case .personal: return AppLocalizer.string("sort.personal", defaultValue: "Mes lignes")
        }
    }
}

struct EditorialNowItem: Identifiable {
    let id: String
    let line: String
    let reason: String
}

struct NetworkIssueCarouselItem: Identifiable {
    let id: String
    let keyword: String
    let detail: String
    let lines: [String]
    let location: String?
    let sourceLabel: String
    let tint: Color
}

struct EditorialFeedItem: Identifiable {
    let id: String
    let type: EditorialFeedItemType
    let title: String
    let body: String?
    let timeLabel: String
    let lines: [String]
    let location: String?
    let upvotes: Int?
    let url: URL?
    let attendance: Int?
    let venueCapacity: Int?
    let report: SignalementDTO?
    let event: TransportEventImpactDTO?
}

struct EditorialLineGroup: Identifiable {
    let id: String
    let line: String
    let items: [EditorialFeedItem]
}

/// Wrapper that bundles every line-group of the same transit mode together,
/// so the reports feed can render distinct MÉTRO / TRAM / BUS sections
/// instead of a single mixed list. Lines without an identifiable mode fall
/// into the bus bucket as a sensible default for STIB.
struct EditorialModeSection: Identifiable {
    let id: TransitLineMode
    let mode: TransitLineMode
    let groups: [EditorialLineGroup]
}
