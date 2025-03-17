import SwiftUI

struct ContentView: View {
    var body: some View {
        NavigationView {
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
                
                // Navigatielink naar de lijst met meldingen
                NavigationLink(destination: MeldingenView()) {
                    Text("Bekijk alle meldingen")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.blue)
                        .cornerRadius(8)
                }
                
                // Navigatielink naar de nieuwe melding creatie
                NavigationLink(destination: NewMeldingView()) {
                    Text("Nieuwe melding aanmaken")
                        .foregroundColor(.white)
                        .padding()
                        .frame(maxWidth: .infinity)
                        .background(Color.green)
                        .cornerRadius(8)
                }
                // Navigatielink naar de lijst met lijnen
                                NavigationLink(destination: LijnenLijstView()) {
                                    Text("Bekijk alle lijnen")
                                        .foregroundColor(.white)
                                        .padding()
                                        .frame(maxWidth: .infinity)
                                        .background(Color.orange)
                                        .cornerRadius(8)
                                }
            }
            .padding()
            .navigationTitle("Startpagina")
        }
    }
}

struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
