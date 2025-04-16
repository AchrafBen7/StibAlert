
import SwiftUI

struct NewMeldingView: View {
    @StateObject private var viewModel = NewMeldingViewModel()
    
    // Champs du formulaire
    @State private var nomArret: String = ""
    @State private var ligne: String = ""
    @State private var typeProbleme: String = ""
    @State private var description: String = ""
    @State private var photo: String = ""
    @State private var showSuccessAlert = false
    
    var body: some View {
        ZStack {
            Color(hex: "#FAFAFD").ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    Text("Ajouter un signalement")
                        .font(.title2)
                        .fontWeight(.bold)
                        .padding(.top, 24)
                        .padding(.horizontal, 24)
                    
                    // Champs du formulaire
                    Group {
                        CustomInputField(placeholder: "Nom de l'arrêt", text: $nomArret)
                        CustomInputField(placeholder: "Ligne", text: $ligne)
                        CustomInputField(placeholder: "Type de problème", text: $typeProbleme)
                        CustomInputField(placeholder: "Description", text: $description, isMultiline: true)
                        CustomInputField(placeholder: "URL d’une photo (facultatif)", text: $photo)
                    }
                    .padding(.horizontal, 24)
                    
                    // Bouton de soumission
                    Button(action: {
                        let newMelding = NewMeldingRequest(
                            nomArret: nomArret,
                            ligne: ligne,
                            typeProbleme: typeProbleme,
                            description: description,
                            photo: photo.isEmpty ? nil : photo
                        )
                        viewModel.postMelding(nieuweMelding: newMelding)
                    }) {
                        Text("Envoyer le signalement")
                            .foregroundColor(.white)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color(hex: "#4557A1"))
                            .cornerRadius(12)
                            .font(.headline)
                    }
                    .padding(.horizontal, 24)
                    .padding(.bottom, 40)
                }
            }
        }
        .alert(isPresented: $showSuccessAlert) {
            Alert(
                title: Text("Succès"),
                message: Text("Le signalement a bien été créé."),
                dismissButton: .default(Text("OK")) {
                    nomArret = ""
                    ligne = ""
                    typeProbleme = ""
                    description = ""
                    photo = ""
                    viewModel.MeldingCreated = nil
                }
            )
        }
        .onChange(of: viewModel.MeldingCreated) { newValue in
            if newValue != nil {
                showSuccessAlert = true
            }
        }
        
    }
}
