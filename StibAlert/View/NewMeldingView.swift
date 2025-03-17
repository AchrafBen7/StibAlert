import SwiftUI

struct NewMeldingView: View {
    @StateObject private var viewModel = NewMeldingViewModel()
    
    // Variables pour l’input
    @State private var nomArret: String = ""
    @State private var ligne: String = ""
    @State private var typeProbleme: String = ""
    @State private var description: String = ""
    @State private var photo: String = ""
    
    // Contrôle de l’alerte
    @State private var showSuccessAlert = false
    
    var body: some View {
        NavigationView {
            Form {
                Section(header: Text("Nieuwe melding invoeren")) {
                    TextField("Halte naam", text: $nomArret)
                    TextField("Lijn", text: $ligne)
                    TextField("Type probleem", text: $typeProbleme)
                    TextField("Beschrijving", text: $description)
                    TextField("Foto URL (optioneel)", text: $photo)
                }
                
                Button("Verstuur melding") {
                    let newMelding = NewMeldingRequest(
                        nomArret: nomArret,
                        ligne: ligne,
                        typeProbleme: typeProbleme,
                        description: description,
                        photo: photo.isEmpty ? nil : photo
                    )
                    viewModel.postMelding(nieuweMelding: newMelding)
                }
                
                // En cas d'erreur
                if let error = viewModel.errorMessage {
                    Section {
                        Text("Fout: \(error)")
                            .foregroundColor(.red)
                    }
                }
            }
            .navigationTitle("Nieuwe Melding")
            
            // ALERTE DE SUCCÈS
            .alert(isPresented: $showSuccessAlert) {
                Alert(
                    title: Text("Succès"),
                    message: Text("Le signalement a bien été créé."),
                    dismissButton: .default(Text("OK")) {
                        // Optionnel: réinitialiser le formulaire
                        nomArret = ""
                        ligne = ""
                        typeProbleme = ""
                        description = ""
                        photo = ""
                        
                        // Optionnel: remettre la variable à nil pour ne pas ré-afficher l'alerte
                        viewModel.MeldingCreated = nil
                    }
                )
            }
            
            // Détecter quand `MeldingCreated` change
            .onChange(of: viewModel.MeldingCreated) { oldValue, newValue in
               

                if oldValue == nil && newValue != nil {
                    // Affichez votre alerte de succès, par exemple :
                    showSuccessAlert = true
                }
            }

        }
    }
    
    // Formatter pour la date (si vous en avez encore besoin)
    private var dateFormatter: DateFormatter {
        let formatter = DateFormatter()
        formatter.dateStyle = .short
        formatter.timeStyle = .short
        return formatter
    }
}
