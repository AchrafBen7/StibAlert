import SwiftUI

struct LijnenLijstView: View {
    @StateObject private var viewModel = LijnenViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    if let error = viewModel.errorMessage {
                        Text("Erreur : \(error)")
                            .foregroundColor(.red)
                            .padding()
                    }
                    
                    ForEach(viewModel.lijnen) { ligne in
                        VStack(alignment: .leading, spacing: 8) {
                            // Bouton pour le sens normal (nomComplet)
                            Button(action: {
                                print("Ligne \(ligne.lineid) normale sélectionnée")
                            }) {
                                Text("Ligne \(ligne.lineid) : \(ligne.nomComplet)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                                    .padding()
                                    .frame(maxWidth: .infinity)
                                    .background(Color.blue)
                                    .cornerRadius(8)
                            }
                            
                            // Bouton pour le sens retour (nomCompletRetour)
                            Button(action: {
                                print("Ligne \(ligne.lineid) retour sélectionnée")
                            }) {
                                // Si nomCompletRetour est défini, on l'affiche, sinon on indique "Non défini"
                                Text("Ligne \(ligne.lineid)<<<<<<<:\(ligne.nomCompletRetour ?? "Non défini")")
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
 
