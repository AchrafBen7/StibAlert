//
//  TabBar.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int
    
    // Couleur active selon la charte
    let activeColor = Color(hex: "#4557A1")
    // On garde 4 icônes : Maison, Carte, Plus et Coeur
    let icons = ["house.fill", "location.fill", "plus", "heart"]
    
    var body: some View {
        HStack {
            ForEach(icons.indices, id: \.self) { i in
                Spacer()
                Button {
                    selectedTab = i
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: icons[i])
                            .font(.system(size: 22, weight: .semibold))
                            // Zone de tap minimale pour une bonne ergonomie
                            .frame(minWidth: 44, minHeight: 44)
                            .foregroundColor(selectedTab == i ? activeColor : .gray)
                        if selectedTab == i {
                            Circle()
                                .fill(activeColor)
                                .frame(width: 4, height: 4)
                        }
                    }
                }
                Spacer()
            }
        }
        .padding(.vertical, 4)
        .frame(height: 50) // Hauteur ajustée pour imiter une vraie barre d'onglets iPhone
        .background(
            Color.white
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: -1)
        )
    }
}
