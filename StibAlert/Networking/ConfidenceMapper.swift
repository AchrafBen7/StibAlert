import Foundation
import SwiftUI

enum UnifiedConfidence: String, Codable {
    case low
    case medium
    case high

    var displayLabel: String {
        switch self {
        case .high: return "Élevée"
        case .medium: return "Moyenne"
        case .low: return "Basse"
        }
    }

    var shortLabel: String {
        switch self {
        case .high: return "HAUTE"
        case .medium: return "MOY."
        case .low: return "BASSE"
        }
    }

    var color: Color {
        switch self {
        case .high: return Color(hex: "#E94E1B")
        case .medium: return Color(hex: "#F59E0B")
        case .low: return Color(hex: "#9CA3AF")
        }
    }

    var iconName: String {
        switch self {
        case .high: return "checkmark.shield.fill"
        case .medium: return "exclamationmark.shield"
        case .low: return "questionmark.diamond"
        }
    }

    static func from(legacyString value: String?) -> UnifiedConfidence {
        guard let v = value?.lowercased() else { return .low }
        switch v {
        case "haute", "high": return .high
        case "moyenne", "medium": return .medium
        case "basse", "low": return .low
        default: return .low
        }
    }

    static func from(numericScore score: Double?) -> UnifiedConfidence {
        guard let s = score else { return .low }
        if s >= 70 { return .high }
        if s >= 50 { return .medium }
        return .low
    }

    static func from(reportCount: Int, aggregateTrust: Double) -> UnifiedConfidence {
        if reportCount >= 5 && aggregateTrust >= 70 { return .high }
        if reportCount >= 4 && aggregateTrust >= 60 { return .high }
        if reportCount >= 3 && aggregateTrust >= 50 { return .medium }
        return .low
    }
}

extension ClusterConfidence {
    var unified: UnifiedConfidence {
        switch self {
        case .low: return .low
        case .medium: return .medium
        case .high: return .high
        }
    }
}
