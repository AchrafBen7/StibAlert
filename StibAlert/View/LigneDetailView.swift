//
//  LigneDetailView.swift
//  StibAlert
//
//  Created by studentehb on 27/03/2025.
//

import SwiftUI


struct LigneDetailView: View {
    let lineid: String

    var body: some View {
        VStack {
            PerturbationLigneView(lineID: lineid)
        }
        .navigationTitle("Ligne \(lineid)")
    }
}

