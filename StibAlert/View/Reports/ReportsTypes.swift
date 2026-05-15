import SwiftUI

enum ReportSegment: String, CaseIterable, Identifiable {
    case all, official, community, events
    var id: String { rawValue }
    var label: String {
        switch self {
        case .all: return "Tout"
        case .official: return "Officiel"
        case .community: return "Communauté"
        case .events: return "Événements"
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
    case all, metro, tram, bus

    var id: String { rawValue }

    var label: String {
        switch self {
        case .all: return "Tous modes"
        case .metro: return "Métro"
        case .tram: return "Tram"
        case .bus: return "Bus"
        }
    }

    var iconSystemName: String? {
        switch self {
        case .all: return nil
        case .metro: return "m.circle.fill"
        case .tram: return "tram.fill"
        case .bus: return "bus.fill"
        }
    }
}

enum ReportSortMode: String, CaseIterable, Identifiable {
    case recent, urgent, personal

    var id: String { rawValue }

    var label: String {
        switch self {
        case .recent: return "Plus récents"
        case .urgent: return "Plus urgents"
        case .personal: return "Mes lignes"
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
