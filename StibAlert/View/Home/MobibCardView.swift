//
//  MobibCardView.swift
//  StibAlert
//
//  Created by studentehb on 28/04/2025.
//
 
import SwiftUI
 
struct MobibCardView: View {
    @ObservedObject var authViewModel: AuthViewModel
    @State private var animateGradient = false
    
    var body: some View {
        ZStack(alignment: .topLeading) {
          
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#F18F5D"), Color(hex: "#FF7E47")]),
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .animation(Animation.linear(duration: 8).repeatForever(autoreverses: true), value: animateGradient)
            .onAppear {
                animateGradient = true
            }
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("MOBIB")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                    Spacer()
                    Image(systemName: "tram.fill")
                        .foregroundColor(.white.opacity(0.8))
                        .font(.title3)
                }
                
                HStack {
                    Image(systemName: "creditcard.fill")
                        .foregroundColor(.white)
                    Text("**** **** \(authViewModel.user?._id.suffix(4) ?? "1234")")
                        .foregroundColor(.white)
                        .font(.caption)
                }
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(authViewModel.user?.nom ?? "Gast")
                        .font(.headline)
                        .foregroundColor(.white)
                    Text("STIB - MIVB")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }
                
                Spacer()
                
                HStack {
                    Image(systemName: "bus.fill")
                    Image(systemName: "tram.fill")
                    Image(systemName: "train.side.front.car")
                }
                .foregroundColor(.white.opacity(0.8))
                .font(.caption)
            }
            .padding()
        }
        .frame(height: 200)
        .padding(.horizontal, 5)
    }
}
