//
//  OfflineBanner.swift
//  StibAlert
//
//  Created by studentehb on 29/04/2025.
//

import SwiftUI

struct OfflineBanner: View {
    var body: some View {
        HStack {
            Image(systemName: "wifi.slash")
                .foregroundColor(.white)
                .imageScale(.medium)
            
            Text("Mode hors-ligne activé")
                .foregroundColor(.white)
                .font(.footnote)
                .bold()
        }
        .padding()
        .frame(maxWidth: .infinity)
        .background(Color.red.opacity(0.9))
        .cornerRadius(10)
        .padding(.horizontal)
        .padding(.top, 8)
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.easeInOut, value: UUID()) 
    }
}
