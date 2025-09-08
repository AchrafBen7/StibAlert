//
//  LijnPickerView.swift
//  StibAlert
//
//  Created by studentehb on 17/04/2025.
//
import SwiftUI

struct LijnPickerView: View {
    let lignes: [LijnModel]
    var onSelect: (LijnModel) -> Void
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(lignes) { line in
                        Button {
                            onSelect(line)
                            dismiss()                         } label: {
                            HStack {
                                Text(line.lineid)
                                    .font(.headline)
                                     .foregroundColor(.white)
                                    .frame(width: 44, height: 44)
                                    .background(LineColors.color(for: line.lineid))
                                    .cornerRadius(10)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.nomComplet)
                                        .foregroundColor(.black)
                                        .font(.subheadline)
                                    if let retour = line.nomCompletRetour {
                                        Text(retour)
                                            .font(.caption)
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
                .padding()
            }
            .navigationTitle("Choisis une ligne")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Fermer") {
                        dismiss()
                    }
                }
            }
        }
    }
}
