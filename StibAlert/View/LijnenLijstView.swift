import SwiftUI

struct LijnenLijstView: View {
    @StateObject private var viewModel = LijnenViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                ForEach(viewModel.lijnen) { ligne in
                    VStack(spacing: 8) {
                        // Sens Aller
                        NavigationLink(destination: HalteLijstView(lijn: ligne)) {
                            Text("Ligne \(ligne.lineid) : \(ligne.nomComplet)")
                                .font(.headline)
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.blue)
                                .cornerRadius(8)
                        }
                        
                        // Sens Retour (si défini)
                        if let retour = ligne.nomCompletRetour {
                            NavigationLink(destination: HalteLijstView(lijn: ligne)) {
                                Text("Ligne \(ligne.lineid) : \(retour)")
                                    .font(.subheadline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.green)
                                    .cornerRadius(8)
                            }
                        }
                    }
                }
                .padding()
            }
            .navigationTitle("Toutes les lignes")
            .onAppear {
                viewModel.fetchLijnen()
            }
        }
    }
}

