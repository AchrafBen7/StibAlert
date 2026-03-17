//
//  HalteParLigneView.swift
//  StibAlert
//
//  Created by studentehb on 28/04/2025.
//

 
import SwiftUI
 
struct HaltesParLigneView: View {
    let lineId: String
    @ObservedObject var authViewModel: AuthViewModel
    var onUpdateFavoris: () -> Void
    
    @StateObject private var viewModel = AlleHaltesViewModel()
    @Environment(\.presentationMode) var presentationMode
    @State private var favorisLocaux: Set<String> = [] // ici
    @State private var showToast = false
    @State private var toastMessage = ""
    
    var onClose: () -> Void
    
    
    var body: some View {
        ZStack {
            ScrollView {
                VStack(spacing: 12) {
                    ForEach(viewModel.arrets) { halte in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(halte.nom)
                                    .font(.body)
                                Text("ID: \(halte.stopId)")
                                    .font(.caption)
                                    .foregroundColor(.gray)
                            }
                            Spacer()
                            Button(action: {
                                if let userId = authViewModel.user?._id, let token = authViewModel.token {
                                    toggleFavori(arretId: halte._id, userId: userId, token: token)
                                }
                            }) {
                                Image(systemName: favorisLocaux.contains(halte._id) ? "star.fill" : "star")
                                    .foregroundColor(.yellow)
                            }
                        }
                        .padding()
                        .background(Color.white)
                        .cornerRadius(12)
                        .shadow(color: Color.black.opacity(0.05), radius: 3, x: 0, y: 2)
                        .padding(.horizontal)
                    }
                }
                .padding(.top)
            }
            
            if showToast {
                VStack {
                    Spacer()
                    Text(toastMessage)
                        .padding()
                        .background(Color.black.opacity(0.75))
                        .foregroundColor(.white)
                        .cornerRadius(10)
                        .padding(.bottom, 32)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                .animation(.easeInOut(duration: 0.3), value: showToast)
            }
        }
        .navigationTitle("Stopplaatsen \(lineId)")
        .onAppear {
            viewModel.fetchArrets(lineId: lineId)
            favorisLocaux = Set(authViewModel.user?.favoris ?? [])
            
        }
    }
    
    func toggleFavori(arretId: String, userId: String, token: String) {
        guard let url = URL(string: "https://stib-alert-backend.onrender.com/api/utilisateurs/\(userId)/favoris/\(arretId)") else { return }
        
        var request = URLRequest(url: url)
        request.httpMethod = "PATCH"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        
        URLSession.shared.dataTask(with: request) { _, _, error in
            DispatchQueue.main.async {
                if let error = error {
                    print("❌ Favoriete fout :", error.localizedDescription)
                    showTemporaryToast(message: "Fout bij toevoegen")
                } else {
                    if favorisLocaux.contains(arretId) {
                        favorisLocaux.remove(arretId)
                        showTemporaryToast(message: "Verwijderd uit favorieten ❌")
                    } else {
                        favorisLocaux.insert(arretId)
                        showTemporaryToast(message: "Toegevoegd aan favorieten ✅")
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) {
                            onUpdateFavoris()
                            onClose() 
                        }
                    }
                    
                }
            }
        }.resume()
    }
    
    func showTemporaryToast(message: String) {
        toastMessage = message
        showToast = true
        
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            showToast = false
        }
    }
}
