//
//  FavorisHalteRow.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
//

 
import SwiftUI
 
struct FavorisHalteRow: View {
    let halte: HalteModel
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 12) {
                if let firstLine = halte.lignesDesservies.first {
                    Text(firstLine)
                        .font(.headline)
                        .foregroundColor(.white)
                        .frame(width: 44, height: 44)
                        .background(LineColors.color(for: firstLine))
                        .cornerRadius(10)
                }
                
                VStack(alignment: .leading, spacing: 2) {
                    Text(halte.nom)
                        .font(.subheadline)
                        .foregroundColor(.black)
                    
                    Text("Aantal meldingen vandaag: \(halte.signalementsRecents?.count ?? 0)")
                        .font(.caption)
                        .foregroundColor(.gray)
                    
                    if let aller = halte.lignesDesservies.first, let retour = halte.lignesDesservies.last, aller != retour {
                        Text("↔️ \(aller) ⇄ \(retour)")
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                
                Spacer()
            }
            .padding()
            .background(Color.white)
            .cornerRadius(12)
            .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
        }
    }
}
