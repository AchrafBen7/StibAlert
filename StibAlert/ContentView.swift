import SwiftUI

struct ContentView: View {
    @StateObject private var authVM = AuthViewModel()
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 16) {
                    Image(systemName: "tram.fill")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 100, height: 100)
                        .foregroundStyle(.tint)
                    
                    Text("STIB Alert")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                    
                    Text("Modellen worden momenteel ontwikkeld...")
                        .font(.subheadline)
                        .foregroundColor(.secondary)
                    
                    NavigationLink(destination: MeldingenView()) {
                        Text("Bekijk alle meldingen")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.blue)
                            .cornerRadius(8)
                    }
                    
                    NavigationLink(destination: NewMeldingView()) {
                        Text("Nieuwe melding aanmaken")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.green)
                            .cornerRadius(8)
                    }
                    
                    NavigationLink(destination: LijnenLijstView()) {
                        Text("Bekijk alle lijnen")
                            .foregroundColor(.white)
                            .padding()
                            .frame(maxWidth: .infinity)
                            .background(Color.orange)
                            .cornerRadius(8)
                    }
                    
                    Spacer()
                    Group {
                        NavigationLink("S'inscrire", destination: RegistatieView(authVM: authVM))
                        NavigationLink("Activer le compte", destination: ActivationView(authVM: authVM))
                        NavigationLink("Connexion", destination: ConnexionView(authVM: authVM))
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.blue.opacity(0.1))
                    .cornerRadius(10)
                    
                    if authVM.isAuthenticated, let utilisateur = authVM.user {
                        Button("Déconnexion", role: .destructive) {
                            authVM.deconnexion()
                        }
                        .padding(.top)
                        
                        Text("🔓 Connecté en tant que \(utilisateur.email)")
                            .foregroundColor(.green)
                        
                        NavigationLink(destination: ProfilView(utilisateur: utilisateur)) {
                            Text("👤 Voir mon profil")
                                .foregroundColor(.white)
                                .padding()
                                .frame(maxWidth: .infinity)
                                .background(Color.purple)
                                .cornerRadius(8)
                        }
                        .padding(.top, 8)
                        Spacer()
                    } else {
                        Text("🔒 Non connecté")
                            .foregroundColor(.gray)
                        Spacer(minLength: 20)
                    }
                    
                    
                }
                .padding()
                .navigationTitle("Authentification")
                .onAppear {
                    authVM.verifierConnexion()
                }

            }
        }
        
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
