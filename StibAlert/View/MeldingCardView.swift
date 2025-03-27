//
//  MeldingCardView.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//
import SwiftUI

struct SignalementCardView: View {
    let signalement: Signalement

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("🛑 \(signalement.typeProbleme)").bold()
            Text("📍 Arrêt : \(signalement.arretNom ?? "Inconnu")")
            Text("📝 \(signalement.description)")
            Text("🧠 IA validée : \(signalement.validationIA ? "Oui" : "Non")")
            Text("📊 Confiance : \(signalement.confiance)")
            Text("👍 \(signalement.votesPositifs) / 👎 \(signalement.votesNegatifs)")
            Text("📆 \(signalement.dateSignalement.prefix(10))")
        }
        .padding()
        .background(Color(.systemGray6))
        .cornerRadius(8)
    }
}
