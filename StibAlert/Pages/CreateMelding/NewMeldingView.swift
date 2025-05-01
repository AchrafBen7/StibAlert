
import SwiftUI
import SwiftUI

struct NewMeldingView: View {
    @StateObject private var viewModel = NewMeldingViewModel()
    
    @State private var nomArret: String = ""
    @State private var ligne: String = ""
    @State private var selectedProbleem: ProbleemType? = nil
    @State private var description: String = ""
    @State private var photo: String = ""
    @State private var showSuccessAlert = false
    @State private var showLijnPicker = false
    @ObservedObject var lijnenVM = LijnenViewModel()
    @State private var showArretPicker = false
    @StateObject private var arretsVM = AlleHaltesViewModel()
    @State private var showErrorPopup = false
    @State private var selectedUIImage: UIImage?
    @State private var showImagePicker = false
    @State private var useCamera = false
    
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
                    
                    formSection
                    
                    envoyerButtonSection
                }
            }
        }
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedUIImage, sourceType: useCamera ? .camera : .photoLibrary)
        }
        .sheet(isPresented: $showLijnPicker) {
            LijnPickerView(lignes: lijnenVM.lijnen) { selectedLine in
                ligne = selectedLine.lineid
                nomArret = ""
                arretsVM.fetchArrets(lineId: selectedLine.lineid)
                showLijnPicker = false
            }
        }
        .sheet(isPresented: $showArretPicker) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Choisis un arrêt")
                        .font(.headline)
                        .padding(.top, 16)
                    
                    let arretsUniques = Dictionary(grouping: arretsVM.arrets, by: { $0.nom }).compactMap { $0.value.first }
                    
                    ForEach(arretsUniques) { halte in
                        Button(action: {
                            nomArret = halte.nom
                            showArretPicker = false
                        }) {
                            HStack(spacing: 12) {
                                Image(systemName: "mappin.and.ellipse")
                                    .foregroundColor(.white)
                                    .frame(width: 32, height: 32)
                                    .background(Color(hex: "#4557A1"))
                                    .cornerRadius(8)
                                
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
                }.padding(.bottom)
            }
        }
        .overlay(
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
                        
                        Text(error)
                            .multilineTextAlignment(.center)
                            .font(.subheadline)
                            .foregroundColor(.gray)
                        
                        Button("Fermer") {
                            withAnimation {
                                showErrorPopup = false
                                viewModel.errorMessage = nil
                            }
                        }
                        .padding(.horizontal, 24)
                        .padding(.vertical, 10)
                        .background(Color.red.opacity(0.1))
                        .cornerRadius(10)
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
                    selectedUIImage = nil
                    viewModel.MeldingCreated = nil
                }
            )
        }
        .onChange(of: viewModel.MeldingCreated) { if $0 != nil { showSuccessAlert = true } }
        .onChange(of: viewModel.errorMessage) { if $0 != nil { withAnimation { showErrorPopup = true } } }
        .onAppear { lijnenVM.fetchLijnen() }
    }
    
    // MARK: - Sections
    private var formSection: some View {
        VStack(spacing: 16) {
            // 1. Sélection de la ligne
            LijnSelectieButton(ligne: ligne, lignes: lijnenVM.lijnen) {
                showLijnPicker = true
            }
            
            // 2. Sélection de l'arrêt (uniquement si une ligne est choisie)
            if !ligne.isEmpty {
                Button {
                    showArretPicker = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.white)
                            .frame(width: 32, height: 32)
                            .background(Color(hex: "#4557A1"))
                            .cornerRadius(8)
                        
                        Text(nomArret.isEmpty ? "Choisir un arrêt" : nomArret)
                            .foregroundColor(nomArret.isEmpty ? .gray : .black)
                            .font(.subheadline)
                        
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
            }
            
            // 3. Problème
            probleemSection
            
            // 4. Description
            VStack(alignment: .leading) {
                Text("Explique plus en détail")
                    .font(.subheadline)
                    .foregroundColor(.gray)
                CustomInputField(placeholder: "Décrivez ce qui s’est passé…", text: $description, isMultiline: true)
            }
            
            // 5. Photo
            PhotoPickerSection(
                selectedUIImage: $selectedUIImage,
                showImagePicker: $showImagePicker,
                useCamera: $useCamera
            )
        }
        .padding(.horizontal, 24)
    }
    
    private var probleemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quel est le souci ?")
                .font(.subheadline)
                .foregroundColor(.gray)
                .padding(.horizontal, 24)
            
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 3), spacing: 16) {
                ForEach(ProbleemType.allCases.filter { $0 != .Autre }) { probleem in
                    Button {
                        selectedProbleem = probleem
                    } label: {
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
                        .background(probleem.color.opacity(probleem == selectedProbleem ? 1 : 0.6))
                        .cornerRadius(16)
                    }
                }
            }
            .padding(.horizontal, 24)
            
            
        }
    }
    
    private var envoyerButtonSection: some View {
        Button {
            guard let typeProbleme = selectedProbleem?.rawValue else {
                viewModel.errorMessage = "Veuillez sélectionner un type de problème."
                return
            }
            let newMelding = NewMeldingRequest(
                nomArret: nomArret,
                ligne: ligne,
                typeProbleme: typeProbleme,
                description: description
                
            )
            if let image = selectedUIImage {
                viewModel.postMeldingWithImage(nieuweMelding: newMelding, image: image)
            } else {
                viewModel.postMelding(nieuweMelding: newMelding)
            }
        } label: {
            Text("Envoyer le signalement")
                .foregroundColor(.white)
                .frame(maxWidth: .infinity)
                .padding()
                .background(Color(hex: "#4557A1"))
                .cornerRadius(12)
                .font(.headline)
        }
        .padding(.horizontal, 24)
    }
}
