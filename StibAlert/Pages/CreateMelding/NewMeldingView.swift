
import SwiftUI

struct NewMeldingView: View {
    @StateObject private var viewModel = NewMeldingViewModel()
    
    // Champs du formulaire
    @State private var nomArret: String = ""
    @State private var ligne: String = ""
    @State private var selectedProbleem: ProbleemType? = nil
    @State private var description: String = ""
    @State private var photo: String = ""
    @State private var showSuccessAlert = false
    @State private var showLijnPicker = false
    @ObservedObject var lijnenVM = LijnenViewModel() // si ce n'est pas déjà présent
    @State private var showArretPicker = false
    @StateObject private var arretsVM = AlleHaltesViewModel()
    @State private var showErrorPopup = false
    
    
    
    
    
    
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
                        
                        Button(action: {
                            showLijnPicker = true
                        }) {
                            HStack {
                                if let selected = lijnenVM.lijnen.first(where: { $0.lineid == ligne }) {
                                    HStack(spacing: 12) {
                                        Text(selected.lineid)
                                            .font(.headline)
                                            .foregroundColor(.white)
                                            .frame(width: 44, height: 44)
                                            .background(LineColors.color(for: selected.lineid))
                                            .cornerRadius(10)
                                        
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(selected.nomComplet)
                                                .foregroundColor(.black)
                                                .font(.subheadline)
                                            if let retour = selected.nomCompletRetour {
                                                Text(retour)
                                                    .font(.caption)
                                                    .foregroundColor(.gray)
                                            }
                                        }
                                        Spacer()
                                    }
                                } else {
                                    Text("Choisir une ligne")
                                        .foregroundColor(.gray)
                                }
                                
                                Spacer()
                                Image(systemName: "chevron.down")
                                    .foregroundColor(.gray)
                            }
                            .padding()
                            .background(Color.white)
                            .cornerRadius(10)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                            )
                        }
                        .sheet(isPresented: $showLijnPicker) {
                            LijnPickerView(lignes: lijnenVM.lijnen) { selectedLine in
                                ligne = selectedLine.lineid
                                nomArret = "" // reset l'arrêt précédent
                                arretsVM.fetchArrets(lineId: selectedLine.lineid) // ici on charge les arrêts
                                showLijnPicker = false
                            }
                        }
                        
                        if !ligne.isEmpty {
                            Button(action: {
                                showArretPicker = true
                            }) {
                                HStack(spacing: 12) {
                                    Image(systemName: "mappin.and.ellipse")
                                        .foregroundColor(.white)
                                        .frame(width: 32, height: 32)
                                        .background(Color(hex: "#4557A1"))
                                        .cornerRadius(8)
                                    
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(nomArret.isEmpty ? "Choisir un arrêt" : nomArret)
                                            .foregroundColor(nomArret.isEmpty ? .gray : .black)
                                            .font(.subheadline)
                                    }
                                    
                                    Spacer()
                                    Image(systemName: "chevron.down")
                                        .foregroundColor(.gray)
                                }
                                .padding()
                                .background(Color.white)
                                .cornerRadius(10)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .stroke(Color.gray.opacity(0.2), lineWidth: 1)
                                )
                            }
                            .sheet(isPresented: $showArretPicker) {
                                ScrollView {
                                    VStack(spacing: 12) {
                                        Text("Choisis un arrêt")
                                            .font(.headline)
                                            .padding(.top, 16)
                                        
                                        // ✅ Supprime les doublons en groupant par nom
                                        let arretsUniques = Dictionary(grouping: arretsVM.arrets, by: { $0.nom }).compactMap { $0.value.first }
                                        
                                        ForEach(arretsUniques) { halte in
                                            Button(action: {
                                                nomArret = halte.nom
                                                showArretPicker = false
                                            }) {
                                                HStack(spacing: 12) {
                                                    // 🧭 Icône neutre
                                                    Image(systemName: "mappin.and.ellipse")
                                                        .foregroundColor(.white)
                                                        .frame(width: 32, height: 32)
                                                        .background(Color(hex: "#4557A1"))
                                                        .cornerRadius(8)
                                                    
                                                    // 🅰️ Nom de l'arrêt
                                                    Text(halte.nom)
                                                        .foregroundColor(.black)
                                                        .font(.subheadline)
                                                    
                                                    Spacer()
                                                }
                                                .padding()
                                                .background(Color.white)
                                                .cornerRadius(12)
                                                .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                                                .padding(.horizontal)
                                            }
                                        }
                                    }
                                    .padding(.bottom)
                                }
                                
                            }
                            
                            
                        }
                        
                        
                        // Sélecteur de problème
                        
                        VStack(alignment: .leading, spacing: 12) {
                            Text("Quel est le souci ?")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                                .padding(.horizontal, 24)
                            
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                                ForEach(ProbleemType.allCases.filter { $0 != .Autre }) { probleem in
                                    Button(action: {
                                        selectedProbleem = probleem
                                    }) {
                                        VStack(spacing: 8) {
                                            Image(systemName: probleem.icon)
                                                .font(.system(size: 22, weight: .bold))
                                                .foregroundColor(.white)
                                            Text(probleem.rawValue)
                                                .font(.caption)
                                                .foregroundColor(.white)
                                                .multilineTextAlignment(.center)
                                        }
                                        .frame(width: 90, height: 90)
                                        .background(
                                            probleem.color.opacity(probleem == selectedProbleem ? 1 : 0.6)
                                        )
                                        .cornerRadius(16)
                                    }
                                }
                            }
                            .padding(.horizontal, 24)
                            
                            // ✅ Bouton pour "Autre"
                            // ✅ Bouton pour "Autre"
                            Button(action: {
                                selectedProbleem = .Autre
                            }) {
                                HStack(spacing: 8) {
                                    Image(systemName: ProbleemType.Autre.icon)
                                        .foregroundColor(selectedProbleem == .Autre ? .white : .gray)
                                    Text("Autre")
                                        .foregroundColor(selectedProbleem == .Autre ? .white : .gray)
                                }
                                .font(.subheadline)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(selectedProbleem == .Autre ? Color.gray : Color.white)
                                .cornerRadius(12)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 12)
                                        .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                                )
                            }
                            .padding(.top, 8)
                            .padding(.horizontal, 24)
                            .padding(.bottom, 16)
                            
                        }
                        
                        
                        HStack {
                            Text("Explique plus en détail")
                                .font(.subheadline)
                                .foregroundColor(.gray)
                            Spacer()
                        }
                        .padding(.horizontal, 24)
                        .padding(.top, 4)
                        
                        CustomInputField(placeholder: "Décrivez ce qui s’est passé…", text: $description, isMultiline: true)
                        
                        CustomInputField(placeholder: "URL d’une photo (facultatif)", text: $photo)
                    }
                    .padding(.horizontal, 24)
                    
                    // Bouton de soumission
                    Button(action: {
                        guard let typeProbleme = selectedProbleem?.rawValue else {
                            viewModel.errorMessage = "Veuillez sélectionner un type de problème."
                            return
                        }
                        
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
        .overlay( // ✅ Le pop-up erreur dans un overlay du ZStack principal
            Group {
                if showErrorPopup, let error = viewModel.errorMessage {
                    VStack(spacing: 16) {
                        Image(systemName: "exclamationmark.triangle.fill")
                            .resizable()
                            .frame(width: 40, height: 40)
                            .foregroundColor(.white)
                            .padding()
                            .background(Color.red)
                            .clipShape(Circle())
                        
                        Text("Oups !")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundColor(.black)
                        
                        Text(error)
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                            .padding(.horizontal, 16)
                        
                        Button(action: {
                            withAnimation {
                                showErrorPopup = false
                                viewModel.errorMessage = nil
                            }
                        }) {
                            Text("Fermer")
                                .fontWeight(.semibold)
                                .padding(.horizontal, 24)
                                .padding(.vertical, 10)
                                .background(Color.red.opacity(0.1))
                                .cornerRadius(10)
                        }
                    }
                    .padding()
                    .background(Color.white)
                    .cornerRadius(20)
                    .shadow(radius: 20)
                    .padding(.horizontal, 40)
                    .transition(.scale)
                    .zIndex(2)
                }
            }
        )
        
        .alert(isPresented: $showSuccessAlert) {
            Alert(
                title: Text("Succès"),
                message: Text("Le signalement a bien été créé."),
                dismissButton: .default(Text("OK")) {
                    nomArret = ""
                    ligne = ""
                    selectedProbleem = nil
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
        }.onAppear {
            lijnenVM.fetchLijnen()
        }
        .onChange(of: viewModel.errorMessage) { newValue in
            if newValue != nil {
                withAnimation {
                    showErrorPopup = true
                }
            }
        }
        
    }
    
}
