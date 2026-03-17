//
//  TabBar.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI

struct CustomTabBar: View {
    @Binding var selectedTab: Int

    let activeColor = Color(hex: "#4557A1")

    let tabs: [(icon: String, label: String)] = [
        ("location.fill", "Kaart"),
        ("list.bullet.rectangle", "Meldingen"),
        ("plus", "toevoegen"),
        ("heart", "Favorieten")
    ]

    var body: some View {
        HStack {
            ForEach(tabs.indices) { i in
                Spacer()
                Button {
                    selectedTab = i
                } label: {
                    VStack(spacing: 2) {
                        Image(systemName: tabs[i].icon)
                            .font(.system(size: 22, weight: .semibold))
                            .frame(minWidth: 44, minHeight: 28)
                            .foregroundColor(selectedTab == i ? activeColor : .gray)

                        Text(tabs[i].label)
                            .font(.caption2)
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
        .frame(height: 64)
        .background(
            Color.white
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: -1)
        )
    }
}
