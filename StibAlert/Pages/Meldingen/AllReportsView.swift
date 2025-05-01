//
//  AllReportsView.swift
//  StibAlert
//
//  Created by studentehb on 01/05/2025.
//
//
//  DraggableSheet.swift
//  StibAlert
//
//  Created by studentehb on 16/04/2025.
//

import SwiftUI

struct AllReportsView: View {
    @StateObject private var meldingenVM = MeldingenViewModel()
    @StateObject private var lijnenVM = LijnenViewModel()
    
    @State private var selectedTransit: TransitMapView.TransitMode = .metro
    @State private var selectedLijnId: String? = nil
    
    // 🟢 Filtrage des lignes selon le transport sélectionné
    private var filteredLijnen: [LijnModel] {
        lijnenVM.lijnen.filter { line in
            let type = line.typeTransport.lowercased()
            switch selectedTransit {
            case .bus: return type.contains("bus")
            case .metro: return type.contains("metro") || ["1", "2", "5", "6"].contains(line.lineid)
            case .tram: return type.contains("tram")
            }
        }
    }
    
    // 🔵 Signalements filtrés
    private var filteredMeldingen: [MeldingenReadModel] {
        let recent = meldingenVM.meldingen.filter {
            Date().timeIntervalSince($0.dateSignalement) <= (24 * 60 * 60)
        }
        
        if let selectedLijnId {
            return recent
                .filter { $0.ligne == selectedLijnId }
                .sorted { $0.dateSignalement > $1.dateSignalement }
        } else {
            // ✅ Si aucune ligne sélectionnée, montre tout
            return recent.sorted { $0.dateSignalement > $1.dateSignalement }
        }
    }
    
    var body: some View {
        VStack(spacing: 0) {
            // --- BOUTONS BUS / METRO / TRAM ---
            HStack(spacing: 16) {
                ForEach(TransitMapView.TransitMode.allCases) { mode in
                    let isSelected = (mode == selectedTransit)
                    Button {
                        selectedTransit = mode
                        selectedLijnId = nil
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: iconName(for: mode))
                            Text(mode.rawValue.capitalized)
                        }
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#4557A1"))
                        .padding(.vertical, 10)
                        .padding(.horizontal, 16)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(isSelected ? Color(hex: "#F18F5D").opacity(0.3) : Color(hex: "#FAFAFD"))
                        )
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 12)
            
            Divider()
            
            // --- LIGNES DISPONIBLES ---
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(filteredLijnen) { line in
                        let isSelected = selectedLijnId == line.lineid
                        Button {
                            selectedLijnId = line.lineid
                        } label: {
                            HStack(spacing: 8) {
                                Text(line.lineid)
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundColor(.white)
                                    .padding(10)
                                    .background(LineColors.color(for: line.lineid))
                                    .cornerRadius(8)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(line.nomComplet)
                                        .font(.caption)
                                        .foregroundColor(.primary)
                                    if let retour = line.nomCompletRetour {
                                        Text(retour)
                                            .font(.caption2)
                                            .foregroundColor(.gray)
                                    }
                                }
                            }
                            .padding(8)
                            .background(
                                RoundedRectangle(cornerRadius: 12)
                                    .fill(isSelected ? Color(hex: "#F0F4FF") : Color.white)
                                    .overlay(
                                        RoundedRectangle(cornerRadius: 12)
                                            .stroke(isSelected ? Color.blue.opacity(0.6) : Color.clear, lineWidth: 1.5)
                                    )
                                    .shadow(color: Color.black.opacity(0.05), radius: 1, x: 0, y: 1)
                            )
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 4)
            }
            
            // ✅ Réinitialisation du filtre (juste après la ScrollView)
            if selectedLijnId != nil {
                HStack {
                    Spacer()
                    Button(action: {
                        selectedLijnId = nil
                    }) {
                        Label("Réinitialiser le filtre", systemImage: "arrow.uturn.left")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 10)
            }
            
            
            // --- SIGNALEMENTS ---
            ScrollView {
                if filteredMeldingen.isEmpty {
                    Text("Pas de signalements pour cette ligne.")
                        .foregroundColor(.gray)
                        .padding()
                } else {
                    LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                        ForEach(filteredMeldingen) { melding in
                            NavigationLink(
                                destination: MeldingDetailView(arretId: melding.arretId._id, signalementId: melding._id)
                            ) {
                                MeldingenCardView(signalement: melding)
                                    .frame(height: 150)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                    }
                    .padding(.horizontal)
                    .padding(.top, 10)
                }
            }
            
            Spacer()
        }
        .navigationTitle("All reports")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear {
            lijnenVM.fetchLijnen()
            meldingenVM.fetchMeldingen()
        }
    }
    
    private func iconName(for mode: TransitMapView.TransitMode) -> String {
        switch mode {
        case .bus: return "bus"
        case .metro, .tram: return "tram.fill"
        }
    }
}
