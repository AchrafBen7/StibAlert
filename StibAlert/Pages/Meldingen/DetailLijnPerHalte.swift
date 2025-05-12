//
//  DetailLijnPerHalte.swift
//  StibAlert
//
//  Created by studentehb on 12/05/2025.
//
import SwiftUI

struct LigneDetailHalteView: View {
    let line: LijnModel
    @Environment(\.presentationMode) var presentationMode
    @StateObject private var halteVM = AlleHaltesViewModel()
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            
            // Header haut ligne STIB
            HStack(alignment: .center, spacing: 12) {
                Button(action: {
                    presentationMode.wrappedValue.dismiss()
                }) {
                    Image(systemName: "chevron.left")
                        .foregroundColor(.blue)
                        .font(.system(size: 20, weight: .medium))
                }

                Text(line.lineid)
                    .font(.system(size: 18, weight: .bold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(LineColors.color(for: line.lineid))
                    .cornerRadius(10)

                VStack(alignment: .leading, spacing: 2) {
                    Text(line.nomComplet)
                        .font(.headline)
                        .foregroundColor(.black)
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

            Divider()
            
            ScrollView {
                VStack(spacing: 8) {
                    let uniqueHaltes = Dictionary(grouping: halteVM.arrets, by: { $0._id }).compactMap { $0.value.first }

                    ForEach(uniqueHaltes) { halte in
                        let count = halte.signalementsRecents?.count ?? 0

                        NavigationLink(destination: MeldingenPerHalteView(halte: halte)) {
                            HStack(spacing: 12) {
                                Rectangle()
                                    .fill(statusColor(for: halte))
                                    .frame(width: 6)
                                    .cornerRadius(3)

                                VStack(alignment: .leading, spacing: 4) {
                                    Text(halte.nom)
                                        .font(.body)
                                        .bold()

                                    Text("\(count) signalement(s)")
                                        .font(.caption)
                                        .foregroundColor(.gray)
                                }

                                Spacer()

                                if count >= 4 {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .foregroundColor(.red)
                                }
                            }
                            .padding()
                            .background(Color(hex: "#F2F6FB"))
                            .cornerRadius(12)
                            .padding(.horizontal)
                        }
                        .buttonStyle(PlainButtonStyle())
                    }
                }
                .padding(.top, 8)
            }
        }
        .navigationBarHidden(true)
        .onAppear {
            halteVM.fetchArrets(lineId: line.lineid)
        }
    }

    func statusColor(for halte: HalteModel) -> Color {
        let count = halte.signalementsRecents?.count ?? 0
        if count >= 4 { return .red }
        else if count >= 2 { return .yellow }
        else { return .green }
    }
}
