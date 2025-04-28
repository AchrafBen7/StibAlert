//
//  TransitAnimationView.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//
//
//  TransitAnimationView.swift
//  StibAlert
//
//  Created by studentehb on 15/04/2025.
//
 
import SwiftUI
 
struct TransitBannerView: View {
    @State private var animateGradient = false
    
    var body: some View {
        ZStack {
            // Fond animé : un dégradé linéaire qui bascule subtilement entre deux orientations
            LinearGradient(
                gradient: Gradient(colors: [Color(hex: "#3762FF"), Color(hex: "#4557A1")]),
                startPoint: animateGradient ? .topLeading : .bottomTrailing,
                endPoint: animateGradient ? .bottomTrailing : .topLeading
            )
            .animation(Animation.linear(duration: 10).repeatForever(autoreverses: true), value: animateGradient)
            .onAppear {
                animateGradient = true
            }
            .cornerRadius(16)
            .shadow(color: Color.black.opacity(0.2), radius: 8, x: 0, y: 4)
            
            // Filigrane avec l'icône du bus, en transparence pour ajouter du style
            Image(systemName: "bus.fill")
                .resizable()
                .scaledToFit()
                .frame(width: 80, height: 80)
                .opacity(0.15)
                .offset(x: -100, y: 30)
            
            // Contenu textuel
            VStack(spacing: 4) {
                Text("STIB/MIVB")
                    .font(.title)
                    .fontWeight(.bold)
                    .foregroundColor(.white)
                
                Text("Brussels Public Transport")
                    .font(.subheadline)
                    .foregroundColor(.white)
                    .opacity(0.9)
            }
        }
        .padding(.horizontal, 24)
        .frame(height: 200)
    }
}
 
struct TransitBannerView_Previews: PreviewProvider {
    static var previews: some View {
        TransitBannerView()
            .previewLayout(.sizeThatFits)
    }
}
 
