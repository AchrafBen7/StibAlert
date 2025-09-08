//
//  SignalementStyledCard.swift
//  StibAlert
//
//  Created by studentehb on 23/05/2025.
//
import SwiftUI

struct SignalementStyledCard: View {
    let melding: ArretSignalementItem
    let typeTransport: String?

    var probleemType: ProbleemType? {
        ProbleemType(rawValue: melding.typeProbleme)
    }

    var body: some View {
        if let date = parseDate(melding.date), Date().timeIntervalSince(date) <= 24 * 60 * 60 {
            HStack(alignment: .top, spacing: 12) {
                // Ligne badge
                Text(melding.ligne)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .padding(10)
                    .background(LineColors.color(for: melding.ligne))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 6) {
               
                    HStack(spacing: 6) {
                        

                        Text(melding.typeProbleme.capitalized)
                            .font(.headline)
                            .fontWeight(.semibold)

                        Spacer()

                
                        Text(heureDe(date))
                            .font(.caption)
                            .foregroundColor(.gray)
                    }

               
                    HStack(spacing: 6) {
                       

             
                        Text(" · \(melding.description.prefix(50))…")
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .lineLimit(1)
                    }


                }

            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            .background(Color(.systemBackground))
            .opacity(signalementOpacity(date))
        }
    }

    // MARK: - Helpers

    func parseDate(_ isoString: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.date(from: isoString)
    }

    func signalementOpacity(_ date: Date) -> Double {
        let interval = Date().timeIntervalSince(date)
        if interval > 24 * 60 * 60 {
            return 0.0
        } else if interval > 6 * 60 * 60 {
            return 0.4
        } else {
            return 1.0
        }
    }

    func tempsDepuis(_ date: Date) -> String {
        let interval = Date().timeIntervalSince(date)
        let minutes = Int(interval / 60)
        let hours = Int(interval / 3600)

        if hours >= 24 { return "" }
        if minutes < 1 { return "zojuist" }
        if minutes < 60 { return "\(minutes) min" }
        return "\(hours)h"
    }

    func heureDe(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH'h'mm" 
        return formatter.string(from: date)
    }

    func typeTransport(from raw: String?) -> String {
        switch raw?.lowercased() {
        case "tram": return "Tram"
        case "bus": return "Bus"
        case "metro": return "Métro"
        default: return "Transport"
        }
    }
    func abbrForTransport(_ raw: String?) -> String {
        switch raw?.lowercased() {
        case "tram": return "T"
        case "bus": return "B"
        case "metro": return "M"
        default: return "?"
        }
    }


}
