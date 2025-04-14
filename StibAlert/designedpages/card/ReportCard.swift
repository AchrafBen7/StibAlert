//
//  ReportCard.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct ReportCardView: View {
    let report: ReportMock

    var body: some View {
        let cardOpacity = report.isDone ? 0.4 : 1.0
        
        VStack(alignment: .leading, spacing: 6) {
            // Numéro de ligne
            Text(report.lineNumber)
                .font(.caption2)
                .foregroundColor(.white)
                .padding(.vertical, 4)
                .padding(.horizontal, 6)
                .background(report.lineColor)
                .cornerRadius(4)
            
            // Nom de l'arrêt
            Text(report.stopName)
                .font(.subheadline)
                .fontWeight(.semibold)
                .foregroundColor(.black)
                .lineLimit(1)
            
            // From
            HStack(spacing: 4) {
                Text("↙").font(.caption2).foregroundColor(.orange)
                Text("From:").font(.caption2).foregroundColor(.orange)
                Text(report.fromText)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            // To
            HStack(spacing: 4) {
                Text("↗").font(.caption2).foregroundColor(Color(hex: "#FF5C5C"))
                Text("To:").font(.caption2).foregroundColor(Color(hex: "#FF5C5C"))
                Text(report.toText)
                    .font(.caption2)
                    .foregroundColor(.gray)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            
            Spacer() // Pousse le contenu vers le haut
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .padding(.vertical, 12)
        .padding(.horizontal, 10)
        .background(Color.white)
        .cornerRadius(10)
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .stroke(Color(hex: "#ECECEC"), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.02), radius: 1, x: 0, y: 1)
        .opacity(cardOpacity)
    }
}
