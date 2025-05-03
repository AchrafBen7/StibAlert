
import SwiftUI
import CoreLocation


struct NewMeldingView: View {
    @StateObject private var viewModel = NewMeldingViewModel()
    @StateObject private var locationManager = LocationManager()
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
    @State private var selectedArretId: String = ""
    @State private var showAllNearbyStops = false
    
    
    
    private func computeNearbyHaltes() -> [HalteModel] {
        guard let userLocation = locationManager.userLocation else {
            print("[DEBUG] ❌ Position utilisateur indisponible")
            return []
        }
        
        print("[DEBUG] 📍 Position utilisateur : \(userLocation.latitude), \(userLocation.longitude)")
        print("[DEBUG] 🧮 Nombre total d'arrêts disponibles : \(arretsVM.arrets.count)")
        
        var seen = Set<String>()
        
        let result: [HalteModel] = arretsVM.arrets.compactMap { halte -> HalteModel? in
            let halteCoord = CLLocation(latitude: halte.latitude, longitude: halte.longitude)
            let distance = CLLocation(latitude: userLocation.latitude, longitude: userLocation.longitude).distance(from: halteCoord)
            
            if distance <= 1300 {
                if seen.contains(halte.nom) {
                    print("[DEBUG] 🔁 Doublon ignoré : \(halte.nom)")
                    return nil
                }
                
                seen.insert(halte.nom)
                var updatedHalte = halte
                updatedHalte.distanceToUser = distance
                print("[DEBUG] ✅ Arrêt '\(halte.nom)' à \(Int(distance)) m")
                return updatedHalte
            } else {
                
                return nil
            }
        }
            .sorted { ($0.distanceToUser ?? 0) < ($1.distanceToUser ?? 0) }
        
        
        print("[DEBUG] 📌 Arrêts à proximité trouvés : \(result.count)")
        return result
    }
    
    
    
    var body: some View {
        ZStack {
            Color(hex: "#FAFAFD").ignoresSafeArea()
            
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    
                    // 🔵 TON TITRE/HEADER (ex-HStack)
                    HStack {
                        Image(systemName: "mappin.and.ellipse")
                            .foregroundColor(.blue)
                        Text(nomArret.isEmpty
                             ? "Choisis un arrêt"
                             : "\(nomArret) – \(computeNearbyHaltes().first { $0.nom == nomArret }?.distanceToUser.map { Int($0) } ?? 0)m")
                        .font(.headline)
                        .foregroundColor(.black)
                        Spacer()
                    }
                    .padding(.top, 12)
                    .padding(.horizontal, 24)
                    
                    // 📝 LE FORMULAIRE
                    formSection
                    
                    // 📤 BOUTON ENVOYER
                    envoyerButtonSection
                }
                .padding(.bottom, 20)
            }
        }
        
        .sheet(isPresented: $showImagePicker) {
            ImagePicker(selectedImage: $selectedUIImage, sourceType: useCamera ? .camera : .photoLibrary)
        }
        .sheet(isPresented: $showLijnPicker) {
            LijnPickerView(lignes: arretsVM.lignesPourArret) { selectedLine in
                ligne = selectedLine.lineid
                showLijnPicker = false
            }
            
        }
        .sheet(isPresented: $showArretPicker) {
            ScrollView {
                VStack(spacing: 12) {
                    Text("Choisis un arrêt")
                        .font(.headline)
                        .padding(.top, 16)
                    
                    let arretsUniques: [HalteModel] = Dictionary(grouping: arretsVM.arrets, by: { $0.nom }).compactMap { (_, value) in value.first }
                    
                    
                    
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
        .onAppear {
            lijnenVM.fetchLijnen()
            locationManager.requestLocation()
            arretsVM.fetchAllHaltes() // cette nouvelle fonction va charger TOUS les arrêts
        }
        .sheet(isPresented: $showAllNearbyStops) {
            NavigationView {
                ScrollView {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("Tous les arrêts à proximité")
                            .font(.headline)
                            .padding()
                        
                        ForEach(computeNearbyHaltes()) { halte in
                            halteButton(halte: halte)
                                .padding(.horizontal)
                        }
                    }
                }
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Fermer") {
                            showAllNearbyStops = false
                        }
                    }
                }
            }
        }
        
        
    }
    
    // MARK: - Sections
    private var formSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            
            // Nearby stop
            Text("Nearby stop")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            if arretsVM.arrets.isEmpty {
                HStack(spacing: 10) {
                    ProgressView()
                    Text("Recherche des arrêts à proximité...")
                        .font(.footnote)
                        .foregroundColor(.gray)
                }
            } else {
                VStack(spacing: 6) {
                    ForEach(computeNearbyHaltes().prefix(5)) { halte in
                        halteButton(halte: halte)
                    }
                    
                    if computeNearbyHaltes().count > 5 {
                        Button(action: {
                            showAllNearbyStops = true
                        }) {
                            Text("Voir tous les arrêts à proximité")
                                .font(.footnote)
                                .foregroundColor(.blue)
                                .padding(.top, 4)
                        }
                    }
                }
                
            }
            
            // Ligne si disponible
            if !nomArret.isEmpty && !arretsVM.lignesPourArret.isEmpty {
                LijnSelectieButton(ligne: ligne, lignes: arretsVM.lignesPourArret) {
                    showLijnPicker = true
                }
            }
            
            // Problème
            probleemSection
            
            // Description
            ZStack(alignment: .topLeading) {
                TextEditor(text: $description)
                    .padding(12)
                    .background(Color.white)
                    .cornerRadius(16)
                    .foregroundColor(.black)
                    .frame(minHeight: 120)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .stroke(Color.gray.opacity(0.3), lineWidth: 1)
                    )
                
                if description.isEmpty {
                    Text("Décrivez ici...")
                        .foregroundColor(.gray)
                        .padding(.top, 20)
                        .padding(.leading, 18)
                }
            }
            
            // Photo
            PhotoPickerSection(
                selectedUIImage: $selectedUIImage,
                showImagePicker: $showImagePicker,
                useCamera: $useCamera
            )
            
        }
        .padding(.horizontal, 14) // ✅ Un seul padding ici
    }
    
    
    private var probleemSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Quel est le souci ?")
                .font(.subheadline)
                .foregroundColor(.gray)
            
            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16),
                    GridItem(.flexible(), spacing: 16)
                ],
                spacing: 16
            ) {
                ForEach(ProbleemType.allCases.filter { $0 != .Autre }) { probleem in
                    let isSelected = selectedProbleem == probleem
                    
                    Button {
                        selectedProbleem = probleem
                    } label: {
                        VStack(spacing: 8) {
                            Image(systemName: probleem.icon)
                                .font(.system(size: 22, weight: .bold))
                                .foregroundColor(.white)
                            
                            Text(probleem.rawValue)
                                .font(.callout)
                                .foregroundColor(.white)
                                .multilineTextAlignment(.center)
                                .lineLimit(1)
                                .minimumScaleFactor(0.8)
                        }
                        .frame(maxWidth: .infinity, minHeight: 100)
                        .background(probleem.color.opacity(isSelected ? 1 : 0.7))
                        .cornerRadius(14)
                        .overlay(
                            RoundedRectangle(cornerRadius: 14)
                                .stroke(probleem.color.darker(by: 20), lineWidth: isSelected ? 2 : 0)
                        )
                        .shadow(color: isSelected ? probleem.color.darker(by: 30).opacity(0.3) : .clear,
                                radius: 4, x: 0, y: 2)
                        .scaleEffect(isSelected ? 1.05 : 1.0)
                        .animation(.easeInOut(duration: 0.15), value: selectedProbleem)
                    }
                }
            }
        }
        .padding(.horizontal, 9)
        
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
        .padding(.horizontal, 9)
    }
    @ViewBuilder
    private func halteButton(halte: HalteModel) -> some View {
        Button {
            nomArret = halte.nom
            ligne = "" // reset
            selectedArretId = halte.id
            showAllNearbyStops = false // ⬅️ ajoute cette ligne pour FERMER la sheet
            arretsVM.fetchLijnenPourArret(arretId: halte.id) {
                showLijnPicker = true
            }
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(halte.nom)
                        .font(.footnote)
                        .fontWeight(.medium)
                        .foregroundColor(.black)
                    if let distance = halte.distanceToUser {
                        Text(String(format: "%.0f m", distance))
                            .font(.caption2)
                            .foregroundColor(.gray)
                    }
                }
                Spacer()
            }
            .padding(.vertical, 8)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity)
            .background(nomArret == halte.nom ? Color.orange.opacity(0.4) : Color(UIColor.systemGray6))
            .cornerRadius(10)
        }
    }
    
    
    
}



