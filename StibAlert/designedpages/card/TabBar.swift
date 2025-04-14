//
//  TabBar.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//
import SwiftUI


struct CustomTabBar: View {
    @Binding var selectedTab: Int
    
    let activeColor = Color(hex: "#FF5C5C")
    let icons = ["house.fill", "mappin.and.ellipse", "plus", "heart", "person.fill"]
    
    var body: some View {
        HStack(spacing: 0) {
            ForEach(icons.indices, id: \.self) { i in
                Spacer()
                Button {
                    selectedTab = i
                } label: {
                    VStack(spacing: 3) {
                        Image(systemName: icons[i])
                            .font(.system(size: 20, weight: .semibold))
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
        .padding(.vertical, 10)
        .background(
            Color.white
                .shadow(color: .black.opacity(0.05), radius: 2, x: 0, y: -1)
        )
    }
}


