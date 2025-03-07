//
//  ContentView.swift
//  StibAlert
//
//  Created by studentehb on 06/03/2025.
//

import SwiftUI

struct ContentView: View {
    var body: some View {
        VStack {
            Image(systemName: "globe")
                .imageScale(.large)
                .foregroundStyle(.tint)
            Text("Let's go!")
        }
        .padding()
        .onAppear {
            testHalteModel()
        }
    }
}
// hier heb ik aan chatgpt gevraagd om mijn haltemodel te testen.
func testHalteModel() {
    print("testHalteModel is gecalled")
    let jsonString = """
    {
        "stop_id": "12345",
        "nom": "Centraal Station",
        "latitude": 50.8503,
        "longitude": 4.3517,
        "typeTransport": "Metro",
        "lignesDesservies": ["5", "1"],
        "etat": "Vert",
        "signalementRecents": ["sig1", "sig2"]
    }
    """
    if let jsonData = jsonString.data(using: .utf8) {
        do {
            let halte = try JSONDecoder().decode(halteModel.self, from: jsonData)
            print("Halte décodée avec succès:")
            print("ID: \(halte.id)")
            print("Nom: \(halte.nom)")
            print("Latitude: \(halte.latitude)")
            print("Longitude: \(halte.longitude)")
            print("Type de transport: \(halte.typeTransport)")
            print("Lignes desservies: \(halte.lignesDesservies)")
            print("État: \(halte.etat)")
            if let recents = halte.signalementRecents {
                print("Signalements récents: \(recents)")
            }
        } catch {
            print("Erreur lors du décodage: \(error)")
        }
    } else {
        print("Conversion du JSON en Data a échoué")
    }
}

#Preview {
    ContentView()
}
