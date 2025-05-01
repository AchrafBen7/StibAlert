//
//  LijnSelectieButton.swift
//  StibAlert
//
//  Created by studentehb on 01/05/2025.
//


import SwiftUI

struct LijnSelectieButton: View {
    let ligne: String
    let lignes: [LijnModel]
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack {
                if let selected = lignes.first(where: { $0.lineid == ligne }) {
                    HStack(spacing: 12) {
                        Text(selected.lineid)
                            .font(.headline)
                            .foregroundColor(.white)
                            .frame(width: 44, height: 44)
                            .background(LineColors.color(for: selected.lineid))
                            .cornerRadius(10)
                        
                        VStack(alignment: .leading, spacing: 2) {
                            Text(selected.nomComplet)
                                .foregroundColor(.black)
                                .font(.subheadline)
                            if let retour = selected.nomCompletRetour {
                                Text(retour)
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                        }
                        Spacer()
                    }
                } else {
                    Text("Choisir une ligne")
                        .foregroundColor(.gray)
                }
                
                Spacer()
                Image(systemName: "chevron.down")
                    .foregroundColor(.gray)
            }
            .padding()
            .background(Color.white)
            .cornerRadius(10)
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
            )
        }
    }
}

