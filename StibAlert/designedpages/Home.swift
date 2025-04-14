//
//  Home.swift
//  StibAlert
//
//  Created by studentehb on 14/04/2025.
//

import SwiftUI

struct Home: View {
    @State var isLoggedIn = true
       @State var userName = "Michael"
       @State var userProfileImage: Image? = Image(systemName: "person.fill")
       @State var selectedTab = 0
       
       // Exemples de data
       let reports: [ReportMock] = [
           .init(lineNumber: "63", stopName: "Centraal-Station",
                 fromText: "Centraal Station", toText: "Begrafenis Evere",
                 lineColor: Color(hex: "#3762FF"), isDone: false),
           .init(lineNumber: "79", stopName: "Ambiorix",
                 fromText: "Kraainem", toText: "Maelbeek",
                 lineColor: Color(hex: "#F09E1B"), isDone: false),
           .init(lineNumber: "7",  stopName: "Heysel",
                 fromText: "Vanderkindere", toText: "Heysel",
                 lineColor: Color(hex: "#F5566E"), isDone: true),
           .init(lineNumber: "59", stopName: "Border-Stasi",
                 fromText: "Lorem Ipsum Lorem Ipsum", toText: "YYY",
                 lineColor: Color(hex: "#5FB04A"), isDone: false),
           .init(lineNumber: "90", stopName: "Optimisme",
                 fromText: "Trône", toText: "Simonis",
                 lineColor: Color(hex: "#F187FB"), isDone: false)
       ]
       
       var body: some View {
           ZStack {
               // Fond
               Color(hex: "#FAFAFD").ignoresSafeArea()
               
               VStack(spacing: 0) {
                   // ----- TOP BAR -----
                   HStack {
                       if isLoggedIn {
                           userProfileImage?
                               .resizable()
                               .scaledToFill()
                               .frame(width: 36, height: 36)
                               .clipShape(Circle())
                       } else {
                           Button("Se connecter") {}
                               .font(.caption2)
                               .padding(.vertical, 4)
                               .padding(.horizontal, 8)
                               .background(Color.gray.opacity(0.15))
                               .cornerRadius(6)
                       }
                       
                       Spacer()
                       
                       Text("Hey, \(userName)")
                           .font(.subheadline)
                           .fontWeight(.semibold)
                       
                       Spacer()
                       
                       Button {
                           // Notification
                       } label: {
                           Image(systemName: "bell")
                               .font(.title3)
                               .foregroundColor(.orange)
                       }
                   }
                   .padding(.horizontal, 24)
                   .padding(.top, 8)
                   
                   // ----- BANNIÈRE -----
                   RoundedRectangle(cornerRadius: 16)
                       .fill(Color.gray.opacity(0.15))
                       .frame(height: 200)
                       .padding(.horizontal, 24)
                       .padding(.top, 8)
                       .overlay(
                           Text("Ici un élément dynamique (bannière)")
                               .font(.footnote)
                               .foregroundColor(.gray)
                       )
                   
                   Spacer(minLength: 20)
                   
                   // ----- LATEST REPORTS + FILTRE -----
                   HStack {
                       Text("Latest reports")
                           .font(.headline)
                       Spacer()
                       Button {
                           // Filtre
                       } label: {
                           Image(systemName: "line.3.horizontal.decrease.circle")
                               .font(.title3)
                               .foregroundColor(.orange)
                       }
                   }
                   .padding(.horizontal, 24)
                   
                   // ----- GRILLE -----
                   if reports.isEmpty {
                       Text("Pas de signalement aujourd'hui.")
                           .foregroundColor(.gray)
                           .padding(.top, 40)
                       Spacer()
                   } else {
                       ScrollView {
                           LazyVGrid(
                               columns: [
                                   // Chaque colonne a une largeur flexible,
                                   // mais ne descend pas en dessous de 180
                                   GridItem(.flexible(minimum: 180), spacing: 20),
                                   GridItem(.flexible(minimum: 180), spacing: 20)
                               ],
                               spacing: 20
                           ) {
                               ForEach(reports) { item in
                                   // On fixe la hauteur à 150
                                   // => 2 colonnes, min 180 de large + 150 de haut
                                   ReportCardView(report: item)
                                       .frame(height: 150)
                               }
                           }
                           .padding(.horizontal, 24)
                           .padding(.top, 16)
                       }
                   }
                   
                   Spacer()
                   
                   // ----- TAB BAR -----
                   CustomTabBar(selectedTab: $selectedTab)
                       .frame(height: 60)
               }
           }
           .navigationBarHidden(true)
       }
   }

// MARK: - PREVIEW
struct HomeView_Previews: PreviewProvider {
    static var previews: some View {
        Home()
    }
}

